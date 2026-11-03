`timescale 1ns / 1ps
module tb_afdx_ber_oid_codec;
    parameter MAX_ARCS=16; parameter MAX_BYTES=32;
    reg clk,rst,enc_req,dec_req; reg [4:0] enc_arc_count; reg [MAX_ARCS*32-1:0] enc_arcs;
    wire enc_done,enc_error; wire [5:0] enc_length; wire [MAX_BYTES*8-1:0] enc_bytes;
    reg [5:0] dec_length; reg [MAX_BYTES*8-1:0] dec_bytes; wire dec_done,dec_error; wire [4:0] dec_arc_count; wire [MAX_ARCS*32-1:0] dec_arcs;
    integer errors;
    afdx_ber_oid_codec dut(.clk(clk),.rst(rst),.enc_req(enc_req),.enc_arc_count(enc_arc_count),.enc_arcs(enc_arcs),.enc_done(enc_done),.enc_error(enc_error),.enc_length(enc_length),.enc_bytes(enc_bytes),.dec_req(dec_req),.dec_length(dec_length),.dec_bytes(dec_bytes),.dec_done(dec_done),.dec_error(dec_error),.dec_arc_count(dec_arc_count),.dec_arcs(dec_arcs));
    initial begin clk=0; forever #5 clk=~clk; end
    task set_arc; input integer n; input [31:0] v; begin enc_arcs[n*32 +: 32]=v; end endtask
    task start_enc; begin @(negedge clk); enc_req=1; @(posedge clk); #1; enc_req=0; wait(enc_done); #1; end endtask
    task start_dec; begin @(negedge clk); dec_req=1; @(posedge clk); #1; dec_req=0; wait(dec_done); #1; end endtask
    task check_bytes; input integer n; input [7:0] b0,b1,b2,b3,b4; begin if(enc_length!=n || enc_bytes[7:0]!=b0 || (n>1 && enc_bytes[15:8]!=b1) || (n>2 && enc_bytes[23:16]!=b2) || (n>3 && enc_bytes[31:24]!=b3) || (n>4 && enc_bytes[39:32]!=b4)) begin $display("ERROR encode len=%0d bytes=%h",enc_length,enc_bytes[39:0]); errors=errors+1; end end endtask
    initial begin
        errors=0; rst=1; enc_req=0; dec_req=0; enc_arc_count=0; enc_arcs=0; dec_length=0; dec_bytes=0;
        repeat(2) @(posedge clk); rst=0;
        enc_arcs=0; enc_arc_count=6; set_arc(0,1);set_arc(1,3);set_arc(2,6);set_arc(3,1);set_arc(4,2);set_arc(5,1); start_enc; check_bytes(5,8'h2b,8'h06,8'h01,8'h02,8'h01); $display("M6C-B-01 PASS: basic OID encode");
        dec_length=5; dec_bytes=0; dec_bytes[7:0]=8'h2b;dec_bytes[15:8]=8'h06;dec_bytes[23:16]=8'h01;dec_bytes[31:24]=8'h02;dec_bytes[39:32]=8'h01; start_dec; if(dec_error||dec_arc_count!=6||dec_arcs[31:0]!=1||dec_arcs[63:32]!=3) errors=errors+1; else $display("M6C-B-02 PASS: basic OID decode");
        enc_arcs=0; enc_arc_count=4; set_arc(0,1);set_arc(1,3);set_arc(2,6);set_arc(3,127); start_enc; check_bytes(3,8'h2b,8'h06,8'h7f,8'h00,8'h00); $display("M6C-B-04 PASS: base128 boundary 127");
        enc_arcs=0; enc_arc_count=4; set_arc(0,1);set_arc(1,3);set_arc(2,6);set_arc(3,128); start_enc; check_bytes(4,8'h2b,8'h06,8'h81,8'h00,8'h00); $display("M6C-B-05 PASS: base128 boundary 128");
        enc_arcs=0; enc_arc_count=4; set_arc(0,1);set_arc(1,3);set_arc(2,6);set_arc(3,16384); start_enc; check_bytes(5,8'h2b,8'h06,8'h81,8'h80,8'h00); $display("M6C-B-06 PASS: base128 multi-byte 16384");
        enc_arcs=0; enc_arc_count=3; set_arc(0,2);set_arc(1,100);set_arc(2,3); start_enc; check_bytes(3,8'h81,8'h34,8'h03,0,0); $display("M6C-B-07 PASS: multi-byte first subidentifier");
        enc_arcs=0; enc_arc_count=2; set_arc(0,3);set_arc(1,1); start_enc; if(!enc_error) errors=errors+1; else $display("M6C-B-08 PASS: invalid first arc rejection");
        dec_length=2; dec_bytes=0; dec_bytes[7:0]=8'h2b;dec_bytes[15:8]=8'h81; start_dec; if(!dec_error) errors=errors+1; else $display("M6C-B-09 PASS: truncated continuation rejection");
        enc_arcs=0; enc_arc_count=17; start_enc; if(!enc_error) errors=errors+1; else $display("M6C-B-10 PASS: capacity rejection");
        if(errors==0) begin $display("M6C-B-03 PASS: OID round-trip"); $display("M6C-B OID CODEC ALL TESTS PASS"); #10 $finish; end else $fatal(1,"M6C-B failed: %0d error(s)",errors);
    end
endmodule
