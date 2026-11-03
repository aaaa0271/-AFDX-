`timescale 1ns/1ps
module afdx_snmp_response_builder #(
 parameter integer MAX_VARBIND_BYTES=64,
 parameter integer MAX_MSG_BYTES=96
)(
 input wire clk,rst_n,req,input wire [31:0] request_id,
 input wire [MAX_VARBIND_BYTES*8-1:0] varbind_data,input wire [7:0] varbind_length,
 output reg done,valid,output reg [7:0] error_code,
 output reg [MAX_MSG_BYTES*8-1:0] msg_data,output reg [7:0] msg_length
);
wire rid_done,rid_error;wire [3:0] rid_tlv_length;wire [55:0] rid_tlv;
afdx_ber_primitive_codec u_request_id_codec(
 .encode_valid(1'b1),.encode_type(8'h02),.encode_value(request_id),
 .encode_done(rid_done),.encode_error(rid_error),.encode_len(rid_tlv_length),.encode_tlv(rid_tlv),
 .decode_valid(1'b0),.decode_type(8'd0),.decode_len(4'd0),.decode_tlv(56'd0),.decode_done(),.decode_error(),.decode_value());
wire [7:0] rid_length={4'd0,rid_tlv_length}-8'd2;
wire [15:0] total_length=16'd25+{8'd0,rid_length}+{8'd0,varbind_length};
wire [15:0] outer_length=total_length-16'd2;
wire [15:0] pdu_length=total_length-16'd15;
wire [31:0] aligned_id=rid_tlv[31:0] << ((8'd4-rid_length)*8);
reg [MAX_MSG_BYTES*8-1:0] header,tail,bindings;
reg [7:0] h,t,v;
integer i;
// Fixed-index byte writes and only two bounded vector shifts. In particular,
// do not use a procedural position counter incremented inside a conditional
// unrolled loop: old synthesis tools expand that into an exponential mux tree.
always @* begin
 header=0;tail=0;bindings=0;h=0;t=0;v=0;
 for(i=0;i<MAX_MSG_BYTES;i=i+1)begin
  h=0;t=0;v=0;
  case(i)
   0:h=48;1:h=outer_length[7:0];2:h=2;3,4:h=1;5:h=4;6:h=6;
   7:h="p";8:h="u";9:h="b";10:h="l";11:h="i";12:h="c";
   13:h=8'ha2;14:h=pdu_length[7:0];15:h=2;16:h=rid_length;
   default:if(i>=17&&i<21&&i<17+rid_length)h=aligned_id>>((20-i)*8);
  endcase
  case(i)
   0,3:t=2;1,4:t=1;6:t=48;7:t=varbind_length;default:;
  endcase
  if(i<MAX_VARBIND_BYTES && i<varbind_length)v=varbind_data[MAX_VARBIND_BYTES*8-1-i*8-:8];
  header[MAX_MSG_BYTES*8-1-i*8-:8]=h;
  tail[MAX_MSG_BYTES*8-1-i*8-:8]=t;
  bindings[MAX_MSG_BYTES*8-1-i*8-:8]=v;
 end
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin done<=0;valid<=0;error_code<=0;msg_data<=0;msg_length<=0;end
 else begin
  done<=0;
  if(req)begin
   done<=1;valid<=0;error_code<=0;msg_data<=0;msg_length<=0;
   if(varbind_length==0||varbind_length>MAX_VARBIND_BYTES)error_code<=1;
   else if(outer_length>=128||pdu_length>=128)error_code<=3;
   else if(total_length>MAX_MSG_BYTES)error_code<=2;
   else begin
    msg_data<=header | (tail>>((8'd17+rid_length)*8)) | (bindings>>((8'd25+rid_length)*8));
    msg_length<=total_length[7:0];valid<=1;
   end
  end
 end
end
endmodule
