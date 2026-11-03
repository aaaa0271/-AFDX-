`timescale 1ns/1ps
// SNMPv1/v2c read-only agent: configurable community, definite BER up to512 bytes,
// 16 VarBinds, complete lexicographic walk of the implemented MIB, exceptions,
// tooBig and notWritable responses. No private fixed-offset request shim.
module afdx_snmp_extended #(
 parameter integer MAX_BYTES=512,MAX_VARBINDS=16,MAX_OID_BYTES=64,MAX_ARCS=16,
 parameter integer VERSION_OVERRIDE_ENABLE=0
)(
 input wire clk,rst,request_valid,input wire [10:0] request_length,input wire [MAX_BYTES*8-1:0] request_bytes,
 input wire [5:0] community_length,input wire [255:0] community_bytes,
 input wire [799:0] mib_values,
 output wire busy,output reg done,response_valid,error,output reg [7:0] error_code,
 output reg [10:0] response_length,output reg [MAX_BYTES*8-1:0] response_bytes,
 output reg snapshot_event,output reg [31:0] snapshot_count,
 input wire [1:0] version_override
);
// Bound dynamic mux addresses to their actual storage domains. Length and
// TLV bounds remain full-width and are checked before these accesses are used.
function integer address_bits;input integer count;integer k;begin address_bits=1;for(k=0;k<16;k=k+1)if((1<<k)<count)address_bits=k+1;end endfunction
localparam BYTE_BITS=address_bits(MAX_BYTES),BIND_BITS=address_bits(MAX_VARBINDS),ARC_BITS=address_bits(MAX_ARCS),OID_BITS=address_bits(MAX_OID_BYTES);
localparam IDLE=0,TLV=1,COMM=2,RID=3,OID=4,SNAPSHOT=5,BUILD_START=6,BUILD_BYTE=7,LAYOUT=8,OUTPUT_BYTE=9,FINISH=10,COPY_SET=11,SEARCH_NEXT=12,STORE_BINDING=13,BULK_INT=14;
localparam F_MESSAGE=0,F_VERSION=1,F_COMMUNITY=2,F_PDU=3,F_RID=4,F_STATUS=5,F_INDEX=6,F_LIST=7,F_VB=8,F_OID=9,F_NULL=10;
reg [3:0] state,field;reg [MAX_BYTES*8-1:0] packet;reg [10:0] packet_len,pos,parent,msg_end,pdu_end,list_end,vb_end;
reg [5:0] comm_len;reg [255:0] comm;reg [7:0] op;reg [1:0] msg_version;
reg [31:0] bulk_nonrepeat,bulk_max,bulk_round,bulk_value;reg [2:0] bulk_len,bulk_index;
reg [31:0] rid,arc_acc;reg [7:0] rid_first;reg [2:0] rid_len,rid_index;
reg [10:0] content_start,content_length,cursor,original_list_start,original_list_length;
reg [10:0] copy_index;reg [4:0] search_object,search_arc;
reg [7:0] oid_len,oid_index,arc_count;reg arc_first,arc_cont;
reg [MAX_ARCS*32-1:0] arcs;
reg [MAX_OID_BYTES*8-1:0] current_oid,oids[0:MAX_VARBINDS-1];
reg [7:0] oid_lengths[0:MAX_VARBINDS-1],object_ids[0:MAX_VARBINDS-1],request_count,build_index;
reg overflow_count;reg [799:0] snapshot;
reg [MAX_BYTES*8-1:0] vb_bytes;
reg [10:0] vb_length,build_byte,build_length,total_length,outer_len,pdu_len;
reg [7:0] response_status,response_index,value_tag,answer_oid_len;
reg [2:0] value_len;reg [39:0] value_contents;reg [7:0] current_object;
reg [10:0] outer_start,pdu_start,rid_start,status_start,list_start,vb_start;
integer i;reg [7:0] chosen;reg prefix_ok;reg v1_has_error;reg [7:0] v1_error_index;
reg [7:0] answer_byte;reg [15:0] numeric_oid_length;reg [31:0] value32;reg [7:0] emit;
reg [10:0] tlv_len,tlv_start,tlv_end;reg bad_length;
wire [BYTE_BITS-1:0] p0=pos,p1=pos+1,p2=pos+2,p3=pos+3,cur=cursor,field_byte=tlv_start;
wire [BYTE_BITS-1:0] copy_src=original_list_start+copy_index,copy_dst=copy_index,vb_src=cursor-vb_start,vb_dst=vb_length+build_byte;
wire [BIND_BITS-1:0] request_slot=request_count,build_slot=build_index;
wire [ARC_BITS-1:0] arc_slot=arc_count,search_slot=search_arc;
wire [OID_BITS-1:0] oid_byte=build_byte-4;
wire [4:0] comm_read=cursor-content_start,comm_emit=cursor-outer_start-5,mib_slot=object_ids[build_slot]-1;
wire [1:0] rid_emit=rid_len-1-(cursor-rid_start-2);
wire [2:0] value_emit=value_len-1-(build_byte-6-answer_oid_len);
wire [7:0] tag=packet[{p0,3'd0}+:8];wire [7:0] len_first=packet[{p1,3'd0}+:8];

wire [7:0] current_byte=packet[{cur,3'd0}+:8];
assign busy=state!=IDLE;
function [7:0] oid_prefix;input [4:0] idx;begin case(idx)
 0:oid_prefix=8'h2b;1:oid_prefix=6;2:oid_prefix=1;3:oid_prefix=4;4:oid_prefix=1;5:oid_prefix=8'h81;6:oid_prefix=8'hfd;7:oid_prefix=8'h59;8,9:oid_prefix=1;default:oid_prefix=0;endcase end endfunction
function [31:0] canonical_arc;input [4:0] idx;input [7:0] obj;begin case(idx)
 0:canonical_arc=1;1:canonical_arc=3;2:canonical_arc=6;3:canonical_arc=1;4:canonical_arc=4;5:canonical_arc=1;6:canonical_arc=32473;7,8:canonical_arc=1;9:canonical_arc=obj;default:canonical_arc=0;endcase end endfunction
function [2:0] int_len;input [31:0] v;begin
 if(v[31])begin if(v>=32'hffffff80)int_len=1;else if(v>=32'hffff8000)int_len=2;else if(v>=32'hff800000)int_len=3;else int_len=4;end
 else begin if(v<=127)int_len=1;else if(v<=32767)int_len=2;else if(v<=8388607)int_len=3;else int_len=4;end
end endfunction
function [2:0] uint_len;input [31:0] v;begin if(v<=127)uint_len=1;else if(v<=32767)uint_len=2;else if(v<=8388607)uint_len=3;else if(v<=32'h7fffffff)uint_len=4;else uint_len=5;end endfunction
function [2:0] len_size;input [10:0] length;begin len_size=length<128?1:length<256?2:3;end endfunction
function [7:0] length_byte;input [10:0] length;input [10:0] n;begin
 if(length<128)length_byte=length[7:0];
 else if(length<256)length_byte=n==0?8'h81:length[7:0];
 else length_byte=n==0?8'h82:n==1?{5'd0,length[10:8]}:length[7:0];
end endfunction
function integer ber_hlen;input integer at;reg [7:0] l;begin
 l=packet[at*8 +: 8]; if(!l[7])ber_hlen=1;else if(l==8'h81)ber_hlen=2;else if(l==8'h82)ber_hlen=3;else ber_hlen=0;
end endfunction
function integer ber_clen;input integer at;reg [7:0] l;begin
 l=packet[at*8 +: 8]; if(!l[7])ber_clen=l;else if(l==8'h81)ber_clen=packet[(at+1)*8 +: 8];else if(l==8'h82)ber_clen={packet[(at+1)*8 +: 8],packet[(at+2)*8 +: 8]};else ber_clen=0;
end endfunction
wire [7:0] bulk_n=bulk_nonrepeat>=request_count?request_count:bulk_nonrepeat[7:0];
wire [10:0] candidate_vb=vb_length+build_length;
wire [10:0] candidate_pdu=2+rid_len+6+1+len_size(candidate_vb)+candidate_vb;
wire [10:0] candidate_outer=3+2+comm_len+1+len_size(candidate_pdu)+candidate_pdu;
wire [10:0] candidate_total=1+len_size(candidate_outer)+candidate_outer;
wire [31:0] bulk_next_value=bulk_index==0?{{24{current_byte[7]}},current_byte}:{bulk_value[23:0],current_byte};
always @*begin
 bad_length=0;tlv_start=pos+2;tlv_len=0;
 if(pos+2>parent)bad_length=1;
 else if(!len_first[7])tlv_len={3'd0,len_first};
 else if(len_first==8'h81&&pos+3<=parent)begin tlv_start=pos+3;tlv_len={3'd0,packet[{p2,3'd0}+:8]};end
 else if(len_first==8'h82&&pos+4<=parent)begin
  tlv_start=pos+4;
  if(packet[{p2,3'd0}+:8]>1)bad_length=1;
  tlv_len={2'd0,packet[{p2,3'd0}],packet[{p3,3'd0}+:8]};
 end else bad_length=1;
 tlv_end=tlv_start+tlv_len;
 if(tlv_end>parent||tlv_end>packet_len)bad_length=1;
 // Lexicographic comparison on decoded numeric arcs, NOT encoded byte order.
 chosen=0;prefix_ok=1;
 for(i=0;i<9;i=i+1)if(arcs[i*32+:32]!=canonical_arc(i,0))prefix_ok=0;
 if(op==8'ha0||op==8'ha3)begin
  if(arc_count==10&&prefix_ok&&arcs[9*32+:32]>=1&&arcs[9*32+:32]<=25)chosen=arcs[9*32+:8];
 end
 // v1 reports noSuchName for unavailable GET/GETNEXT/SET objects (RFC1157 4.1.5).
 v1_has_error=0;v1_error_index=0;
 for(i=0;i<MAX_VARBINDS;i=i+1)begin
  if(i<request_count&&object_ids[i]==0&&!v1_has_error)begin
   v1_has_error=1;v1_error_index=i+1;
  end
 end
end
task reject;input [7:0] code;begin error<=1;error_code<=code;response_valid<=0;response_length<=0;response_bytes<=0;state<=FINISH;end endtask
task next_field;input [3:0] f;input [10:0] p,limit;begin field<=f;pos<=p;parent<=limit;state<=TLV;end endtask
always @*begin
 emit=0;
 if(cursor==0)emit=48;
 else if(cursor<outer_start)emit=length_byte(outer_len,cursor-1);
 else if(cursor==outer_start)emit=2;else if(cursor==outer_start+1)emit=1;
 else if(cursor==outer_start+2)emit=msg_version;
 else if(cursor==outer_start+3)emit=4;else if(cursor==outer_start+4)emit=comm_len;
 else if(cursor<pdu_start)emit=comm[{comm_emit,3'd0}+:8];
 else if(cursor==pdu_start)emit=8'ha2;
 else if(cursor<rid_start)emit=length_byte(pdu_len,cursor-pdu_start-1);
 else if(cursor==rid_start)emit=2;else if(cursor==rid_start+1)emit=rid_len;
 else if(cursor<status_start)emit=rid>>{rid_emit,3'd0};
 else if(cursor==status_start||cursor==status_start+3)emit=2;
 else if(cursor==status_start+1||cursor==status_start+4)emit=1;
 else if(cursor==status_start+2)emit=response_status;else if(cursor==status_start+5)emit=response_index;
 else if(cursor==list_start)emit=48;
 else if(cursor<vb_start)emit=length_byte(vb_length,cursor-list_start-1);
 else emit=vb_bytes[{vb_src,3'd0}+:8];
 answer_byte=0;
 if(build_byte==0)answer_byte=48;
 else if(build_byte==1)answer_byte=answer_oid_len+4+value_len;
 else if(build_byte==2)answer_byte=6;
 else if(build_byte==3)answer_byte=answer_oid_len;
 else if(build_byte<4+answer_oid_len)begin
  if(current_object!=0)answer_byte=build_byte==14?current_object:oid_prefix(build_byte-4);
  else answer_byte=oids[build_slot][{oid_byte,3'd0}+:8];
 end else if(build_byte==4+answer_oid_len)answer_byte=value_tag;
 else if(build_byte==5+answer_oid_len)answer_byte=value_len;
 else answer_byte=value_contents>>{value_emit,3'd0};
end
always @(posedge clk)begin
 if(rst)begin
  state<=IDLE;field<=0;bulk_nonrepeat<=0;bulk_max<=0;bulk_round<=0;bulk_value<=0;bulk_len<=0;bulk_index<=0;copy_index<=0;search_object<=1;search_arc<=0;packet<=0;packet_len<=0;pos<=0;parent<=0;msg_end<=0;pdu_end<=0;list_end<=0;vb_end<=0;comm_len<=0;comm<=0;op<=0;msg_version<=1;
  rid<=0;rid_first<=0;rid_len<=0;rid_index<=0;cursor<=0;content_start<=0;content_length<=0;original_list_start<=0;original_list_length<=0;oid_len<=0;oid_index<=0;arc_count<=0;arc_acc<=0;arc_first<=1;arc_cont<=0;arcs<=0;current_oid<=0;request_count<=0;build_index<=0;overflow_count<=0;
  snapshot<=0;snapshot_event<=0;snapshot_count<=0;vb_bytes<=0;vb_length<=0;build_byte<=0;build_length<=0;total_length<=0;outer_len<=0;pdu_len<=0;outer_start<=0;pdu_start<=0;rid_start<=0;status_start<=0;list_start<=0;vb_start<=0;
  response_status<=0;response_index<=0;value_tag<=0;value_len<=0;value_contents<=0;current_object<=0;answer_oid_len<=0;
  done<=0;response_valid<=0;error<=0;error_code<=0;response_length<=0;response_bytes<=0;
 end else begin
  done<=0;snapshot_event<=0;
  case(state)
  IDLE:if(request_valid)begin
    bulk_nonrepeat<=0;bulk_max<=0;bulk_round<=0;
    packet<=request_bytes;packet_len<=request_length;comm_len<=community_length;comm<=community_bytes;
    request_count<=0;overflow_count<=0;error<=0;error_code<=0;response_valid<=0;response_bytes<=0;response_length<=0;response_status<=0;response_index<=0;vb_length<=0;vb_bytes<=0;
    if(request_length<18||request_length>MAX_BYTES||community_length>32||community_length==0)reject(1);
    else next_field(F_MESSAGE,0,request_length);
   end
   TLV:if(bad_length)reject(1);else case(field)
    F_MESSAGE:if(tag!=48||tlv_end!=packet_len)reject(1);else begin msg_end<=tlv_end;next_field(F_VERSION,tlv_start,tlv_end);end
    F_VERSION:if(tag!=2||tlv_len!=1||packet[{field_byte,3'd0}+:8]>1||
                       (VERSION_OVERRIDE_ENABLE!=0&&version_override>1))reject(5);
              else begin
               if(VERSION_OVERRIDE_ENABLE!=0)msg_version<=version_override;
               else msg_version<=packet[{field_byte,3'd0}+:8];
               next_field(F_COMMUNITY,tlv_end,msg_end);
              end
    F_COMMUNITY:if(tag!=4||tlv_len!=comm_len)reject(2);else begin cursor<=tlv_start;content_start<=tlv_start;content_length<=tlv_len;state<=COMM;end
    F_PDU:if((tag!=8'ha0&&tag!=8'ha1&&tag!=8'ha3&&tag!=8'ha5)||
             (msg_version==0&&tag==8'ha5)||tlv_end!=msg_end)reject(3);else begin op<=tag;pdu_end<=tlv_end;next_field(F_RID,tlv_start,tlv_end);end
    F_RID:if(tag!=2||tlv_len==0||tlv_len>4)reject(1);else begin rid_len<=tlv_len;rid_index<=0;cursor<=tlv_start;content_start<=tlv_start;content_length<=tlv_len;state<=RID;end
    F_STATUS,F_INDEX:if(op==8'ha5)begin
     if(tag!=2||tlv_len==0||tlv_len>4)reject(1);
     else begin bulk_len<=tlv_len;bulk_index<=0;bulk_value<=0;cursor<=tlv_start;content_start<=tlv_start;content_length<=tlv_len;state<=BULK_INT;end
    end else if(tag!=2||tlv_len!=1||packet[{field_byte,3'd0}+:8]!=0)reject(1);else if(field==F_STATUS)next_field(F_INDEX,tlv_end,pdu_end);else next_field(F_LIST,tlv_end,pdu_end);
    F_LIST:if(tag!=48||tlv_end!=pdu_end)reject(1);else begin list_end<=tlv_end;original_list_start<=tlv_start;original_list_length<=tlv_len;if(tlv_len==0)state<=SNAPSHOT;else next_field(F_VB,tlv_start,tlv_end);end
    F_VB:if(tag!=48)reject(1);else begin vb_end<=tlv_end;next_field(F_OID,tlv_start,tlv_end);end
    F_OID:if(tag!=6||tlv_len==0||tlv_len>MAX_OID_BYTES)reject(7);else begin oid_len<=tlv_len;oid_index<=0;cursor<=tlv_start;content_start<=tlv_start;content_length<=tlv_len;arcs<=0;arc_acc<=0;arc_count<=0;arc_first<=1;arc_cont<=0;current_oid<=0;state<=OID;end
    F_NULL:if((op!=8'ha3&&(tag!=5||tlv_len!=0))||tlv_end!=vb_end)reject(1);else begin
     if(request_count<MAX_VARBINDS)begin
      oids[request_slot]<=current_oid;oid_lengths[request_slot]<=oid_len;
      if(op==8'ha1||op==8'ha5)begin search_object<=1;search_arc<=0;state<=SEARCH_NEXT;end
      else begin object_ids[request_slot]<=chosen;state<=STORE_BINDING;end
     end else begin overflow_count<=1;state<=STORE_BINDING;end
    end
   endcase
   // One numeric-arc comparison per clock. Preserve lexicographic ordering
   // without unrolling 25 x MAX_ARCS wide comparators in the eLinx front end.
   SEARCH_NEXT:begin
    if(search_arc>=10 || (search_arc<arc_count&&canonical_arc(search_arc,{3'd0,search_object})<arcs[{search_slot,5'd0}+:32]))begin
     if(search_object==25)begin object_ids[request_slot]<=0;state<=STORE_BINDING;end
     else begin search_object<=search_object+1'b1;search_arc<=0;end
    end else if(search_arc>=arc_count || canonical_arc(search_arc,{3'd0,search_object})>arcs[{search_slot,5'd0}+:32])begin
     object_ids[request_slot]<={3'd0,search_object};state<=STORE_BINDING;
    end else search_arc<=search_arc+1'b1;
   end
   STORE_BINDING:begin
    request_count<=request_count+1'b1;
    if(vb_end==list_end)state<=SNAPSHOT;else next_field(F_VB,vb_end,list_end);
   end
   BULK_INT:begin
    bulk_value<=bulk_next_value;
    if(bulk_index==bulk_len-1)begin
     if(field==F_STATUS)begin bulk_nonrepeat<=bulk_next_value[31]?0:bulk_next_value;next_field(F_INDEX,cursor+1,pdu_end);end
     else begin bulk_max<=bulk_next_value[31]?0:bulk_next_value;next_field(F_LIST,cursor+1,pdu_end);end
    end else begin bulk_index<=bulk_index+1'b1;cursor<=cursor+1'b1;end
   end
   COMM:begin
    if(current_byte!=comm[{comm_read,3'd0}+:8])reject(2);
    else if(cursor==content_start+content_length-1)next_field(F_PDU,cursor+1,msg_end);else cursor<=cursor+1'b1;
   end
   RID:begin
    if(rid_index==0)begin rid<={{24{current_byte[7]}},current_byte};rid_first<=current_byte;end
    else rid<={rid[23:0],current_byte};
    if(rid_index==1&&((rid_first==0&&!current_byte[7])||(rid_first==255&&current_byte[7])))reject(1);
    else if(rid_index==rid_len-1)next_field(F_STATUS,cursor+1,pdu_end);
    else begin rid_index<=rid_index+1'b1;cursor<=cursor+1'b1;end
   end
   OID:begin
    current_oid[oid_index*8+:8]<=current_byte;
    if((!arc_cont&&current_byte==8'h80)||arc_acc>32'h01ffffff||arc_count>=MAX_ARCS)reject(7);
    else begin
     arc_acc<=(arc_acc<<7)|current_byte[6:0];arc_cont<=current_byte[7];
     if(!current_byte[7])begin
      if(arc_first)begin
       if(((arc_acc<<7)|current_byte[6:0])<40)begin arcs[31:0]<=0;arcs[63:32]<=(arc_acc<<7)|current_byte[6:0];end
       else if(((arc_acc<<7)|current_byte[6:0])<80)begin arcs[31:0]<=1;arcs[63:32]<=((arc_acc<<7)|current_byte[6:0])-40;end
       else begin arcs[31:0]<=2;arcs[63:32]<=((arc_acc<<7)|current_byte[6:0])-80;end
       arc_count<=2;arc_first<=0;
      end else begin arcs[{arc_slot,5'd0}+:32]<=(arc_acc<<7)|current_byte[6:0];arc_count<=arc_count+1'b1;end
      arc_acc<=0;
     end
     if(oid_index==oid_len-1)begin if(current_byte[7])reject(7);else next_field(F_NULL,cursor+1,vb_end);end
     else begin oid_index<=oid_index+1'b1;cursor<=cursor+1'b1;end
    end
   end
   SNAPSHOT:begin
    snapshot<=mib_values;snapshot_count<=snapshot_count+1'b1;snapshot_event<=1;build_index<=0;rid_len<=int_len(rid);
    if(overflow_count)begin
     response_status<=1;response_index<=0;copy_index<=0;
     vb_length<=msg_version==0?original_list_length:0;
     state<=msg_version==0&&original_list_length!=0?COPY_SET:LAYOUT;
    end
    else if(msg_version==0&&v1_has_error)begin
     // SNMPv1 has no exception values: report the first failing VarBind.
     response_status<=2;response_index<=v1_error_index;vb_length<=original_list_length;
     copy_index<=0;state<=original_list_length==0?LAYOUT:COPY_SET;
    end
    else if(op==8'ha3)begin
     response_status<=request_count==0?0:msg_version==0?2:17;response_index<=request_count!=0?1:0;vb_length<=original_list_length;
     // Reuse one byte mux instead of MAX_BYTES parallel packet selectors.
     copy_index<=0;state<=original_list_length==0?LAYOUT:COPY_SET;
    end
    else if(op==8'ha5&&(request_count==0||(bulk_n==0&&bulk_max==0)))state<=LAYOUT;
    else state<=BUILD_START;
   end
   COPY_SET:begin
    vb_bytes[{copy_dst,3'd0}+:8]<=packet[{copy_src,3'd0}+:8];
    if(copy_index+1==original_list_length)state<=LAYOUT;else copy_index<=copy_index+1'b1;
   end
   BUILD_START:if(build_index>=request_count)state<=LAYOUT;else begin
    current_object<=object_ids[build_slot];build_byte<=0;
    if(object_ids[build_slot]==0)begin
     answer_oid_len<=oid_lengths[build_slot];value_tag<=(op==8'ha1||op==8'ha5)?8'h82:8'h80;value_len<=0;value_contents<=0;build_length<=6+oid_lengths[build_slot];
    end else begin
     answer_oid_len<=11;
     value32=snapshot[{mib_slot,5'd0}+:32];
     if(object_ids[build_slot]==2)value32=snapshot_count;
     if(object_ids[build_slot]==1||object_ids[build_slot]==4||object_ids[build_slot]==5)begin value_tag<=2;value_len<=int_len(value32);build_length<=17+int_len(value32);end
     else begin value_tag<=object_ids[build_slot]==3?8'h43:8'h41;value_len<=uint_len(value32);build_length<=17+uint_len(value32);end
     value_contents<={8'd0,value32};
    end
    state<=BUILD_BYTE;
   end
   BUILD_BYTE:begin
    if(op==8'ha5&&candidate_total>MAX_BYTES)state<=LAYOUT;
    else if(vb_length+build_length>MAX_BYTES)begin response_status<=1;response_index<=0;vb_length<=0;vb_bytes<=0;state<=LAYOUT;end
    else begin
     vb_bytes[{vb_dst,3'd0}+:8]<=answer_byte;
     if(build_byte==build_length-1)begin
      vb_length<=vb_length+build_length;
      if(op==8'ha5)begin
       // Next repetition starts after this returned OID. Exceptions retain
       // the last returned (or original) OID for the corresponding column.
       if(current_object!=0)begin
        object_ids[build_slot]<=current_object==25?0:current_object+1'b1;oid_lengths[build_slot]<=11;
        oids[build_slot]<={current_object,80'h010159fd81010401062b};
       end
       if(build_index+1>=request_count)begin
        if(bulk_n==request_count||bulk_round+1>=bulk_max)state<=LAYOUT;
        else begin bulk_round<=bulk_round+1'b1;build_index<=bulk_n;state<=BUILD_START;end
       end else if(build_index+1==bulk_n&&bulk_max==0)state<=LAYOUT;
       else begin build_index<=build_index+1'b1;state<=BUILD_START;end
      end else begin build_index<=build_index+1'b1;state<=BUILD_START;end
     end
     else build_byte<=build_byte+1'b1;
    end
   end
   LAYOUT:begin
    // Blocking temporary arithmetic is used only for bounded small lengths.
    pdu_len=2+rid_len+6+1+len_size(vb_length)+vb_length;
    outer_len=3+2+comm_len+1+len_size(pdu_len)+pdu_len;
    total_length=1+len_size(outer_len)+outer_len;
    if(total_length>MAX_BYTES)begin response_status<=1;response_index<=0;vb_length<=0;vb_bytes<=0;end
    else begin
     outer_start<=1+len_size(outer_len);
     pdu_start<=1+len_size(outer_len)+3+2+comm_len;
     rid_start<=1+len_size(outer_len)+3+2+comm_len+1+len_size(pdu_len);
     status_start<=1+len_size(outer_len)+3+2+comm_len+1+len_size(pdu_len)+2+rid_len;
     list_start<=1+len_size(outer_len)+3+2+comm_len+1+len_size(pdu_len)+2+rid_len+6;
     vb_start<=total_length-vb_length;cursor<=0;response_length<=total_length;state<=OUTPUT_BYTE;
    end
   end
   OUTPUT_BYTE:begin
    response_bytes[{cur,3'd0}+:8]<=emit;
    if(cursor==total_length-1)begin response_valid<=1;state<=FINISH;end else cursor<=cursor+1'b1;
   end
   FINISH:begin done<=1;state<=IDLE;end
  endcase
 end
end
endmodule
