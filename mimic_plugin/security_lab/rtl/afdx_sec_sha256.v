`timescale 1ns/1ps
// Iterative SHA-256, message read port; no simulation-only crypto task.
module afdx_sec_sha256(input wire clk,rst,start,input wire [15:0] length,
 output wire [15:0] address,input wire [7:0] data,
 output wire busy,output reg done,output reg [255:0] digest);
reg [1:0] state;reg [15:0] len,position,total;reg [5:0] fill,round_q;
reg [31:0] w[0:63],h[0:7];reg [31:0] a,b,c,d,e,f,g,hh;
reg [31:0] word_q,word_next,t1,t2,an,en;reg [7:0] byte_q;reg [63:0] bit_length;integer i;
assign address=position;assign busy=state!=0;
function [31:0] rr;input [31:0] x;input integer n;begin rr=(x>>n)|(x<<(32-n));end endfunction
function [31:0] constant_k;input [5:0] n;begin case(n)
6'd0:constant_k=32'h428a2f98;
6'd1:constant_k=32'h71374491;
6'd2:constant_k=32'hb5c0fbcf;
6'd3:constant_k=32'he9b5dba5;
6'd4:constant_k=32'h3956c25b;
6'd5:constant_k=32'h59f111f1;
6'd6:constant_k=32'h923f82a4;
6'd7:constant_k=32'hab1c5ed5;
6'd8:constant_k=32'hd807aa98;
6'd9:constant_k=32'h12835b01;
6'd10:constant_k=32'h243185be;
6'd11:constant_k=32'h550c7dc3;
6'd12:constant_k=32'h72be5d74;
6'd13:constant_k=32'h80deb1fe;
6'd14:constant_k=32'h9bdc06a7;
6'd15:constant_k=32'hc19bf174;
6'd16:constant_k=32'he49b69c1;
6'd17:constant_k=32'hefbe4786;
6'd18:constant_k=32'h0fc19dc6;
6'd19:constant_k=32'h240ca1cc;
6'd20:constant_k=32'h2de92c6f;
6'd21:constant_k=32'h4a7484aa;
6'd22:constant_k=32'h5cb0a9dc;
6'd23:constant_k=32'h76f988da;
6'd24:constant_k=32'h983e5152;
6'd25:constant_k=32'ha831c66d;
6'd26:constant_k=32'hb00327c8;
6'd27:constant_k=32'hbf597fc7;
6'd28:constant_k=32'hc6e00bf3;
6'd29:constant_k=32'hd5a79147;
6'd30:constant_k=32'h06ca6351;
6'd31:constant_k=32'h14292967;
6'd32:constant_k=32'h27b70a85;
6'd33:constant_k=32'h2e1b2138;
6'd34:constant_k=32'h4d2c6dfc;
6'd35:constant_k=32'h53380d13;
6'd36:constant_k=32'h650a7354;
6'd37:constant_k=32'h766a0abb;
6'd38:constant_k=32'h81c2c92e;
6'd39:constant_k=32'h92722c85;
6'd40:constant_k=32'ha2bfe8a1;
6'd41:constant_k=32'ha81a664b;
6'd42:constant_k=32'hc24b8b70;
6'd43:constant_k=32'hc76c51a3;
6'd44:constant_k=32'hd192e819;
6'd45:constant_k=32'hd6990624;
6'd46:constant_k=32'hf40e3585;
6'd47:constant_k=32'h106aa070;
6'd48:constant_k=32'h19a4c116;
6'd49:constant_k=32'h1e376c08;
6'd50:constant_k=32'h2748774c;
6'd51:constant_k=32'h34b0bcb5;
6'd52:constant_k=32'h391c0cb3;
6'd53:constant_k=32'h4ed8aa4a;
6'd54:constant_k=32'h5b9cca4f;
6'd55:constant_k=32'h682e6ff3;
6'd56:constant_k=32'h748f82ee;
6'd57:constant_k=32'h78a5636f;
6'd58:constant_k=32'h84c87814;
6'd59:constant_k=32'h8cc70208;
6'd60:constant_k=32'h90befffa;
6'd61:constant_k=32'ha4506ceb;
6'd62:constant_k=32'hbef9a3f7;
6'd63:constant_k=32'hc67178f2;
endcase end endfunction
always @*begin
 bit_length={48'd0,len}<<3;
 byte_q=0;
 if(position<len)byte_q=data;
 else if(position==len)byte_q=8'h80;
 else if(position>=total-8)byte_q=bit_length>>((total-1-position)*8);
 word_next=round_q<16?w[round_q]:(rr(w[round_q-2],17)^rr(w[round_q-2],19)^(w[round_q-2]>>10))+w[round_q-7]+(rr(w[round_q-15],7)^rr(w[round_q-15],18)^(w[round_q-15]>>3))+w[round_q-16];
 t1=hh+(rr(e,6)^rr(e,11)^rr(e,25))+((e&f)^((~e)&g))+constant_k(round_q)+word_next;
 t2=(rr(a,2)^rr(a,13)^rr(a,22))+((a&b)^(a&c)^(b&c));an=t1+t2;en=d+t1;
end
always @(posedge clk)begin
 if(rst)begin state<=0;done<=0;digest<=0;position<=0;len<=0;total<=0;fill<=0;round_q<=0;word_q<=0;a<=0;b<=0;c<=0;d<=0;e<=0;f<=0;g<=0;hh<=0;for(i=0;i<8;i=i+1)h[i]<=0;end
 else begin
  done<=0;
  if(start&&state==0)begin len<=length;total<=((length+16'd72)>>6)<<6;position<=0;fill<=0;word_q<=0;state<=1;
   h[0]<=32'h6a09e667;h[1]<=32'hbb67ae85;h[2]<=32'h3c6ef372;h[3]<=32'ha54ff53a;h[4]<=32'h510e527f;h[5]<=32'h9b05688c;h[6]<=32'h1f83d9ab;h[7]<=32'h5be0cd19;
  end
  if(state==1)begin
   word_q<={word_q[23:0],byte_q};position<=position+1'b1;
   if(fill[1:0]==3)w[fill>>2]<={word_q[23:0],byte_q};
   if(fill==63)begin state<=2;round_q<=0;a<=h[0];b<=h[1];c<=h[2];d<=h[3];e<=h[4];f<=h[5];g<=h[6];hh<=h[7];end
   else fill<=fill+1'b1;
  end
  if(state==2)begin
   if(round_q>=16)w[round_q]<=word_next;
   a<=an;b<=a;c<=b;d<=c;e<=en;f<=e;g<=f;hh<=g;
   if(round_q==63)begin
    h[0]<=h[0]+an;h[1]<=h[1]+a;h[2]<=h[2]+b;h[3]<=h[3]+c;h[4]<=h[4]+en;h[5]<=h[5]+e;h[6]<=h[6]+f;h[7]<=h[7]+g;
    if(position==total)begin state<=0;done<=1;digest<={h[0]+an,h[1]+a,h[2]+b,h[3]+c,h[4]+en,h[5]+e,h[6]+f,h[7]+g};end
    else begin state<=1;fill<=0;word_q<=0;end
   end else round_q<=round_q+1'b1;
  end
 end
end
endmodule
