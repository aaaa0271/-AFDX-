`timescale 1ns/1ps
// LEGACY/standalone SNMP policy module: not instantiated by
// AFDX_competition_top or the competition AFDX_top; retained only for legacy
// ModelSim regression coverage. Do not use for new work.
// Bounded, byte-serial SNMPv2c/public BER decoder. One byte is examined per
// clock, avoiding cascaded data-dependent wide-vector multiplexers in synthesis.
module afdx_snmp_profile_decoder #(
 parameter integer MAX_MSG_BYTES=128,
 parameter integer MAX_VARBINDS=2
)(
 input wire clk,rst_n,req,
 input wire [7:0] msg_length,input wire [MAX_MSG_BYTES*8-1:0] msg_bytes,
 output reg done,valid,output reg [7:0] error_code,
 output reg request_op,output reg [31:0] request_id,
 output reg [7:0] object_count,output reg [MAX_VARBINDS*8-1:0] object_ids
);
localparam IDLE=0,HEADER=1,RID=2,STATUS=3,LIST_TAG=4,LIST_LEN=5,
 VB_TAG=6,VB_LEN=7,OID_TAG=8,OID_LEN=9,OID_DATA=10,NULL_TAG=11,NULL_LEN=12;
reg [3:0] state;
reg [MAX_MSG_BYTES*8-1:0] bytes_q;
reg [7:0] length_q,pos,rid_length,field_index,vb_end,vb_size,oid_length,oid_index,leaf;
reg [7:0] rid_first,pdu_error;
reg community_bad;
wire [7:0] data=bytes_q[pos*8+:8];
function [7:0] prefix;
 input [3:0] index;
 begin case(index)
  0:prefix=8'h2b;1:prefix=6;2:prefix=1;3:prefix=4;4:prefix=1;
  5:prefix=8'h81;6:prefix=8'hfd;7:prefix=8'h59;8,9:prefix=1;default:prefix=0;
 endcase end
endfunction
reg malformed;
always @* begin
 malformed=0;
 case(state)
  HEADER:case(pos)
   0:malformed=data!=48;
   1:malformed=data!=length_q-2;
   2,15:malformed=data!=2;
   3,4:malformed=data!=1;
   5:malformed=data!=4;
   6:malformed=data!=6;
   14:malformed=data!=length_q-15;
   16:malformed=data<1||data>4;
   default:;
  endcase
  RID:malformed=field_index==1 && ((rid_first==0&&!data[7])||(rid_first==255&&data[7]));
  STATUS:case(field_index)
   0,3:malformed=data!=2;
   1,4:malformed=data!=1;
   default:malformed=data!=0;
  endcase
  LIST_TAG,VB_TAG:malformed=data!=48 || (state==VB_TAG && object_count>=MAX_VARBINDS);
  LIST_LEN:malformed=data!=length_q-pos-1 || data[7];
  VB_LEN:malformed=data[7] || data<7 || ({1'b0,pos}+9'd1+{1'b0,data}>{1'b0,length_q});
  OID_TAG:malformed=data!=6;
  OID_LEN:malformed=!((data>=1&&data<=5)||(data>=8&&data<=11)) || vb_size!=data+4;
  OID_DATA:begin
   if(oid_index<10)malformed=data!=prefix(oid_index[3:0]);
   else malformed=data[7] || (data==0&&!request_op);
   if(oid_index==oid_length-1 && oid_length<11 && !request_op)malformed=1;
  end
  NULL_TAG:malformed=data!=5;
  NULL_LEN:malformed=data!=0 || pos+1!=vb_end;
  default:;
 endcase
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  state<=IDLE;bytes_q<=0;length_q<=0;pos<=0;rid_length<=0;field_index<=0;rid_first<=0;
  vb_end<=0;vb_size<=0;oid_length<=0;oid_index<=0;leaf<=0;pdu_error<=0;community_bad<=0;
  done<=0;valid<=0;error_code<=0;request_op<=0;request_id<=0;object_count<=0;object_ids<=0;
 end else begin
  done<=0;
  if(state==IDLE)begin
   if(req)begin
    bytes_q<=msg_bytes;length_q<=msg_length;pos<=0;valid<=0;error_code<=0;
    request_op<=0;request_id<=0;object_count<=0;object_ids<=0;community_bad<=0;pdu_error<=0;
    if(msg_length<32||msg_length>MAX_MSG_BYTES||msg_length>=128)begin done<=1;error_code<=1;end
    else state<=HEADER;
   end
  end else if(pos>=length_q || malformed)begin
   done<=1;valid<=0;error_code<=1;state<=IDLE;
  end else begin
   pos<=pos+1'b1;
   case(state)
    HEADER:begin
     case(pos)
      7:if(data!="p")community_bad<=1;
      8:if(data!="u")community_bad<=1;
      9:if(data!="b")community_bad<=1;
      10:if(data!="l")community_bad<=1;
      11:if(data!="i")community_bad<=1;
      12:if(data!="c")community_bad<=1;
      13:begin request_op<=data==8'ha1;
       if(data!=8'ha0 && data!=8'ha1)pdu_error<=data==8'ha3 ? 8'd4:8'd3;
      end
      16:begin rid_length<=data;field_index<=0;state<=RID;end
      default:;
     endcase
    end
    RID:begin
     if(field_index==0)begin request_id<={{24{data[7]}},data};rid_first<=data;end
     else request_id<={request_id[23:0],data};
     if(field_index==rid_length-1)begin state<=STATUS;field_index<=0;end
     else field_index<=field_index+1'b1;
    end
    STATUS:if(field_index==5)state<=LIST_TAG;else field_index<=field_index+1'b1;
    LIST_TAG:state<=LIST_LEN;
    LIST_LEN:state<=VB_TAG;
    VB_TAG:state<=VB_LEN;
    VB_LEN:begin vb_size<=data;vb_end<=pos+8'd1+data;state<=OID_TAG;end
    OID_TAG:state<=OID_LEN;
    OID_LEN:begin oid_length<=data;oid_index<=0;leaf<=0;state<=OID_DATA;end
    OID_DATA:begin
     if(oid_index==10)leaf<=data;
     if(oid_index==oid_length-1)state<=NULL_TAG;else oid_index<=oid_index+1'b1;
    end
    NULL_TAG:state<=NULL_LEN;
    NULL_LEN:begin
     object_ids[object_count*8+:8]<=leaf;object_count<=object_count+1'b1;
     if(vb_end==length_q)begin
      done<=1;valid<=!community_bad && pdu_error==0;
      error_code<=community_bad?8'd2:pdu_error;state<=IDLE;
     end else state<=VB_TAG;
    end
    default:begin done<=1;valid<=0;error_code<=1;state<=IDLE;end
   endcase
  end
 end
end
endmodule
