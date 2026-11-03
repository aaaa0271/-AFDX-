`timescale 1ns/1ps
// Bounded A4 target download: LNO/LNL/LNA and LND/LNR, followed by
// target-initiated file WRQs and LNS. Only committed package files are exposed.
// Protocol field references and deliberately unsupported options: docs/DOWNLOAD_615A.md.
//
// ELABORATION-FRIENDLY REVISION (memory-based packet/name storage):
// runtime-variable part-selects on the 4096-bit protocol buffer and 256-bit
// name regs are replaced with indexed memory accesses, which keep Quartus
// elaboration bounded. Behaviour is unchanged; the module port list and the
// state machine are the same as the original afdx_615a_download.
module afdx_615a_download #(
 parameter integer TIMEOUT_CYCLES=100000000,CLK_HZ=TIMEOUT_CYCLES
)(
 input wire clk,rst,input wire [31:0] loader_ip,input wire upload_busy,
 input wire package_valid,input wire [2:0] file_count,
 output reg [1:0] read_file,output wire [15:0] read_address,
 input wire [255:0] read_name,input wire [15:0] read_length,input wire [7:0] read_data,
 input wire rx_valid,input wire [31:0] rx_ip,input wire [15:0] rx_sport,rx_dport,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes,
 output wire tx_valid,input wire tx_ready,output wire [31:0] tx_ip,
 output wire [15:0] tx_sport,tx_dport,output wire [10:0] tx_length,output wire [4127:0] tx_bytes,
 output wire active,idle,output reg complete,failed
);
localparam OFF=0,SCAN=1,INIT=2,ACCEPT=3,LIST=4,SELECT=5,PROGRESS=6,FILE=7,FINAL=8,DRAIN=9;
localparam C_OFF=0,C_INIT=1,C_DATA=2,C_DALLY=3;
reg [3:0] state;reg [1:0] cs;reg operator_mode;
reg [7:0] names_mem[0:3][0:31];reg [5:0] name_sizes[0:3];reg [15:0] sizes[0:3];reg [2:0] count;
reg [1:0] selection[0:3];reg [2:0] selected_count,current,finished_files;
reg [15:0] status_code,status_counter,control_peer;
reg [31:0] peer_ip,timer,select_timer;reg [63:0] control_budget;reg [2:0] attempts;
reg cv;wire cr;reg [15:0] cd;reg [10:0] cl,last_len;reg [4127:0] cb,last_packet;
reg c_aux,c_failed,c_accepted,init_acked;
reg [4127:0] accepted_selection;reg [10:0] accepted_length;
reg start_client,client_inflight;wire client_busy,client_done,client_error,client_idle;
wire fv,fr;wire [31:0] fi;wire [15:0] fs,fd,put_address;wire [10:0] fl;wire [4127:0] fb;
reg [5:0] transfer_name_size;reg [255:0] transfer_name;reg [15:0] transfer_size;
reg [7:0] pf_mem[0:511];reg data_transfer;
reg [1:0] owner;
wire [15:0] op={rx_bytes[7:0],rx_bytes[15:8]},block_number={rx_bytes[23:16],rx_bytes[31:24]};
wire request_shape=rx_length==19&&rx_bytes[12*8+:8]==0&&rx_bytes[13*8+:48]==48'h00746574636f;
wire req_lno=rx_bytes[2*8+:80]==80'h4f4e4c2e544547524154;
wire req_lnd=rx_bytes[2*8+:80]==80'h444e4c2e544547524154;
wire req_lna=rx_bytes[2*8+:80]==80'h414e4c2e544547524154;
wire req_lnr=rx_bytes[2*8+:80]==80'h524e4c2e544547524154;
wire peer=rx_valid&&rx_ip==peer_ip&&rx_sport!=0;
wire control_peer_packet=peer&&rx_dport==44000&&rx_sport==control_peer&&!cv;
wire control_progress=control_peer_packet&&((cs==C_INIT&&op==4&&block_number==1&&rx_length==4)||
 (cs==C_DATA&&op==3&&block_number==1&&rx_length>=12&&rx_length<=148)||(op==5&&rx_length>=5&&b(rx_length-1)==0));
wire wait_message,abort_message;wire [15:0] wait_seconds,abort_status;
afdx_615a_tftp_error decode_error(.length(rx_length),.bytes(rx_bytes),.wait_message(wait_message),
 .abort_message(abort_message),.wait_seconds(wait_seconds),.abort_status(abort_status));
assign active=state!=OFF;
assign idle=state==OFF&&cs==C_OFF&&!cv&&client_idle&&owner==0;
assign read_address=put_address;
assign tx_valid=owner==1?cv:owner==2?fv:1'b0;
assign tx_ip=owner==1?peer_ip:fi;
assign tx_sport=owner==1?16'd44000:fs;
assign tx_dport=owner==1?cd:fd;
assign tx_length=owner==1?cl:fl;
assign tx_bytes=owner==1?cb:fb;
assign cr=owner==1&&tx_ready;assign fr=owner==2&&tx_ready;
reg [7:0] put_data_r;
always @*begin put_data_r=data_transfer?read_data:(put_address<512?pf_mem[put_address]:8'd0);end
wire [7:0] put_data=put_data_r;
afdx_tftp_client #(.MAX_FILE_BYTES(4096),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CLK_HZ(CLK_HZ)) sender(
 .clk(clk),.rst(rst),.start(start_client),.read_not_write(1'b0),.server_ip(peer_ip),.local_tid(16'd44001),
 .filename_length(transfer_name_size),.filename(transfer_name),.put_length(transfer_size),.put_address(put_address),.put_data(put_data),
 .tx_valid(fv),.tx_ready(fr),.tx_length(fl),.tx_bytes(fb),.tx_destination_ip(fi),.tx_source_port(fs),.tx_destination_port(fd),
 .rx_valid(rx_valid&&rx_dport==44001),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_destination_port(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
 .busy(client_busy),.done(client_done),.error(client_error),.idle(client_idle),.file_valid(),.file_length(),.file_crc(),
 .read_address(16'd0),.read_data(),.retries(),.duplicates(),.rejected());
function [7:0] b;input integer p;begin b=(p>=0&&p<516)?rx_bytes[p*8+:8]:8'd0;end endfunction
// Parse a complete one-block LNA/LNR before acknowledging it. Names must
// match the snapshotted committed directory, with no duplicates or aliases.
// Bytes are pulled through the pbyte array so no runtime-variable part-select
// on the wide rx_bytes vector is elaborated.
integer pgi;
reg [7:0] pbyte[0:515];
always @*begin for(pgi=0;pgi<516;pgi=pgi+1)pbyte[pgi]=rx_bytes[pgi*8+:8];end
integer i,j,k,n,pos,match_index,parsed_count,eq;reg valid_selection;reg [3:0] seen;
reg [1:0] parsed_selection[0:3];reg [7:0] cand[0:31];
always @*begin
 parsed_count={pbyte[10],pbyte[11]};pos=12;seen=0;
 for(k=0;k<32;k=k+1)cand[k]=0;
 valid_selection=rx_length>=12&&rx_length<=148&&{pbyte[4],pbyte[5],pbyte[6],pbyte[7]}==rx_length-4&&pbyte[8]=="A"&&pbyte[9]=="4"&&parsed_count>0&&parsed_count<=count;
 for(i=0;i<4;i=i+1)begin
  parsed_selection[i]=0;
  if(i<parsed_count)begin
   n=pbyte[pos];pos=pos+1;
   if(n<2||n>32||pos+n>rx_length||pbyte[pos+n-1]!=0)valid_selection=0;
   for(j=0;j<32;j=j+1)if(j<n-1)cand[j]=pbyte[pos+j];
   match_index=-1;
   for(j=0;j<4;j=j+1)if(j<count&&match_index<0&&name_sizes[j]==n-1)begin
    eq=1;
    for(k=0;k<32;k=k+1)if(names_mem[j][k]!=cand[k])eq=0;
    if(eq)match_index=j;
   end
   if(match_index<0)valid_selection=0;
   else begin if(seen[match_index])valid_selection=0;seen[match_index]=1;parsed_selection[i]=match_index;end
   pos=pos+n;
  end
 end
 if(!operator_mode)begin if(pbyte[pos]!=0)valid_selection=0;pos=pos+1;end
 if(pos!=rx_length)valid_selection=0;
end
task control_error;input [15:0] code;input [15:0] destination;begin
 cb<=0;cb[15:8]<=5;cb[23:16]<=code[15:8];cb[31:24]<=code[7:0];cl<=5;cd<=destination;cv<=1;c_aux<=1;
end endtask
task control_ack;input [15:0] number;begin
 cb<=0;cb[15:8]<=4;cb[23:16]<=number[15:8];cb[31:24]<=number[7:0];cl<=4;cd<=control_peer;cv<=1;c_aux<=0;
 last_packet<=0;last_packet[15:8]<=4;last_packet[23:16]<=number[15:8];last_packet[31:24]<=number[7:0];last_len<=4;
end endtask
task envelope;input integer length;begin
 for(k=0;k<512;k=k+1)pf_mem[k]=0;
 pf_mem[0]=length>>24;pf_mem[1]=length>>16;pf_mem[2]=length>>8;pf_mem[3]=length;
 pf_mem[4]="A";pf_mem[5]="4";
end endtask
integer q,z,cursor,ns,total;reg [15:0] per_status;
task send_protocol;input [79:0] filename;input integer length;begin
 transfer_name<={176'd0,filename};transfer_name_size<=10;transfer_size<=length;data_transfer<=0;start_client<=1;client_inflight<=1;
end endtask
task make_status;input [15:0] code;begin
 total=20;
 for(q=0;q<4;q=q+1)if(q<selected_count)total=total+name_sizes[selection[q]]+5;
 envelope(total);pf_mem[6]=code[15:8];pf_mem[7]=code[7:0];
 // Empty description (one length byte), counter, exception timer, estimate,
 // three ASCII ratio bytes, uint16 file count.
 pf_mem[9]=status_counter[15:8];pf_mem[10]=status_counter[7:0];
 pf_mem[15]=code==3?"1":"0";pf_mem[16]="0";pf_mem[17]="0";
 pf_mem[19]=selected_count;cursor=20;
 for(q=0;q<4;q=q+1)if(q<selected_count)begin
  ns=name_sizes[selection[q]];pf_mem[cursor]=ns+1;cursor=cursor+1;
  for(z=0;z<32;z=z+1)if(z<ns)pf_mem[cursor+z]=names_mem[selection[q]][z];
  cursor=cursor+ns+1;per_status=q<finished_files?16'd3:code;
  pf_mem[cursor]=per_status[15:8];pf_mem[cursor+1]=per_status[7:0];cursor=cursor+3;
 end
 status_counter<=status_counter+1'b1;send_protocol(80'h534e4c2e544547524154,total);
end endtask
reg [7:0] name_pick[0:31];
always @*begin for(pgi=0;pgi<32;pgi=pgi+1)name_pick[pgi]=names_mem[selection[current]][pgi];end
always @(posedge clk)begin
 if(rst)begin
  state<=OFF;cs<=C_OFF;operator_mode<=0;count<=0;selected_count<=0;current<=0;finished_files<=0;
  read_file<=0;status_code<=0;status_counter<=0;control_peer<=0;peer_ip<=0;timer<=0;select_timer<=0;control_budget<=0;attempts<=0;
  accepted_selection<=0;accepted_length<=0;cv<=0;cd<=0;cl<=0;cb<=0;last_len<=0;last_packet<=0;c_aux<=0;c_failed<=0;c_accepted<=0;init_acked<=0;
  start_client<=0;client_inflight<=0;transfer_name_size<=0;transfer_name<=0;transfer_size<=0;data_transfer<=0;owner<=0;complete<=0;failed<=0;
  for(k=0;k<4;k=k+1)begin name_sizes[k]<=0;sizes[k]<=0;selection[k]<=0;for(z=0;z<32;z=z+1)names_mem[k][z]<=0;end
  for(k=0;k<512;k=k+1)pf_mem[k]<=0;
 end else begin
  start_client<=0;c_accepted<=0;init_acked<=0;c_failed<=0;
  if(owner==0)begin if(cv)owner<=1;else if(fv)owner<=2;end
  else if((tx_valid&&tx_ready)||(owner==1&&!cv)||(owner==2&&!fv&&!client_busy))owner<=0;
  if(cv&&cr)begin cv<=0;if(!c_aux)timer<=0;end
  if(cs!=C_OFF)begin
   control_budget<=control_budget+1'b1;
   if(!cv||c_aux)timer<=timer+1'b1;
   if(control_progress&&cs!=C_DALLY)begin timer<=0;control_budget<=0;attempts<=0;end
   else if(control_budget>=64'd4*(TIMEOUT_CYCLES+4)-1)begin
    cs<=C_OFF;cv<=0;if(cs!=C_DALLY)c_failed<=1;
   end else if((!cv||c_aux)&&timer>=TIMEOUT_CYCLES-1)begin
    timer<=0;
    if(cs==C_DALLY)cs<=C_OFF;
    else if(attempts==3||control_budget>=64'd4*(TIMEOUT_CYCLES+4))begin cs<=C_OFF;c_failed<=1;end
    else if(!cv)begin cb<=last_packet;cl<=last_len;cd<=control_peer;cv<=1;c_aux<=0;attempts<=attempts+1'b1;end
   end
  end
  if(control_peer_packet&&op==5&&rx_length>=5&&b(rx_length-1)==0&&cs!=C_DALLY)begin
   cs<=C_OFF;c_failed<=1;status_code<=abort_message?abort_status:16'h1003;
  end else if(control_peer_packet&&cs==C_INIT&&op==4&&block_number==1&&rx_length==4)begin cs<=C_OFF;init_acked<=1;end
  else if(control_peer_packet&&(cs==C_DATA||cs==C_DALLY)&&op==3&&block_number==1)begin
   if(cs==C_DALLY)begin
    if(rx_length==accepted_length&&rx_bytes==accepted_selection)control_ack(1);
    else control_error(4,control_peer);
   end
   else if(valid_selection)begin
    accepted_selection<=rx_bytes;accepted_length<=rx_length;
    control_ack(1);cs<=C_DALLY;c_accepted<=1;selected_count<=parsed_count;
    for(k=0;k<4;k=k+1)selection[k]<=parsed_selection[k];
   end else begin control_error(4,control_peer);cs<=C_OFF;c_failed<=1;end
  end else if(peer&&rx_dport==44000&&rx_sport!=control_peer&&!cv)control_error(5,rx_sport);
  if(rx_valid&&rx_ip==loader_ip&&rx_sport!=0&&rx_dport==69&&!cv)begin
   if(request_shape&&op==1&&(req_lno||req_lnd)&&state==OFF&&client_idle&&cs==C_OFF)begin
    peer_ip<=loader_ip;control_peer<=rx_sport;cd<=rx_sport;complete<=0;failed<=0;
    if(upload_busy||!package_valid||file_count==0||file_count>4)control_error(4,rx_sport);
    else begin operator_mode<=req_lno;count<=file_count;read_file<=0;state<=SCAN;selected_count<=0;finished_files<=0;current<=0;status_counter<=0;status_code<=16'h1003;end
   end else if(request_shape&&op==1&&(req_lno||req_lnd)&&state==INIT&&cs==C_INIT&&rx_sport==control_peer&&
               ((operator_mode&&req_lno)||(!operator_mode&&req_lnd)))begin
    cb<=last_packet;cl<=last_len;cd<=control_peer;cv<=1;c_aux<=1;
   end else if(request_shape&&op==2&&(req_lna||req_lnr)&&state==SELECT&&cs==C_OFF&&((operator_mode&&req_lna)||(!operator_mode&&req_lnr)))begin
    control_peer<=rx_sport;cb<=0;cb[15:8]<=4;cl<=4;cd<=rx_sport;cv<=1;c_aux<=0;
    last_packet<=0;last_packet[15:8]<=4;last_len<=4;cs<=C_DATA;timer<=0;control_budget<=0;attempts<=0;
   end else if(request_shape&&op==2&&(req_lna||req_lnr)&&cs==C_DATA&&rx_sport==control_peer)begin cb<=last_packet;cl<=last_len;cd<=control_peer;cv<=1;c_aux<=1;end
   else control_error(4,rx_sport);
  end
  if(client_done)client_inflight<=0;
  if(c_failed&&state!=OFF&&state!=FINAL&&state!=DRAIN)begin failed<=1;state<=FINAL;status_code<=16'h1003;end
  else if(client_done&&client_error&&state!=FINAL)begin failed<=1;state<=FINAL;status_code<=16'h1003;end
  else case(state)
   OFF:begin end
   SCAN:begin
    for(q=0;q<32;q=q+1)names_mem[read_file][q]<=read_name[q*8+:8];
    sizes[read_file]<=read_length;ns=0;
    for(q=0;q<32;q=q+1)if(read_name[q*8+:8]!=0&&ns==q)ns=ns+1;
    name_sizes[read_file]<=ns;
    if(ns<1||ns>31||read_length>4096||
       read_name=={176'd0,80'h534e4c2e544547524154}||
       read_name=={176'd0,80'h4c4e4c2e544547524154})begin
     control_error(4,control_peer);failed<=1;state<=DRAIN;
    end
    else if({1'b0,read_file}+1==count)begin
     cb<=0;cb[15:8]<=3;cb[31:24]<=1;cb[7*8+:8]<=9;cb[8*8+:8]<="A";cb[9*8+:8]<="4";cb[11*8+:8]<=1;
     last_packet<=0;last_packet[15:8]<=3;last_packet[31:24]<=1;last_packet[7*8+:8]<=9;last_packet[8*8+:8]<="A";last_packet[9*8+:8]<="4";last_packet[11*8+:8]<=1;
     cv<=1;c_aux<=0;cl<=13;last_len<=13;cd<=control_peer;cs<=C_INIT;timer<=0;control_budget<=0;attempts<=0;state<=INIT;
    end else read_file<=read_file+1'b1;
   end
   INIT:if(init_acked)state<=ACCEPT;
   ACCEPT:if(!client_inflight&&client_idle)make_status(1);
    else if(client_done&&!client_error)begin state<=operator_mode?LIST:SELECT;select_timer<=0;end
   LIST:if(!client_inflight&&client_idle)begin
    total=8;for(q=0;q<4;q=q+1)if(q<count)total=total+name_sizes[q]+3;
    envelope(total);pf_mem[7]=count;cursor=8;
    for(q=0;q<4;q=q+1)if(q<count)begin ns=name_sizes[q];pf_mem[cursor]=ns+1;cursor=cursor+1;
     for(z=0;z<32;z=z+1)if(z<ns)pf_mem[cursor+z]=names_mem[q][z];cursor=cursor+ns+2;end
    send_protocol(80'h4c4e4c2e544547524154,total);
   end else if(client_done&&!client_error)begin state<=SELECT;select_timer<=0;end
   SELECT:begin
    if(cs==C_OFF)select_timer<=select_timer+1'b1;
    if(c_accepted)begin state<=PROGRESS;current<=0;finished_files<=0;end
    else if(cs==C_OFF&&select_timer>=TIMEOUT_CYCLES*4-1)begin failed<=1;state<=FINAL;status_code<=16'h1003;end
   end
   PROGRESS:if(!client_inflight&&client_idle)make_status(2);
    else if(client_done&&!client_error)begin read_file<=selection[current];state<=FILE;end
   FILE:if(!client_inflight&&client_idle)begin
    transfer_name_size<=name_sizes[selection[current]];transfer_size<=sizes[selection[current]];
    for(q=0;q<32;q=q+1)transfer_name[q*8+:8]<=name_pick[q];
    data_transfer<=1;start_client<=1;client_inflight<=1;
   end else if(client_done&&!client_error)begin
    finished_files<=finished_files+1'b1;
    if(current+1==selected_count)begin state<=FINAL;status_code<=3;end
    else begin current<=current+1'b1;state<=PROGRESS;end
   end
   FINAL:if(!client_inflight&&client_idle)make_status(status_code);
    else if(client_done)begin if(client_error)failed<=1;else if(status_code==3)complete<=1;state<=DRAIN;end
   DRAIN:if(!cv&&client_idle&&cs==C_OFF&&owner==0)state<=OFF;
  endcase
 end
end
endmodule
