`timescale 1ns/1ps
// Four VLs, two complete UDP messages per VL. UDP payload capacity is 8192.
// Fragment offsets address the UDP datagram (header included), never the app
// payload alone. All non-final fragments are multiples of eight octets.
module afdx_datagram_tx #(
 parameter integer MAX_MESSAGE=8192,SUBVL_MAX_MESSAGE=2048,EXTENDED_PORTS=0,
 parameter integer PORTS=EXTENDED_PORTS?16:4,
 parameter [3:0] SAMPLING_MASK=0,
 parameter [47:0] SOURCE_MAC=48'h020000000010
)(
 input wire clk,rst,tx_enable,network_a_enable,network_b_enable,
 input wire [671:0] network_cfg,input wire [1023:0] port_cfg,input wire [1:0] app_wr_subvl,
 input wire cfg_we,input wire [1:0] cfg_vl_id,input wire [31:0] cfg_bag,input wire [15:0] cfg_lmax,
 input wire app_wr_en,input wire [1:0] app_wr_vl_id,input wire [7:0] app_wr_data,
 input wire [15:0] app_wr_len,input wire app_wr_sof,app_wr_eof,
 output wire app_wr_ready,app_wr_accept,output reg app_len_error,
 output wire [7:0] a_data,b_data,output wire a_en,b_en,a_er,b_er,a_done,b_done,
 output wire busy,output reg [31:0] messages,frames,errors
);
localparam MEMORY_BYTES=12*MAX_MESSAGE+(PORTS-4)*3*SUBVL_MAX_MESSAGE;
reg [7:0] memory[0:MEMORY_BYTES-1];
function [15:0] port_capacity;input [3:0] p;begin port_capacity=p<4?MAX_MESSAGE:SUBVL_MAX_MESSAGE;end endfunction
function integer message_address;input [3:0] p;input [1:0] q;input [15:0] offset;begin
 if(p<4)message_address=(p*3+q)*MAX_MESSAGE+offset;
 else message_address=12*MAX_MESSAGE+((p-4)*3+q)*SUBVL_MAX_MESSAGE+offset;
end endfunction
reg [15:0] lengths[0:PORTS*3-1],ids[0:PORTS*3-1],next_id[0:3],offsets[0:PORTS-1];
reg [1:0] count[0:PORTS-1];reg [3:0] enabled;reg [1:0] wp[0:PORTS-1],rp[0:PORTS-1],sample_latest[0:PORTS-1];
wire [PORTS-1:0] sampling,port_enabled;genvar cp;
generate for(cp=0;cp<PORTS;cp=cp+1)begin:PORT_POLICY
 assign sampling[cp]=EXTENDED_PORTS?port_cfg[cp*64+1]:SAMPLING_MASK[cp%4];
 assign port_enabled[cp]=EXTENDED_PORTS?port_cfg[cp*64]:1'b1;
end endgenerate
wire [3:0] app_port=EXTENDED_PORTS?{app_wr_subvl,app_wr_vl_id}:{2'd0,app_wr_vl_id};
reg [31:0] bags[0:3],bag_left[0:3];reg [15:0] lmax[0:3];reg [7:0] sequence_number[0:3];
reg capture;reg [3:0] cap_vl;reg [1:0] cap_slot;reg [15:0] cap_len,cap_index;
reg [1:0] free_sample_slot;reg free_found;integer z;
wire [3:0] write_vl=capture?cap_vl:app_port;
wire [1:0] write_slot=capture?cap_slot:(sampling[app_port]?free_sample_slot:wp[app_port]);
wire [15:0] write_index=capture?cap_index:16'd0;
wire length_ok=port_enabled[app_port]&&network_cfg[app_wr_vl_id*168]&&network_cfg[app_wr_vl_id*168+1]&&app_wr_len>=1&&app_wr_len<=port_capacity(app_port)&&lmax[app_wr_vl_id]>=64&&lmax[app_wr_vl_id]<=1518&&
 (!sampling[app_port]||app_wr_len<=lmax[app_wr_vl_id]-47);
assign app_wr_ready=!rst&&(capture||(app_wr_sof&&enabled[app_wr_vl_id]&&count[app_port]<2&&length_ok));
assign app_wr_accept=app_wr_ready&&app_wr_en;
wire capture_bad=capture&&(app_wr_sof||app_port!=cap_vl||app_wr_len!=cap_len);
wire last_input=capture?cap_index==cap_len-1:app_wr_len==1;
wire enqueue=app_wr_accept&&!capture_bad&&app_wr_eof&&last_input;
localparam IDLE=0,BODY=1,WAIT_FCS=2,IFG=3;
reg [1:0] state,rr;reg [3:0] selected;reg [1:0] sub_rr[0:3];reg [1:0] slot;reg active_a,active_b;
reg [3:0] idle_gap;reg [15:0] message_length,fragment_offset,fragment_length,identifier,body_index,seq_index;
reg more_fragments;reg [7:0] seq_q;
reg [47:0] dm;reg [31:0] sip,dip;reg [15:0] sport,dport;
reg choose_valid;reg [1:0] choice,probe,sub_probe;reg [3:0] port_choice,port_probe;integer i,j,sj;
always @*begin
 choose_valid=0;choice=0;probe=0;sub_probe=0;port_choice=0;port_probe=0;
 for(j=1;j<=4;j=j+1)begin
  probe=rr+j;
  for(sj=1;sj<=(EXTENDED_PORTS?4:1);sj=sj+1)begin
   sub_probe=EXTENDED_PORTS?sub_rr[probe]+sj:0;port_probe={sub_probe,probe};
   if(!choose_valid&&enabled[probe]&&port_enabled[port_probe]&&network_cfg[probe*168]&&network_cfg[probe*168+1]&&count[port_probe]!=0&&bag_left[probe]==0)begin
    choose_valid=1;choice=probe;port_choice=port_probe;
   end
  end
 end
end
wire launch=state==IDLE&&tx_enable&&(network_a_enable||network_b_enable)&&choose_valid;
wire retire=state==IFG&&idle_gap==0;
wire dequeue=retire&&!more_fragments&&!sampling[selected];
wire [15:0] available=lmax[choice]-39;
wire [5:0] head=port_choice*3+(sampling[port_choice]?sample_latest[port_choice]:rp[port_choice]);
wire [15:0] remaining=lengths[head]+8-offsets[port_choice];

always @*begin
 free_sample_slot=0;free_found=0;
 for(z=0;z<3;z=z+1)if(!free_found&&!(count[app_port]!=0&&sample_latest[app_port]==z)&&!(state!=IDLE&&selected==app_port&&slot==z))begin free_sample_slot=z;free_found=1;end
end
wire next_more=remaining>available;
wire [15:0] next_fragment=next_more?{available[15:3],3'd0}:remaining;
wire [15:0] ip_length=fragment_length+20,udp_length=message_length+8;
wire [15:0] frag_field=(fragment_offset>>3)|(more_fragments?16'h2000:16'd0);
reg [31:0] sum_ip;reg [15:0] ip_checksum;
always @*begin
 sum_ip=32'h4500+{16'd0,ip_length}+{16'd0,identifier}+{16'd0,frag_field}+32'h0111+
 {16'd0,sip[31:16]}+{16'd0,sip[15:0]}+{16'd0,dip[31:16]}+{16'd0,dip[15:0]};
 sum_ip=(sum_ip&65535)+(sum_ip>>16);sum_ip=(sum_ip&65535)+(sum_ip>>16);ip_checksum=~sum_ip[15:0];
end
wire ar,br;wire body_ready=(!active_a||ar)&&(!active_b||br);
wire body_valid=state==BODY,body_eof=body_index==seq_index;
reg [7:0] memory_read;wire [15:0] prefetch_absolute=fragment_offset+body_index-33;
always @(posedge clk)begin
 if(app_wr_accept&&!capture_bad)memory[message_address(write_vl,write_slot,write_index)]<=app_wr_data;
 if(body_valid&&body_ready&&body_index>=33&&prefetch_absolute>=8&&prefetch_absolute<message_length+8)
  memory_read<=memory[message_address(selected,slot,prefetch_absolute-8)];
end
wire [15:0] absolute_byte=fragment_offset+body_index-34;
reg [7:0] td;
always @*begin
 td=0;
 case(body_index)
  0:td=dm[47:40];1:td=dm[39:32];2:td=dm[31:24];3:td=dm[23:16];4:td=dm[15:8];5:td=dm[7:0];
  6:td=SOURCE_MAC[47:40];7:td=SOURCE_MAC[39:32];8:td=SOURCE_MAC[31:24];9:td=SOURCE_MAC[23:16];10:td=SOURCE_MAC[15:8];11:td=SOURCE_MAC[7:0];
  12:td=8'h08;13:td=0;14:td=8'h45;15:td=0;16:td=ip_length[15:8];17:td=ip_length[7:0];
  18:td=identifier[15:8];19:td=identifier[7:0];20:td=frag_field[15:8];21:td=frag_field[7:0];22:td=1;23:td=17;
  24:td=ip_checksum[15:8];25:td=ip_checksum[7:0];26:td=sip[31:24];27:td=sip[23:16];28:td=sip[15:8];29:td=sip[7:0];
  30:td=dip[31:24];31:td=dip[23:16];32:td=dip[15:8];33:td=dip[7:0];
  default:if(body_index>=34&&body_index<34+fragment_length)begin
   if(absolute_byte<8)case(absolute_byte)
    0:td=sport[15:8];1:td=sport[7:0];2:td=dport[15:8];3:td=dport[7:0];4:td=udp_length[15:8];5:td=udp_length[7:0];default:td=0;
   endcase else td=memory_read;
  end
 endcase
 if(body_eof)td=seq_q;
end
assign busy=state!=IDLE;
gmii_tx_adapter_varlen a(.clk(clk),.rst(rst),.s_data(td),.s_valid(body_valid&&active_a),.s_eof(body_eof),.s_ready(ar),.gmii_txd(a_data),.gmii_tx_en(a_en),.gmii_tx_er(a_er),.frame_done(a_done),.underrun());
gmii_tx_adapter_varlen b(.clk(clk),.rst(rst),.s_data(td),.s_valid(body_valid&&active_b),.s_eof(body_eof),.s_ready(br),.gmii_txd(b_data),.gmii_tx_en(b_en),.gmii_tx_er(b_er),.frame_done(b_done),.underrun());
always @(posedge clk)begin
 if(rst)begin
  enabled<=0;capture<=0;cap_vl<=0;cap_slot<=0;cap_len<=0;cap_index<=0;app_len_error<=0;
  state<=IDLE;rr<=3;selected<=0;slot<=0;active_a<=0;active_b<=0;idle_gap<=0;message_length<=0;fragment_offset<=0;fragment_length<=0;identifier<=0;body_index<=0;seq_index<=0;more_fragments<=0;seq_q<=0;dm<=0;sip<=0;dip<=0;sport<=0;dport<=0;messages<=0;frames<=0;errors<=0;
  for(i=0;i<PORTS;i=i+1)begin wp[i]<=0;rp[i]<=0;sample_latest[i]<=0;count[i]<=0;offsets[i]<=0;end
  for(i=0;i<4;i=i+1)begin next_id[i]<=0;bags[i]<=0;bag_left[i]<=0;lmax[i]<=0;sequence_number[i]<=0;sub_rr[i]<=3;end
  for(i=0;i<PORTS*3;i=i+1)begin lengths[i]<=0;ids[i]<=0;end
 end else begin
  app_len_error<=0;
  if(cfg_we)begin enabled[cfg_vl_id]<=1;bags[cfg_vl_id]<=cfg_bag;lmax[cfg_vl_id]<=cfg_lmax;end
  for(i=0;i<4;i=i+1)if(bag_left[i]!=0)bag_left[i]<=bag_left[i]-1'b1;
  for(i=0;i<PORTS;i=i+1)begin
   if(sampling[i])begin if(enqueue&&write_vl==i)count[i]<=1;else if(launch&&port_choice==i)count[i]<=0;end
   else case({enqueue&&write_vl==i,dequeue&&selected==i})2'b10:count[i]<=count[i]+1'b1;2'b01:count[i]<=count[i]-1'b1;default:;endcase
  end
  if(app_wr_en&&!capture&&app_wr_sof&&!length_ok)begin app_len_error<=1;errors<=errors+1'b1;end
  if(app_wr_accept)begin
   if(capture_bad||app_wr_eof!=last_input)begin
    if(capture_bad||app_wr_eof||last_input)begin capture<=0;app_len_error<=1;errors<=errors+1'b1;end
    else if(!capture)begin capture<=1;cap_vl<=app_port;cap_slot<=write_slot;cap_len<=app_wr_len;cap_index<=1;end
    else cap_index<=cap_index+1'b1;
   end else if(last_input)capture<=0;
   else if(!capture)begin capture<=1;cap_vl<=app_port;cap_slot<=write_slot;cap_len<=app_wr_len;cap_index<=1;end
   else cap_index<=cap_index+1'b1;
  end
  if(enqueue)begin
   lengths[write_vl*3+write_slot]<=capture?cap_len:app_wr_len;ids[write_vl*3+write_slot]<=next_id[write_vl[1:0]];
   next_id[write_vl[1:0]]<=next_id[write_vl[1:0]]+1'b1;if(sampling[write_vl])sample_latest[write_vl]<=write_slot;else wp[write_vl]<=wp[write_vl]^2'd1;messages<=messages+1'b1;
  end
  case(state)
   IDLE:if(launch)begin
    selected<=port_choice;slot<=sampling[port_choice]?sample_latest[port_choice]:rp[port_choice];message_length<=lengths[head];identifier<=ids[head];
    fragment_offset<=offsets[port_choice];fragment_length<=next_fragment;more_fragments<=next_more;
    dm<=network_cfg[choice*168+8+:48];sip<=network_cfg[choice*168+56+:32];dip<=network_cfg[choice*168+88+:32];sport<=EXTENDED_PORTS&&port_cfg[port_choice*64+3]?port_cfg[port_choice*64+24+:16]:network_cfg[choice*168+120+:16];dport<=EXTENDED_PORTS&&port_cfg[port_choice*64+3]?port_cfg[port_choice*64+40+:16]:network_cfg[choice*168+136+:16];
    seq_q<=sequence_number[choice];sequence_number[choice]<=sequence_number[choice]==255?8'd1:sequence_number[choice]+1'b1;
    seq_index<=next_fragment<25?16'd59:16'd34+next_fragment;body_index<=0;active_a<=network_a_enable;active_b<=network_b_enable;
    rr<=choice;sub_rr[choice]<=port_choice[3:2];bag_left[choice]<=bags[choice]>0?bags[choice]-1'b1:0;frames<=frames+1'b1;state<=BODY;
   end
   BODY:if(body_ready)begin if(body_eof)state<=WAIT_FCS;else body_index<=body_index+1'b1;end
   WAIT_FCS:if((!active_a||a_done)&&(!active_b||b_done))begin idle_gap<=12;state<=IFG;end
   IFG:if(idle_gap!=0)idle_gap<=idle_gap-1'b1;else begin
    if(more_fragments)offsets[selected]<=fragment_offset+fragment_length;
    else begin offsets[selected]<=0;if(!sampling[selected])rp[selected]<=rp[selected]^2'd1;end
    state<=IDLE;
   end
  endcase
 end
end
endmodule