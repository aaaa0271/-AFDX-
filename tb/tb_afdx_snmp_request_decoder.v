`timescale 1ns / 1ps

module tb_afdx_snmp_request_decoder;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, req=0;
    reg [7:0] msg_length=0;
    reg [1023:0] msg_bytes=0;
    wire done, error;
    wire [3:0] error_code;
    wire request_op;
    wire [31:0] request_id;
    wire [7:0] object_id;
    wire [7:0] community_length;
    wire [47:0] community_bytes;
    integer errors;

    afdx_snmp_request_decoder u_dut (
        .clk(clk), .rst(rst), .req(req), .msg_length(msg_length), .msg_bytes(msg_bytes),
        .done(done), .error(error), .error_code(error_code), .request_op(request_op),
        .request_id(request_id), .object_id(object_id), .community_length(community_length),
        .community_bytes(community_bytes)
    );

    task automatic make_message;
        input op;
        input [7:0] oid;
        input bad_public;
        input malformed;
        input set_pdu;
        integer i;
        begin
            msg_bytes = 0;
            msg_bytes[0*8 +: 8] = 8'h30; msg_bytes[1*8 +: 8] = 8'h2A;
            msg_bytes[2*8 +: 8] = 8'h02; msg_bytes[3*8 +: 8] = 8'h01; msg_bytes[4*8 +: 8] = 8'h00;
            msg_bytes[5*8 +: 8] = 8'h04; msg_bytes[6*8 +: 8] = 8'h06;
            msg_bytes[7*8 +: 8] = bad_public ? "x" : "p";
            msg_bytes[8*8 +: 8] = "u"; msg_bytes[9*8 +: 8] = "b"; msg_bytes[10*8 +: 8] = "l";
            msg_bytes[11*8 +: 8] = "i"; msg_bytes[12*8 +: 8] = "c";
            msg_bytes[13*8 +: 8] = set_pdu ? 8'hA3 : (op ? 8'hA1 : 8'hA0);
            msg_bytes[14*8 +: 8] = 8'h1D;
            msg_bytes[15*8 +: 8] = 8'h02; msg_bytes[16*8 +: 8] = 8'h03;
            msg_bytes[17*8 +: 8] = 8'h00; msg_bytes[18*8 +: 8] = 8'h00; msg_bytes[19*8 +: 8] = 8'h01;
            msg_bytes[20*8 +: 8] = 8'h02; msg_bytes[21*8 +: 8] = 8'h01; msg_bytes[22*8 +: 8] = 8'h00;
            msg_bytes[23*8 +: 8] = 8'h02; msg_bytes[24*8 +: 8] = 8'h01; msg_bytes[25*8 +: 8] = 8'h00;
            msg_bytes[26*8 +: 8] = 8'h30; msg_bytes[27*8 +: 8] = 8'h10;
            msg_bytes[28*8 +: 8] = 8'h30; msg_bytes[29*8 +: 8] = 8'h0E;
            msg_bytes[30*8 +: 8] = 8'h06; msg_bytes[31*8 +: 8] = 8'h0A;
            msg_bytes[32*8 +: 8] = 8'h2B; msg_bytes[33*8 +: 8] = 8'h06; msg_bytes[34*8 +: 8] = 8'h01;
            msg_bytes[35*8 +: 8] = 8'h04; msg_bytes[36*8 +: 8] = 8'h01; msg_bytes[37*8 +: 8] = 8'h81;
            msg_bytes[38*8 +: 8] = 8'hFD; msg_bytes[39*8 +: 8] = 8'h59; msg_bytes[40*8 +: 8] = 8'h01;
            msg_bytes[41*8 +: 8] = oid; msg_bytes[42*8 +: 8] = 8'h05; msg_bytes[43*8 +: 8] = 8'h00;
            msg_length = malformed ? 8'd44 : 8'd44;
            if (malformed) msg_bytes[1*8 +: 8] = 8'h28;
        end
    endtask

    task automatic run_case;
        input integer id; input op; input [7:0] oid; input bad_public; input malformed; input set_pdu;
        input expected_error; input [3:0] expected_code; input expected_op;
        begin
            make_message(op, oid, bad_public, malformed, set_pdu);
            if (malformed)
                msg_length = 8'd43;
            else
                msg_length = 8'd44;
            #1;
            @(negedge clk); req=1;
            @(posedge clk); #1;
            if ((error!==expected_error) || (error_code!==expected_code) || (request_op!==expected_op) ||
                (!expected_error && (object_id!==oid || request_id!==32'd1))) begin
                $display("M6D-A-%02d FAIL err=%b code=%d op=%b oid=%d id=%h",id,error,error_code,request_op,object_id,request_id);
                errors=errors+1;
            end else $display("M6D-A-%02d PASS",id);
            @(negedge clk); req=0;
        end
    endtask

    initial begin
        errors=0; #20; rst=0;
        run_case(1,0,8'd1,0,0,0,0,0,0);
        run_case(2,1,8'd25,0,0,0,0,0,1);
        run_case(3,0,8'd1,1,0,0,1,2,0);
        run_case(4,0,8'd1,0,1,0,1,1,0);
        run_case(5,0,8'd1,0,0,1,1,4,0);
        run_case(6,0,8'd0,0,0,0,1,7,0);
        $display("M6D-A decoder errors: %0d",errors);
        if(errors==0) $display("M6D-A REQUEST DECODER PASS"); else $display("M6D-A REQUEST DECODER FAIL");
        $finish;
    end
endmodule
