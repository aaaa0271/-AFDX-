`timescale 1ns/1ps
// SNMPv1/v2c dispatcher and RFC3412/3414 plaintext USM responder.
// Octet zero occupies bits 7:0. noAuthNoPriv is the implemented security
// level; authenticated/encrypted messages never reach the MIB in this core.
module afdx_snmp_wire #(
 parameter integer MAX_BYTES=512,CLK_HZ=12500000,
 parameter integer ENGINE_LENGTH=9,USER_LENGTH=4,
 parameter [255:0] ENGINE_ID=256'h5844464105d97e0080,
 parameter [255:0] USER_NAME=256'h78646661,
 parameter [30:0] ENGINE_BOOTS=1
)(
 input wire clk,rst,request_valid,input wire [10:0] request_length,
 input wire [MAX_BYTES*8-1:0] request_bytes,
 input wire [5:0] community_length,input wire [255:0] community_bytes,
 input wire [799:0] mib_values,
 output wire busy,output reg done,response_valid,error,output reg [7:0] error_code,
 output reg [10:0] response_length,output reg [MAX_BYTES*8-1:0] response_bytes,
 output wire snapshot_event,output wire [31:0] snapshot_count
);
 localparam IDLE=0,PARSE=1,SYNTH=2,FIRE=3,WAIT_CORE=4,EXTRACT=5,
            REPORT=6,LAYOUT=7,EMIT=8,FINISH=9,TOOBIG=10,COPY_PDU=11,COPY_RESPONSE=12;
 localparam OUTER=0,VERSION=1,HEADER=2,MSGID=3,MAXSIZE=4,FLAGS=5,MODEL=6,
            SECURITY=7,USM=8,ENGINE=9,BOOTS=10,TIME=11,USER=12,AUTH=13,
            PRIV=14,SCOPED=15,CONTEXT_ENGINE=16,CONTEXT_NAME=17,PDU=18;
 reg [3:0] state;reg [4:0] field;
 reg [MAX_BYTES*8-1:0] packet,pdu_bytes,core_request;
 reg [10:0] packet_length,core_length;
 reg v3,engine_ok,user_ok;reg [7:0] auth_length;reg [7:0] flags_q;
 reg [31:0] msgid,peer_max,ticks,engine_time,time_q;
 reg [31:0] unsupported_count,unknown_engine_count,unknown_user_count;
 reg [31:0] report_value;reg [7:0] report_kind;
 reg [5:0] comm_len;reg [255:0] comm,context_name;reg [5:0] context_length;
 integer pos,limit,outer_end,header_end,security_end,usm_end,scope_pos,scope_end;
 integer pdu_pos,pdu_length,cursor,i,k;
 integer ct,ln,en;reg bad;reg [7:0] tag,lbyte;reg [31:0] integer_value;
 integer cstart,pstart,rstart,rid_size,rid_begin,copy_base;
 integer hlen,slen,scoped_len,body_len,total_len,sec_tag,usm_tag,usm_start;
 integer scope_tag,scope_start,pdu_out,header_start,header_tag,engine_pos;
 integer boots_pos,time_pos,user_pos,auth_pos,context_pos,context_name_pos;
 reg [7:0] emitted;reg match_string;
 wire core_done,core_valid,core_error;wire [7:0] core_code;
 wire [10:0] core_response_length;wire [MAX_BYTES*8-1:0] core_response;
 assign busy=state!=IDLE;
 afdx_snmp_extended #(.MAX_BYTES(MAX_BYTES)) core(
  .clk(clk),.rst(rst),.request_valid(state==FIRE),.request_length(core_length),.request_bytes(core_request),
  .community_length(comm_len),.community_bytes(comm),.mib_values(mib_values),.busy(),
  .done(core_done),.response_valid(core_valid),.error(core_error),.error_code(core_code),
  .response_length(core_response_length),.response_bytes(core_response),
  .snapshot_event(snapshot_event),.snapshot_count(snapshot_count),.version_override(2'd0));
 function [7:0] b;input integer n;begin
  if(n>=0&&n<MAX_BYTES)b=packet[n*8+:8];else b=0;
 end endfunction
 function integer ls;input integer n;begin ls=n<128?1:n<256?2:3;end endfunction
 function [7:0] lb;input integer n,j;begin
  if(n<128)lb=n;else if(n<256)lb=j==0?8'h81:n;else lb=j==0?8'h82:j==1?(n>>8):n;
 end endfunction
 function integer il;input [31:0] n;begin
  il=n<128?1:n<32768?2:n<8388608?3:n<32'h80000000 ?4:5;
 end endfunction
 function [7:0] integer_octet;input [31:0] n;input integer j;begin
  if(j==0)integer_octet=2;else if(j==1)integer_octet=il(n);
  else if(il(n)-1-(j-2)==4)integer_octet=0;
  else integer_octet=n>>((il(n)-1-(j-2))*8);
 end endfunction
 task reject;input [7:0] why;begin
  error<=1;error_code<=why;response_valid<=0;response_length<=0;state<=FINISH;
 end endtask
 task next;input [4:0] f;input integer p,e;begin field<=f;pos<=p;limit<=e;state<=PARSE;end endtask
 task report;input [7:0] kind;input [31:0] value;begin
  report_kind<=kind;report_value<=value;context_length<=0;context_name<=0;
  if(flags_q[2])state<=REPORT;else reject(8'h43);
 end endtask
 // Strict bounded BER TLVs; all nesting endpoints checked before access.
 always @*begin
  tag=b(pos);lbyte=b(pos+1);ct=pos+2;ln=0;bad=0;
  if(pos<0||pos+2>limit)bad=1;
  else if(lbyte<128)ln=lbyte;
  else if(lbyte==8'h81&&pos+3<=limit)begin ct=pos+3;ln=b(pos+2);end
  else if(lbyte==8'h82&&pos+4<=limit)begin ct=pos+4;ln={b(pos+2),b(pos+3)};end
  else bad=1;
  en=ct+ln;if(en>limit||en>packet_length||en>MAX_BYTES)bad=1;
  integer_value=0;
  for(k=0;k<4;k=k+1)if(k<ln)integer_value=(integer_value<<8)|b(ct+k);
  match_string=1;
  for(k=0;k<32;k=k+1)if(k<ln)begin
   if(field==ENGINE||field==CONTEXT_ENGINE)begin if(b(ct+k)!=ENGINE_ID[k*8+:8])match_string=0;end
   else if(b(ct+k)!=USER_NAME[k*8+:8])match_string=0;
  end
  emitted=0;
  if(cursor==0)emitted=8'h30;
  else if(cursor<header_start)emitted=lb(body_len,cursor-1);
  else if(cursor==header_start)emitted=2;
  else if(cursor==header_start+1)emitted=1;
  else if(cursor==header_start+2)emitted=3;
  else if(cursor==header_tag)emitted=8'h30;
  else if(cursor<header_tag+1+ls(hlen))emitted=lb(hlen,cursor-header_tag-1);
  else if(cursor<sec_tag)begin
   if(cursor<rstart+2+il(msgid))emitted=integer_octet(msgid,cursor-rstart);
   else if(cursor<rstart+2+il(msgid)+2+il(MAX_BYTES))emitted=integer_octet(MAX_BYTES,cursor-rstart-2-il(msgid));
   else case(cursor-(rstart+2+il(msgid)+2+il(MAX_BYTES)))
    0:emitted=4;1:emitted=1;2:emitted=0;3:emitted=2;4:emitted=1;5:emitted=3;
   endcase
  end else if(cursor==sec_tag)emitted=4;
  else if(cursor<usm_tag)emitted=lb(1+ls(slen)+slen,cursor-sec_tag-1);
  else if(cursor==usm_tag)emitted=8'h30;
  else if(cursor<usm_start)emitted=lb(slen,cursor-usm_tag-1);
  else if(cursor==usm_start)emitted=4;
  else if(cursor==usm_start+1)emitted=ENGINE_LENGTH;
  else if(cursor<boots_pos)emitted=ENGINE_ID[(cursor-usm_start-2)*8+:8];
  else if(cursor<time_pos)emitted=integer_octet({1'b0,ENGINE_BOOTS},cursor-boots_pos);
  else if(cursor<user_pos)emitted=integer_octet(time_q,cursor-time_pos);
  else if(cursor==user_pos)emitted=4;
  else if(cursor==user_pos+1)emitted=USER_LENGTH;
  else if(cursor<auth_pos)emitted=USER_NAME[(cursor-user_pos-2)*8+:8];
  else if(cursor<scope_tag)emitted=((cursor-auth_pos)%2==0)?4:0;
  else if(cursor==scope_tag)emitted=8'h30;
  else if(cursor<scope_start)emitted=lb(scoped_len,cursor-scope_tag-1);
  else if(cursor==scope_start)emitted=4;
  else if(cursor==scope_start+1)emitted=ENGINE_LENGTH;
  else if(cursor<context_name_pos)emitted=ENGINE_ID[(cursor-scope_start-2)*8+:8];
  else if(cursor==context_name_pos)emitted=4;
  else if(cursor==context_name_pos+1)emitted=context_length;
  else if(cursor<pdu_out)emitted=context_name[(cursor-context_name_pos-2)*8+:8];
  else emitted=pdu_bytes[(cursor-pdu_out)*8+:8];
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;field<=OUTER;packet<=0;packet_length<=0;pdu_bytes<=0;
   core_request<=0;core_length<=0;done<=0;response_valid<=0;error<=0;error_code<=0;
   response_length<=0;response_bytes<=0;auth_length<=0;v3<=0;engine_ok<=0;user_ok<=0;flags_q<=0;
   msgid<=0;peer_max<=MAX_BYTES;ticks<=0;engine_time<=0;time_q<=0;
   unsupported_count<=0;unknown_engine_count<=0;unknown_user_count<=0;
   report_value<=0;report_kind<=0;comm_len<=0;comm<=0;context_name<=0;context_length<=0;
   pos<=0;limit<=0;outer_end<=0;header_end<=0;security_end<=0;usm_end<=0;
   copy_base<=0;scope_pos<=0;scope_end<=0;pdu_pos<=0;pdu_length<=0;cursor<=0;
   hlen=0;slen=0;scoped_len=0;body_len=0;total_len=0;sec_tag=0;usm_tag=0;usm_start=0;
   scope_tag=0;scope_start=0;pdu_out=0;header_start=0;header_tag=0;rstart=0;
   boots_pos=0;time_pos=0;user_pos=0;auth_pos=0;context_name_pos=0;
  end else begin
   done<=0;
   if(ticks==CLK_HZ-1)begin ticks<=0;if(engine_time<32'h7fffffff)engine_time<=engine_time+1'b1;end
   else ticks<=ticks+1'b1;
   case(state)
    IDLE:if(request_valid)begin
     packet<=request_bytes;packet_length<=request_length;comm<=community_bytes;comm_len<=community_length;
     response_valid<=0;error<=0;error_code<=0;response_length<=0;response_bytes<=0;
     v3<=0;flags_q<=0;msgid<=0;context_name<=0;context_length<=0;peer_max<=MAX_BYTES;
     if(request_length>MAX_BYTES||request_length<8||ENGINE_LENGTH<5||ENGINE_LENGTH>32||USER_LENGTH<1||USER_LENGTH>32)reject(1);
     else next(OUTER,0,request_length);
    end
    PARSE:if(bad)reject(1);else case(field)
     OUTER:if(tag!=48||en!=packet_length)reject(1);else begin outer_end<=en;next(VERSION,ct,en);end
     VERSION:if(tag!=2||ln!=1)reject(1);else if(b(ct)<=1)begin core_request<=packet;core_length<=packet_length;state<=FIRE;end
      else if(b(ct)!=3)reject(5);else begin v3<=1;next(HEADER,en,outer_end);end
     HEADER:if(tag!=48)reject(1);else begin header_end<=en;next(MSGID,ct,en);end
     MSGID,MAXSIZE,MODEL,BOOTS,TIME:begin
      if(tag!=2||ln<1||ln>4||b(ct)>=128)reject(1);
      else case(field)
       MSGID:begin msgid<=integer_value;next(MAXSIZE,en,header_end);end
       MAXSIZE:if(integer_value<484)reject(1);else begin peer_max<=integer_value;next(FLAGS,en,header_end);end
       MODEL:if(integer_value!=3||en!=header_end)reject(8'h40);else next(SECURITY,en,outer_end);
       BOOTS:next(TIME,en,usm_end);
       TIME:next(USER,en,usm_end);
      endcase
     end
     FLAGS:if(tag!=4||ln!=1||(b(ct)&8'hf8)!=0)reject(8'h41);
      else begin flags_q<=b(ct);next(MODEL,en,header_end);end
     // Reserved security-level encodings are not rejected here on purpose:
     // they must pass through engine/user discovery first so the
     // unknownEngineID/unknownUserName counters are never skipped. The level
     // decision is taken centrally at the PRIV field below.
     SECURITY:if(tag!=4)reject(1);else begin security_end<=en;scope_pos<=en;next(USM,ct,en);end
     USM:if(tag!=48||en!=security_end)reject(1);else begin usm_end<=en;next(ENGINE,ct,en);end
     ENGINE:if(tag!=4||ln>32)reject(1);else begin engine_ok<=ln==ENGINE_LENGTH&&match_string;next(BOOTS,en,usm_end);end
     USER:if(tag!=4||ln>32)reject(1);else begin user_ok<=ln==USER_LENGTH&&match_string;next(AUTH,en,usm_end);end
     AUTH:if(tag!=4||ln>48)reject(1);else begin auth_length<=ln;next(PRIV,en,usm_end);end
     PRIV:if(tag!=4||ln>32||en!=usm_end)reject(1);else begin
      if(!engine_ok)begin unknown_engine_count<=unknown_engine_count+1'b1;report(4,unknown_engine_count+1'b1);end
      else if(!user_ok)begin unknown_user_count<=unknown_user_count+1'b1;report(3,unknown_user_count+1'b1);end
      else if(flags_q[1:0]!=0)begin
       // Centralized USM security-level decision for authNoPriv (01),
       // authPriv (11) and the reserved encoding (10). The counter is always
       // incremented here; the report() task honors the response-enable flag
       // (flags bit 2), so non-reportable messages stay silent as required.
       unsupported_count<=unsupported_count+1'b1;
       if(flags_q[0])report(1,unsupported_count+1'b1);else reject(8'h41);
      end
      else if(auth_length!=0||ln!=0)reject(1);else next(SCOPED,scope_pos,outer_end);
     end
     SCOPED:if(tag!=48||en!=outer_end)reject(1);else begin scope_end<=en;next(CONTEXT_ENGINE,ct,en);end
     CONTEXT_ENGINE:if(tag!=4||ln!=ENGINE_LENGTH||!match_string)reject(8'h44);else next(CONTEXT_NAME,en,scope_end);
     CONTEXT_NAME:if(tag!=4||ln!=0)reject(8'h45);else begin context_length<=0;next(PDU,en,scope_end);end
     PDU:if((tag!=8'ha0&&tag!=8'ha1&&tag!=8'ha3&&tag!=8'ha5)||en!=scope_end)reject(3);
      else begin pdu_pos<=pos;pdu_length<=en-pos;state<=SYNTH;end
    endcase
    SYNTH:begin
     body_len=3+2+comm_len+pdu_length;cstart=1+ls(body_len);pstart=cstart+5+comm_len;
     if(pstart+pdu_length>MAX_BYTES||comm_len==0||comm_len>32)reject(1);
     else begin
      core_request<=0;core_request[7:0]<=48;
      for(i=0;i<3;i=i+1)if(i<ls(body_len))core_request[(i+1)*8+:8]<=lb(body_len,i);
      core_request[cstart*8+:24]<=24'h010102;core_request[(cstart+3)*8+:8]<=4;core_request[(cstart+4)*8+:8]<=comm_len;
      for(i=0;i<32;i=i+1)if(i<comm_len)core_request[(cstart+5+i)*8+:8]<=comm[i*8+:8];
      copy_base<=pstart;cursor<=0;core_length<=pstart+pdu_length;state<=COPY_PDU;
     end
    end
    COPY_PDU:begin
     core_request[(copy_base+cursor)*8+:8]<=b(pdu_pos+cursor);
     if(cursor+1==pdu_length)state<=FIRE;else cursor<=cursor+1;
    end
    FIRE:state<=WAIT_CORE;
    WAIT_CORE:if(core_done)begin
     if(core_error||!core_valid)reject(core_code);
     else if(!v3)begin response_bytes<=core_response;response_length<=core_response_length;response_valid<=1;state<=FINISH;end
     else state<=EXTRACT;
    end
    EXTRACT:begin
     cstart=core_response[15:8]<128?2:core_response[15:8]==8'h81 ?3:4;
     pstart=cstart+5+comm_len;pdu_length<=core_response_length-pstart;
     copy_base<=pstart;pdu_bytes<=0;cursor<=0;time_q<=engine_time;state<=COPY_RESPONSE;
    end
    COPY_RESPONSE:begin
     pdu_bytes[cursor*8+:8]<=core_response[(copy_base+cursor)*8+:8];
     if(cursor+1==pdu_length)state<=LAYOUT;else cursor<=cursor+1;
    end
    REPORT:begin
     // Report request-id=0 when security processing failed before PDU dispatch.
     pdu_bytes<=0;pdu_bytes[7:0]<=8'ha8;pdu_bytes[15:8]<=27+il(report_value);
     pdu_bytes[16+:72]<=72'h000102000102000102;
     pdu_bytes[88+:8]<=48;pdu_bytes[96+:8]<=16+il(report_value);
     pdu_bytes[104+:8]<=48;pdu_bytes[112+:8]<=14+il(report_value);
     pdu_bytes[120+:8]<=6;pdu_bytes[128+:8]<=10;
     pdu_bytes[136+:64]<=64'h01010f030601062b;
     pdu_bytes[200+:8]<=report_kind;pdu_bytes[208+:8]<=0;
     pdu_bytes[216+:8]<=8'h41;pdu_bytes[224+:8]<=il(report_value);
     for(i=0;i<5;i=i+1)if(i<il(report_value))pdu_bytes[(29+i)*8+:8]<=i==0&&il(report_value)==5?0:report_value>>((il(report_value)-i-1)*8);
     pdu_length<=29+il(report_value);time_q<=engine_time;state<=LAYOUT;
    end
    LAYOUT:begin
     hlen=2+il(msgid)+2+il(MAX_BYTES)+6;
     slen=2+ENGINE_LENGTH+2+il({1'b0,ENGINE_BOOTS})+2+il(time_q)+2+USER_LENGTH+4;
     scoped_len=2+ENGINE_LENGTH+2+context_length+pdu_length;
     body_len=3+1+ls(hlen)+hlen+1+ls(1+ls(slen)+slen)+1+ls(slen)+slen+1+ls(scoped_len)+scoped_len;
     total_len=1+ls(body_len)+body_len;
     if(total_len>MAX_BYTES||total_len>peer_max)state<=TOOBIG;
     else begin
      header_start=1+ls(body_len);header_tag=header_start+3;rstart=header_tag+1+ls(hlen);
      sec_tag=rstart+hlen;usm_tag=sec_tag+1+ls(1+ls(slen)+slen);usm_start=usm_tag+1+ls(slen);
      boots_pos=usm_start+2+ENGINE_LENGTH;time_pos=boots_pos+2+il({1'b0,ENGINE_BOOTS});
      user_pos=time_pos+2+il(time_q);auth_pos=user_pos+2+USER_LENGTH;
      scope_tag=auth_pos+4;scope_start=scope_tag+1+ls(scoped_len);
      context_name_pos=scope_start+2+ENGINE_LENGTH;pdu_out=context_name_pos+2+context_length;
      cursor<=0;response_length<=total_len;state<=EMIT;
     end
    end
    TOOBIG:begin
     rid_begin=pdu_bytes[15:8]<128?2:pdu_bytes[15:8]==8'h81 ?3:4;
     rid_size=2+pdu_bytes[(rid_begin+1)*8+:8];
     if(rid_size<3||rid_size>6||pdu_length<rid_begin+rid_size)reject(1);
     else begin
      pdu_bytes<=0;pdu_bytes[7:0]<=8'ha2;pdu_bytes[15:8]<=rid_size+8;
      for(i=0;i<6;i=i+1)if(i<rid_size)pdu_bytes[(2+i)*8+:8]<=pdu_bytes[(rid_begin+i)*8+:8];
      pdu_bytes[(2+rid_size)*8+:64]<=64'h0030000102010102;
      pdu_length<=rid_size+10;state<=LAYOUT;
     end
    end
    EMIT:begin response_bytes[cursor*8+:8]<=emitted;
     if(cursor+1==response_length)begin response_valid<=1;state<=FINISH;end else cursor<=cursor+1;
    end
    FINISH:begin done<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
