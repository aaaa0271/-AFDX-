`timescale 1ns/1ps
// Selected-clock monitor. A selector change/reacquisition reanchors instead of
// classifying a legitimate switch to a different clock view as a UTC attack.
module afdx_sec_time_monitor #(parameter integer CLK_HZ=12500000,SAMPLE_CYCLES=125000)(
 input wire clk,rst,reanchor,locked,input wire [63:0] utc,monotonic,limit,
 output reg pulse,output reg [3:0] flags,output reg [31:0] alarms
);
reg previous_lock,anchored;reg [31:0] age;reg [63:0] old_utc,old_mono;
reg [95:0] numerator;reg [63:0] expected,actual,difference;
always @(posedge clk)begin
 if(rst)begin pulse<=0;flags<=0;alarms<=0;previous_lock<=0;anchored<=0;age<=0;old_utc<=0;old_mono<=0;end
 else begin
  pulse<=0;previous_lock<=locked;
  if(reanchor||!locked)begin anchored<=0;age<=0;if(previous_lock&&!locked&&!reanchor)begin pulse<=1;flags<=4'b0100;alarms<=alarms+1'b1;end end
  else if(!anchored)begin anchored<=1;old_utc<=utc;old_mono<=monotonic;age<=0;end
  else if(age>=SAMPLE_CYCLES-1)begin
   age<=0;old_utc<=utc;old_mono<=monotonic;flags<=0;
   numerator={32'd0,(monotonic-old_mono)}<<32;expected=numerator/CLK_HZ;
   actual=utc-old_utc;difference=actual>=expected?actual-expected:expected-actual;
   if(monotonic<old_mono)begin flags<=4'b0001;pulse<=1;alarms<=alarms+1'b1;end
   else if(utc<old_utc||difference>limit+2)begin flags<=4'b0010;pulse<=1;alarms<=alarms+1'b1;end
  end else age<=age+1'b1;
 end
end
endmodule
