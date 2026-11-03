`timescale 1ns/1ps
// Small RFC1350 server for the two ARINC615A control files TARGET.LUI/LUR.
// These bounded files fit in one block. Target data files use the full client.
module afdx_615a_control_tftp #(parameter integer TIMEOUT_CYCLES=100000000)(
 input wire clk,rst,input wire [31:0] loader_ip,
 input wire rx_valid,input wire [31:0] rx_ip,input wire [15:0] rx_sport,rx_dport,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes,
 output reg tx_valid,input wire tx_ready,output reg [31:0] tx_ip,output reg [15:0] tx_sport,tx_dport,
 output reg [10:0] tx_length,output reg [4127:0] tx_bytes,
 output reg initialize,input wire lui_valid,output wire lui_ready,input wire [79:0] lui_bytes,
 output reg lur_valid,output reg [15:0] lur_length,output reg [1023:0] lur_bytes,
 input wire lur_accept,lur_reject,input wire loading,
 output wire idle,output reg remote_abort,output reg [15:0] abort_status
);
localparam IDLE=0,LUI_WAIT=1,LUI_ACK=2,LUR_DATA=3,LUR_CHECK=4,DALLY=5;
reg [2:0] state;reg [31:0] age;reg [2:0] retry_count;reg [4127:0] last;reg [10:0] last_length;
reg [15:0] tid_restore;reg restore_tid;
reg [63:0] no_progress;
wire [15:0] opcode={rx_bytes[7:0],rx_bytes[15:8]},block={rx_bytes[23:16],rx_bytes[31:24]};

wire common_request=rx_length==19 && rx_bytes[12*8+:8]==0 && rx_bytes[13*8+:48]==48'h00746574636f;
wire name_lui=rx_bytes[2*8+:80]==80'h49554c2e544547524154;
wire name_lur=rx_bytes[2*8+:80]==80'h52554c2e544547524154;
assign idle=state==IDLE&&!tx_valid&&!initialize&&!lur_valid;
wire wait_message,abort_message;wire [15:0] wait_seconds,decoded_abort;
wire peer_packet=rx_valid&&rx_ip==loader_ip&&rx_sport!=0&&rx_dport==41000&&rx_sport==tx_dport&&!tx_valid;
wire progress=(state==LUI_WAIT&&lui_valid&&!tx_valid)||
 (state==LUR_CHECK&&(lur_accept||lur_reject)&&!tx_valid)||
 (peer_packet&&((state==LUI_ACK&&opcode==4&&block==1&&rx_length==4)||
 (state==LUR_DATA&&opcode==3&&block==1&&rx_length>=4&&rx_length<=132)||
 (opcode==5&&rx_length>=5&&rx_bytes[(rx_length-1)*8+:8]==0)));
wire exhausted=state!=IDLE&&no_progress>=((state==LUI_ACK||state==LUR_DATA)?64'd4*(TIMEOUT_CYCLES+4):64'd1*TIMEOUT_CYCLES)-1;
wire deadline=state!=IDLE&&!progress&&(exhausted||((!tx_valid||restore_tid)&&age>=TIMEOUT_CYCLES-1));
afdx_615a_tftp_error error_decode(.length(rx_length),.bytes(rx_bytes),.wait_message(wait_message),
 .abort_message(abort_message),.wait_seconds(wait_seconds),.abort_status(decoded_abort));
assign lui_ready=state==LUI_WAIT&&!tx_valid;
task emit_ack;input [15:0] n;begin
 tx_bytes<=0;tx_bytes[15:8]<=4;tx_bytes[23:16]<=n[15:8];tx_bytes[31:24]<=n[7:0];tx_length<=4;tx_valid<=1;
 last<=0;last[15:8]<=4;last[23:16]<=n[15:8];last[31:24]<=n[7:0];last_length<=4;
end endtask
task emit_error;begin tx_bytes<=0;tx_bytes[15:8]<=5;tx_bytes[31:24]<=4;tx_length<=5;tx_valid<=1;state<=IDLE;end endtask
always @(posedge clk)begin
 if(rst)begin remote_abort<=0;abort_status<=0;state<=IDLE;age<=0;no_progress<=0;retry_count<=0;last<=0;last_length<=0;tx_valid<=0;tx_ip<=0;tx_sport<=41000;tx_dport<=0;tx_length<=0;tx_bytes<=0;initialize<=0;lur_valid<=0;lur_length<=0;lur_bytes<=0;tid_restore<=0;restore_tid<=0;end
 else begin
  initialize<=0;lur_valid<=0;remote_abort<=0;
  if(progress)begin no_progress<=0;age<=0;retry_count<=0;end
  else if(state!=IDLE)no_progress<=no_progress+1'b1;
  if(tx_valid&&tx_ready)begin tx_valid<=0;if(!restore_tid)age<=0;if(restore_tid)begin tx_dport<=tid_restore;restore_tid<=0;end end
  if(state!=IDLE&&(!tx_valid||restore_tid||exhausted)&&!progress)begin
   if(age<TIMEOUT_CYCLES-1)age<=age+1'b1;
   if(deadline)begin
    // A stalled application response must not hold the TFTP control port forever.
    if(exhausted||state==DALLY||state==LUI_WAIT||state==LUR_CHECK||retry_count==3)begin state<=IDLE;tx_valid<=0;restore_tid<=0;if(restore_tid)tx_dport<=tid_restore;end
    else if(!tx_valid&&(state==LUI_ACK||state==LUR_DATA))begin tx_valid<=1;tx_bytes<=last;tx_length<=last_length;age<=0;retry_count<=retry_count+1'b1;end
   end
  end
  if(!deadline&&state==LUI_WAIT&&lui_valid&&!tx_valid)begin
   tx_bytes<=0;tx_bytes[15:8]<=3;tx_bytes[31:24]<=1;tx_bytes[4*8+:80]<=lui_bytes;tx_length<=14;tx_valid<=1;
   last<=0;last[15:8]<=3;last[31:24]<=1;last[4*8+:80]<=lui_bytes;last_length<=14;state<=LUI_ACK;age<=0;
  end
  if(!deadline&&state==LUR_CHECK&&!tx_valid)begin
   if(lur_accept)begin emit_ack(1);age<=0;retry_count<=0;state<=DALLY;end
   else if(lur_reject)emit_error;
  end
  if(!deadline&&rx_valid&&rx_ip==loader_ip&&rx_sport!=0&&!tx_valid)begin
   if(rx_dport==69&&(state==IDLE||state==DALLY))begin
    tx_ip<=rx_ip;tx_dport<=rx_sport;age<=0;no_progress<=0;retry_count<=0;
    if(!common_request||loading)emit_error;
    else if(opcode==1&&name_lui)begin initialize<=1;state<=LUI_WAIT;end
    else if(opcode==2&&name_lur)begin emit_ack(0);state<=LUR_DATA;end
    else emit_error;
   end else if(rx_dport==41000&&rx_sport==tx_dport)begin
    if(opcode==5&&rx_length>=5&&rx_bytes[(rx_length-1)*8+:8]==0)begin
     state<=IDLE;remote_abort<=abort_message;abort_status<=decoded_abort;
    end else if(state==LUI_ACK&&opcode==4&&block==1&&rx_length==4)state<=IDLE;
    else if((state==LUR_DATA||state==DALLY)&&opcode==3&&block==1&&rx_length>=4&&rx_length<=132)begin
     if(state==DALLY)emit_ack(1);
     else begin lur_bytes<=rx_bytes[1055:32];lur_length<=rx_length-4;lur_valid<=1;state<=LUR_CHECK;end
    end
   end else if(rx_dport==41000)begin
    // RFC1350 ERROR 5: packet to the control port from a TID other than the
    // connected peer's. Answer the stray source directly without disturbing
    // the live session (its TID is restored after the error frame leaves).
    tid_restore<=tx_dport;restore_tid<=1;
    tx_ip<=rx_ip;tx_dport<=rx_sport;
    tx_bytes<=0;tx_bytes[15:8]<=5;tx_bytes[31:24]<=5;tx_length<=5;tx_valid<=1;
   end
  end
 end
end
endmodule
