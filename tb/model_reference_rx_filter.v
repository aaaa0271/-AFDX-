`timescale 1ns/1ps
// Reference-host input queue: capture the real wire without backpressure,
// select the host IP, then deliver to its protocol parser at host speed.
module model_reference_rx_filter #(parameter [31:0] HOST_IP=32'h0a000001)(
 input wire clk,rst,input wire [7:0] data,input wire valid,error,
 output reg [7:0] host_data=0,output reg host_valid=0,host_error=0,
 output reg [31:0] overflows=0
);
reg [7:0] frame[0:1535],queue[0:49151];integer lengths[0:31];reg bad[0:31];
integer used=0,head=0,tail=0,count=0,index=0,delay=0,j;reg previous=0,frame_bad=0,playing=0;
always @(negedge clk)begin
 if(rst)begin used=0;head=0;tail=0;count=0;index=0;delay=0;previous=0;frame_bad=0;playing=0;host_valid=0;host_error=0;overflows=0;end
 else begin
  if(valid)begin
   if(!previous)begin count=0;frame_bad=0;end
   if(count<1536)frame[count]=data;else frame_bad=1;
   count=count+1;if(error)frame_bad=1;
  end else if(previous&&count>=54&&count<=1536&&{frame[38],frame[39],frame[40],frame[41]}==HOST_IP)begin
   if(used>=32)overflows=overflows+1;
   else begin
    lengths[tail]=count;bad[tail]=frame_bad;for(j=0;j<count;j=j+1)queue[tail*1536+j]=frame[j];tail=(tail+1)%32;used=used+1;
   end
  end
  previous=valid;host_valid=0;host_error=0;
  if(delay!=0)delay=delay-1;
  else begin
   if(!playing&&used!=0)begin playing=1;index=0;end
   if(playing)begin
    host_data=queue[head*1536+index];host_valid=1;host_error=bad[head];
    if(index==lengths[head]-1)begin delay=lengths[head]+32;playing=0;head=(head+1)%32;used=used-1;end
    else index=index+1;
   end
  end
 end
end
endmodule