`timescale 1ns/1ps
// RFC1350 octet-mode client. Bounded storage, RRQ/WRQ, stop-and-wait,
// retransmission, duplicate suppression, final zero block and final-ACK dally.
module afdx_tftp_client #(
 parameter integer MAX_FILE_BYTES=4096,
 parameter integer TIMEOUT_CYCLES=100000000,
 parameter integer MAX_RETRIES=3,
 parameter integer CLK_HZ=TIMEOUT_CYCLES,MAX_WAIT_RESPONSES=8
)(
 input wire clk,rst,start,read_not_write,
 input wire [31:0] server_ip,input wire [15:0] local_tid,
 input wire [5:0] filename_length,input wire [255:0] filename,
 input wire [15:0] put_length,output wire [15:0] put_address,input wire [7:0] put_data,
 output reg tx_valid,input wire tx_ready,output reg [10:0] tx_length,output reg [4127:0] tx_bytes,
 output wire [31:0] tx_destination_ip,output reg [15:0] tx_source_port,tx_destination_port,
 input wire rx_valid,input wire [31:0] rx_source_ip,input wire [15:0] rx_source_port,rx_destination_port,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes,
 output wire busy,output reg done,error,file_valid,
 output reg [15:0] file_length,output reg [31:0] file_crc,
 input wire [15:0] read_address,output wire [7:0] read_data,
 output reg [31:0] retries,duplicates,rejected,
 output wire idle,output wire wait_active,output reg remote_abort,
 output reg [15:0] error_code,abort_status
);
localparam IDLE=0,WAITING=1,COPY_READ=2,FILL_WRITE=3,DALLY=4,WAIT_DELAY=5;
wire wait_message,abort_message;wire [15:0] wait_seconds,decoded_abort;
afdx_615a_tftp_error error_decode(.length(rx_length),.bytes(rx_bytes),
 .wait_message(wait_message),.abort_message(abort_message),.wait_seconds(wait_seconds),.abort_status(decoded_abort));
reg [15:0] seconds_left;reg [31:0] second_ticks;reg [7:0] wait_count;
reg [2:0] state;
assign idle=state==IDLE&&!tx_valid;
assign wait_active=state==WAIT_DELAY;
reg get_mode,peer_known,final_block,tx_auxiliary;
reg [31:0] peer_ip,timer,crc;reg [15:0] peer_tid,block_number,offset,size_q;
reg [9:0] data_count,index;reg [7:0] memory[0:MAX_FILE_BYTES-1];reg [4095:0] read_packet;
reg [4127:0] last_packet;reg [10:0] last_length;reg [7:0] attempts;
reg [63:0] no_progress;reg budget_running;
wire [15:0] opcode={rx_bytes[7:0],rx_bytes[15:8]};
wire [15:0] rx_block={rx_bytes[23:16],rx_bytes[31:24]};
wire rx_peer=rx_valid&&!tx_valid&&rx_source_ip==peer_ip&&rx_destination_port==tx_source_port&&
 rx_source_port!=0&&(!peer_known||rx_source_port==peer_tid)&&rx_length>=4&&rx_length<=516;
wire rx_progress=rx_peer&&state==WAITING&&
 ((get_mode&&opcode==3&&rx_block==block_number)||(!get_mode&&opcode==4&&rx_length==4&&rx_block==block_number));
wire rx_error_packet=rx_peer&&opcode==5&&rx_length>=5&&rx_bytes[(rx_length-1)*8+:8]==0&&state!=DALLY;
wire deadline=(state==WAITING||state==DALLY)&&(!tx_valid||tx_auxiliary)&&timer>=TIMEOUT_CYCLES-1;
wire exhausted=(state==WAITING||state==DALLY)&&budget_running&&
 no_progress>=(state==DALLY?64'd1*TIMEOUT_CYCLES:64'd1*(TIMEOUT_CYCLES+4)*(MAX_RETRIES+1))-1;
wire [15:0] block_size=size_q-offset>=512?16'd512:size_q-offset;
assign busy=state!=IDLE && state!=DALLY;
assign put_address=offset+index;
assign read_data=file_valid&&read_address<file_length?memory[read_address]:8'd0;
assign tx_destination_ip=peer_ip;
function [31:0] crc_byte;input [31:0] c;input [7:0] b;reg [31:0] v;integer k;begin
 v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;
end endfunction
wire [31:0] next_crc=crc_byte(crc,read_packet[index*8+:8]);

integer i;
task ack;input [15:0] number;begin
 tx_bytes<=0;tx_bytes[15:8]<=4;tx_bytes[23:16]<=number[15:8];tx_bytes[31:24]<=number[7:0];tx_length<=4;tx_valid<=1;
 last_packet<=0;last_packet[15:8]<=4;last_packet[23:16]<=number[15:8];last_packet[31:24]<=number[7:0];last_length<=4;
end endtask
task fail_transfer;begin state<=IDLE;error<=1;done<=1;file_valid<=0;tx_valid<=0;end endtask
always @(posedge clk)begin
 if(rst)begin
  remote_abort<=0;error_code<=0;abort_status<=0;seconds_left<=0;second_ticks<=0;wait_count<=0;state<=IDLE;get_mode<=0;peer_known<=0;final_block<=0;peer_ip<=0;peer_tid<=0;block_number<=0;offset<=0;size_q<=0;
  timer<=0;crc<=32'hffffffff;data_count<=0;index<=0;read_packet<=0;last_packet<=0;last_length<=0;attempts<=0;tx_auxiliary<=0;no_progress<=0;budget_running<=0;
  tx_valid<=0;tx_length<=0;tx_bytes<=0;tx_source_port<=0;tx_destination_port<=0;
  done<=0;error<=0;file_valid<=0;file_length<=0;file_crc<=0;retries<=0;duplicates<=0;rejected<=0;
 end else begin
  done<=0;remote_abort<=0;
  if(budget_running&&(state==WAITING||state==DALLY))no_progress<=no_progress+1'b1;
  if(tx_valid&&tx_ready)begin tx_valid<=0;if(!tx_auxiliary)begin timer<=0;budget_running<=1;end end
  if(start&&!busy&&!tx_valid)begin
   error_code<=0;abort_status<=0;wait_count<=0;final_block<=0;tx_auxiliary<=0;no_progress<=0;budget_running<=0;
   file_valid<=0;file_length<=0;file_crc<=0;error<=0;peer_ip<=server_ip;get_mode<=read_not_write;peer_known<=0;peer_tid<=0;
   block_number<=read_not_write?16'd1:16'd0;offset<=0;size_q<=put_length;crc<=32'hffffffff;timer<=0;attempts<=0;
   tx_source_port<=local_tid;tx_destination_port<=69;tx_bytes<=0;last_packet<=0;
   if(filename_length<1||filename_length>31||local_tid==0||(!read_not_write&&put_length>MAX_FILE_BYTES))begin error_code<=16'h8002;fail_transfer;end
   else begin
    tx_bytes[15:8]<=read_not_write?1:2;last_packet[15:8]<=read_not_write?1:2;
    for(i=0;i<32;i=i+1)if(i<filename_length)begin tx_bytes[(2+i)*8+:8]<=filename[i*8+:8];last_packet[(2+i)*8+:8]<=filename[i*8+:8];end
    tx_bytes[(3+filename_length)*8+:40]<=40'h746574636f;last_packet[(3+filename_length)*8+:40]<=40'h746574636f;
    tx_length<=9+filename_length;last_length<=9+filename_length;tx_valid<=1;state<=WAITING;
   end
  end else begin
   // Auxiliary replies consume the budget even while queued.
   if(exhausted&&!rx_progress&&!rx_error_packet)begin
    if(state==DALLY)begin state<=IDLE;tx_valid<=0;end
    else begin error_code<=16'h8001;fail_transfer;end
   end else if((state==WAITING||state==DALLY)&&(!tx_valid||tx_auxiliary)&&!rx_progress&&!rx_error_packet)begin
    if(deadline&&!tx_valid)begin
     if(state==DALLY)state<=IDLE;
     else if(attempts>=MAX_RETRIES)begin error_code<=16'h8001;fail_transfer;end
     else begin
      tx_bytes<=last_packet;tx_length<=last_length;tx_valid<=1;tx_auxiliary<=0;tx_destination_port<=peer_known?peer_tid:16'd69;
      attempts<=attempts+1'b1;retries<=retries+1'b1;timer<=0;
     end
    end else if(!deadline)timer<=timer+1'b1;
   end
   if(state==WAIT_DELAY)begin
    if(seconds_left==0)begin
     tx_bytes<=last_packet;tx_length<=last_length;tx_destination_port<=peer_known?peer_tid:16'd69;tx_valid<=1;tx_auxiliary<=0;
     timer<=0;no_progress<=0;budget_running<=0;state<=WAITING;retries<=retries+1'b1;
    end else if(second_ticks>=CLK_HZ-1)begin second_ticks<=0;seconds_left<=seconds_left-1'b1;end
    else second_ticks<=second_ticks+1'b1;
   end
   if(state==COPY_READ)begin
    if(data_count!=0)begin memory[offset+index]<=read_packet[index*8+:8];crc<=next_crc;end
    if(data_count==0 || index==data_count-1)begin
     ack(block_number);tx_destination_port<=peer_tid;timer<=0;attempts<=0;tx_auxiliary<=0;no_progress<=0;budget_running<=0;
     offset<=offset+data_count;
     if(data_count<512)begin file_length<=offset+data_count;file_crc<=~(data_count==0?crc:next_crc);file_valid<=1;done<=1;state<=DALLY;end
     else begin block_number<=block_number+1'b1;state<=WAITING;end
    end else index<=index+1'b1;
   end
   if(state==FILL_WRITE)begin
    if(block_size!=0)begin tx_bytes[(4+index)*8+:8]<=put_data;last_packet[(4+index)*8+:8]<=put_data;end
    if(block_size==0||index==block_size-1)begin
     tx_length<=4+block_size;last_length<=4+block_size;tx_valid<=1;tx_auxiliary<=0;tx_destination_port<=peer_tid;timer<=0;attempts<=0;
     data_count<=block_size;final_block<=block_size<512;state<=WAITING;
    end else index<=index+1'b1;
   end
   // Expected blocks and peer ERRORs win the deadline; other packets lose it.
   if(rx_valid&&(state==WAITING||state==DALLY||state==WAIT_DELAY)&&!tx_valid&&(!(deadline||exhausted)||rx_progress||rx_error_packet))begin
    if(rx_source_ip!=peer_ip||rx_destination_port!=tx_source_port||rx_source_port==0||rx_length<4||rx_length>516)rejected<=rejected+1'b1;
    else if(peer_known&&rx_source_port!=peer_tid)begin
     // RFC1350 unknown TID error without destroying the established transfer.
     rejected<=rejected+1'b1;tx_bytes<=0;tx_bytes[15:8]<=5;tx_bytes[31:24]<=5;tx_length<=5;tx_destination_port<=rx_source_port;tx_valid<=1;tx_auxiliary<=1;
    end else if(opcode==5)begin
     if(rx_length<5||rx_bytes[(rx_length-1)*8+:8]!=0)rejected<=rejected+1'b1;
     else if(state==DALLY)rejected<=rejected+1'b1;
     else if(wait_message&&state==WAITING)begin
      if(wait_count>=MAX_WAIT_RESPONSES)begin error_code<=16'h8003;fail_transfer;end
      else begin seconds_left<=wait_seconds;second_ticks<=0;wait_count<=wait_count+1'b1;state<=WAIT_DELAY;timer<=0;end
     end else begin
      error_code<=rx_block;abort_status<=abort_message?decoded_abort:16'd0;
      remote_abort<=abort_message;fail_transfer;
     end
    end
    else if(get_mode&&opcode==3&&state!=WAIT_DELAY)begin
     if((state==DALLY&&rx_block==block_number)||(state==WAITING&&peer_known&&rx_block==block_number-1'b1))begin
      duplicates<=duplicates+1'b1;ack(rx_block);tx_destination_port<=rx_source_port;tx_auxiliary<=1;
     end else if(state==WAITING&&rx_block==block_number)begin
      if({1'b0,offset}+rx_length-4>MAX_FILE_BYTES)begin error_code<=16'h8004;fail_transfer;end
      else begin
       peer_tid<=rx_source_port;peer_known<=1;read_packet<=rx_bytes[4127:32];data_count<=rx_length-4;index<=0;state<=COPY_READ;no_progress<=0;budget_running<=0;
      end
     end else rejected<=rejected+1'b1;
    end else if(!get_mode&&opcode==4&&rx_length==4&&state==WAITING)begin
     if(rx_block==block_number)begin
      peer_tid<=rx_source_port;peer_known<=1;no_progress<=0;budget_running<=0;
      if(block_number!=0&&final_block)begin done<=1;error<=0;file_length<=size_q;state<=IDLE;end
      else begin
       if(block_number!=0)offset<=offset+data_count;
       block_number<=block_number+1'b1;index<=0;tx_bytes<=0;last_packet<=0;
       tx_bytes[15:8]<=3;last_packet[15:8]<=3;
       tx_bytes[23:16]<=(block_number+16'd1)>>8;tx_bytes[31:24]<=block_number+16'd1;
       last_packet[23:16]<=(block_number+16'd1)>>8;last_packet[31:24]<=block_number+16'd1;state<=FILL_WRITE;
      end
     end else if(peer_known&&rx_block==block_number-1'b1)duplicates<=duplicates+1'b1;
     else rejected<=rejected+1'b1;
    end else rejected<=rejected+1'b1;
   end
  end
 end
end
endmodule

