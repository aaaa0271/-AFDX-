`timescale 1ns / 1ps


module tb_afdx_payload_commit_buffer;


// ============================================================
// Clock / Reset
// ============================================================

reg clk;
reg rst;


initial begin

    clk = 1'b0;

    forever #5 clk = ~clk;

end


// ============================================================
// DUT input
// ============================================================

reg [7:0] in_data;
reg       in_valid;

wire      in_ready;

reg       in_sof;
reg       in_eof;


// ============================================================
// Decision
// ============================================================

reg decision_valid;
reg decision_accept;


// ============================================================
// DUT output
// ============================================================

wire [7:0] out_data;
wire       out_valid;

reg        out_ready;

wire       out_sof;
wire       out_eof;


// ============================================================
// Status
// ============================================================

wire capture_active;
wire frame_buffered;
wire replay_active;

wire overflow_error;


// ============================================================
// DUT
// ============================================================

afdx_payload_commit_buffer
#(
    .MAX_PAYLOAD_BYTES (32),
    .ADDR_WIDTH        (5)
)
dut
(
    .clk               (clk),
    .rst               (rst),

    .in_data           (in_data),
    .in_valid          (in_valid),
    .in_ready          (in_ready),

    .in_sof            (in_sof),
    .in_eof            (in_eof),

    .decision_valid    (decision_valid),
    .decision_accept   (decision_accept),

    .out_data          (out_data),
    .out_valid         (out_valid),
    .out_ready         (out_ready),

    .out_sof           (out_sof),
    .out_eof           (out_eof),

    .capture_active    (capture_active),
    .frame_buffered    (frame_buffered),
    .replay_active     (replay_active),

    .overflow_error    (overflow_error)
);


// ============================================================
// Scoreboard
// ============================================================

integer error_count;
integer output_count;

integer case_error_start;

reg [7:0] received [0:63];

reg cap_sof [0:63];
reg cap_eof [0:63];


// ============================================================
// Capture application output
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        output_count <= 0;

    end
    else begin

        if (out_valid && out_ready) begin

            received[output_count] <=
                out_data;

            cap_sof[output_count] <=
                out_sof;

            cap_eof[output_count] <=
                out_eof;

            output_count <=
                output_count + 1;

        end

    end

end


// ============================================================
// Reset DUT
// ============================================================

task reset_dut;

begin

    rst = 1'b1;

    in_data  = 8'h00;
    in_valid = 1'b0;
    in_sof   = 1'b0;
    in_eof   = 1'b0;

    decision_valid  = 1'b0;
    decision_accept = 1'b0;

    out_ready = 1'b1;

    repeat (5)
        @(posedge clk);

    @(negedge clk);

    rst = 1'b0;

    repeat (2)
        @(posedge clk);

end

endtask


// ============================================================
// Clear output scoreboard
// ============================================================

task clear_scoreboard;

integer i;

begin

    output_count = 0;

    for (i = 0; i < 64; i = i + 1) begin

        received[i] = 8'h00;

        cap_sof[i] = 1'b0;
        cap_eof[i] = 1'b0;

    end

end

endtask


// ============================================================
// Send one payload byte
// ============================================================

task send_byte;

input [7:0] data;
input       sof;
input       eof;

begin

    @(negedge clk);

    in_data  = data;
    in_sof   = sof;
    in_eof   = eof;
    in_valid = 1'b1;


    while (!in_ready)
        @(negedge clk);


    @(negedge clk);

    in_valid = 1'b0;
    in_sof   = 1'b0;
    in_eof   = 1'b0;

end

endtask


// ============================================================
// Send decision
// ============================================================

task send_decision;

input accept;

begin

    @(negedge clk);

    decision_accept = accept;
    decision_valid  = 1'b1;

    @(negedge clk);

    decision_valid  = 1'b0;
    decision_accept = 1'b0;

end

endtask


// ============================================================
// Wait until replay is finished
// ============================================================

task wait_idle;

integer timeout;

begin

    timeout = 0;

    while (
        (replay_active || frame_buffered) &&
        timeout < 100
    ) begin

        @(posedge clk);

        timeout = timeout + 1;

    end


    if (timeout >= 100) begin

        $display(
            "ERROR: wait_idle timeout"
        );

        error_count = error_count + 1;

    end

end

endtask


// ============================================================
// Check one byte
// ============================================================

task check_byte;

input integer index;
input [7:0] expected;

begin

    if (received[index] !== expected) begin

        $display(
            "ERROR byte[%0d]: expected=%02x actual=%02x",
            index,
            expected,
            received[index]
        );

        error_count = error_count + 1;

    end

end

endtask


// ============================================================
// Main test
// ============================================================

initial begin

    error_count = 0;

    reset_dut;


    // ========================================================
    // TC1
    //
    // Normal frame:
    //
    // capture
    // EOF
    // wait decision
    // ACCEPT
    // replay
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;

    send_byte(8'h11, 1'b1, 1'b0);
    send_byte(8'h22, 1'b0, 1'b0);
    send_byte(8'h33, 1'b0, 1'b1);


    repeat (3)
        @(posedge clk);


    if (!frame_buffered) begin

        $display(
            "TC1 ERROR: frame_buffered not asserted"
        );

        error_count = error_count + 1;

    end


    send_decision(1'b1);

    wait_idle;

    repeat (2)
        @(posedge clk);


    if (output_count != 3) begin

        $display(
            "TC1 ERROR: output_count=%0d expected=3",
            output_count
        );

        error_count = error_count + 1;

    end


    check_byte(0, 8'h11);
    check_byte(1, 8'h22);
    check_byte(2, 8'h33);


    if (!cap_sof[0]) begin

        $display(
            "TC1 ERROR: SOF missing"
        );

        error_count = error_count + 1;

    end


    if (!cap_eof[2]) begin

        $display(
            "TC1 ERROR: EOF missing"
        );

        error_count = error_count + 1;

    end


    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-1 PASS");
    else
        $display("TC-M3D-COMMIT-1 FAIL");


    // ========================================================
    // TC2
    //
    // Entire frame rejected.
    //
    // No payload byte may escape to application.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;

    send_byte(8'h41, 1'b1, 1'b0);
    send_byte(8'h42, 1'b0, 1'b0);
    send_byte(8'h43, 1'b0, 1'b1);


    repeat (2)
        @(posedge clk);


    send_decision(1'b0);


    repeat (5)
        @(posedge clk);


    if (output_count != 0) begin

        $display(
            "TC2 ERROR: rejected frame leaked %0d bytes",
            output_count
        );

        error_count = error_count + 1;

    end

    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-2 PASS");
    else
        $display("TC-M3D-COMMIT-2 FAIL");


    // ========================================================
    // TC3
    //
    // Delayed decision.
    //
    // Buffer must hold complete frame safely.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;

    send_byte(8'h51, 1'b1, 1'b0);
    send_byte(8'h52, 1'b0, 1'b0);
    send_byte(8'h53, 1'b0, 1'b0);
    send_byte(8'h54, 1'b0, 1'b1);


    repeat (10)
        @(posedge clk);


    if (output_count != 0) begin

        $display(
            "TC3 ERROR: payload escaped before decision"
        );

        error_count = error_count + 1;

    end


    if (!frame_buffered) begin

        $display(
            "TC3 ERROR: frame not held"
        );

        error_count = error_count + 1;

    end


    send_decision(1'b1);

    wait_idle;


    if (output_count != 4) begin

        $display(
            "TC3 ERROR: output_count=%0d expected=4",
            output_count
        );

        error_count = error_count + 1;

    end


    check_byte(0, 8'h51);
    check_byte(1, 8'h52);
    check_byte(2, 8'h53);
    check_byte(3, 8'h54);


    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-3 PASS");
    else
        $display("TC-M3D-COMMIT-3 FAIL");


    // ========================================================
    // TC4
    //
    // Decision arrives on the same cycle as final payload byte.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;


    send_byte(8'h61, 1'b1, 1'b0);
    send_byte(8'h62, 1'b0, 1'b0);


    // Manually drive EOF + decision together.

    @(negedge clk);

    in_data  = 8'h63;
    in_valid = 1'b1;
    in_sof   = 1'b0;
    in_eof   = 1'b1;

    decision_valid  = 1'b1;
    decision_accept = 1'b1;


    @(negedge clk);

    in_valid = 1'b0;
    in_eof   = 1'b0;

    decision_valid  = 1'b0;
    decision_accept = 1'b0;


    wait_idle;


    if (output_count != 3) begin

        $display(
            "TC4 ERROR: output_count=%0d expected=3",
            output_count
        );

        error_count = error_count + 1;

    end


    check_byte(0, 8'h61);
    check_byte(1, 8'h62);
    check_byte(2, 8'h63);


    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-4 PASS");
    else
        $display("TC-M3D-COMMIT-4 FAIL");


    // ========================================================
    // TC5
    //
    // Early REJECT decision while frame is still arriving.
    //
    // The remaining bytes are still consumed so upstream frame
    // framing remains clean, but nothing is committed.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;


    send_byte(8'h71, 1'b1, 1'b0);


    send_decision(1'b0);


    send_byte(8'h72, 1'b0, 1'b0);
    send_byte(8'h73, 1'b0, 1'b1);


    repeat (5)
        @(posedge clk);


    if (output_count != 0) begin

        $display(
            "TC5 ERROR: early rejected frame leaked payload"
        );

        error_count = error_count + 1;

    end

    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-5 PASS");
    else
        $display("TC-M3D-COMMIT-5 FAIL");


    // ========================================================
    // TC6
    //
    // Application backpressure.
    //
    // Replay must stop without changing data.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;


    send_byte(8'h81, 1'b1, 1'b0);
    send_byte(8'h82, 1'b0, 1'b0);
    send_byte(8'h83, 1'b0, 1'b0);
    send_byte(8'h84, 1'b0, 1'b1);


    send_decision(1'b1);


    // Let exactly one byte transfer.
    //
    // output_count is updated by NBA on posedge clk.
    // Therefore sample it on negedge clk to avoid waiting
    // one extra transfer cycle.

    while (output_count < 1)
        @(negedge clk);

    out_ready = 1'b0;


    repeat (8)
        @(posedge clk);


    if (output_count != 1) begin

        $display(
            "TC6 ERROR: output advanced during backpressure"
        );

        error_count = error_count + 1;

    end


    @(negedge clk);

    out_ready = 1'b1;


    wait_idle;


    if (output_count != 4) begin

        $display(
            "TC6 ERROR: output_count=%0d expected=4",
            output_count
        );

        error_count = error_count + 1;

    end


    check_byte(0, 8'h81);
    check_byte(1, 8'h82);
    check_byte(2, 8'h83);
    check_byte(3, 8'h84);


    if (!cap_sof[0]) begin

        $display(
            "TC6 ERROR: SOF incorrect"
        );

        error_count = error_count + 1;

    end


    if (!cap_eof[3]) begin

        $display(
            "TC6 ERROR: EOF incorrect"
        );

        error_count = error_count + 1;

    end


    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-6 PASS");
    else
        $display("TC-M3D-COMMIT-6 FAIL");


    // ========================================================
    // TC7
    //
    // Verify buffer is reusable after completed replay.
    // ========================================================

    case_error_start = error_count;

    clear_scoreboard;


    send_byte(8'hA1, 1'b1, 1'b0);
    send_byte(8'hA2, 1'b0, 1'b1);


    send_decision(1'b1);

    wait_idle;


    if (output_count != 2) begin

        $display(
            "TC7 ERROR: output_count=%0d expected=2",
            output_count
        );

        error_count = error_count + 1;

    end


    check_byte(0, 8'hA1);
    check_byte(1, 8'hA2);


    if (!cap_sof[0]) begin

        $display(
            "TC7 ERROR: SOF missing"
        );

        error_count = error_count + 1;

    end


    if (!cap_eof[1]) begin

        $display(
            "TC7 ERROR: EOF missing"
        );

        error_count = error_count + 1;

    end


    if (error_count == case_error_start)
        $display("TC-M3D-COMMIT-7 PASS");
    else
        $display("TC-M3D-COMMIT-7 FAIL");


    // ========================================================
    // Final result
    // ========================================================

    $display("");
    $display(
        "=============================================="
    );


    if (error_count == 0) begin

        $display(
            "M3-D PAYLOAD COMMIT BUFFER STANDALONE PASS"
        );

        $display(
            "FRAME CAPTURE VERIFIED"
        );

        $display(
            "ACCEPT REPLAY VERIFIED"
        );

        $display(
            "REJECT DISCARD VERIFIED"
        );

        $display(
            "DELAYED DECISION VERIFIED"
        );

        $display(
            "EOF/DECISION SAME-CYCLE VERIFIED"
        );

        $display(
            "EARLY REJECT VERIFIED"
        );

        $display(
            "APPLICATION BACKPRESSURE VERIFIED"
        );

        $display(
            "BUFFER REUSE VERIFIED"
        );

    end
    else begin

        $fatal(
            1,
            "M3-D PAYLOAD COMMIT BUFFER FAIL: %0d errors",
            error_count
        );

    end


    $display(
        "=============================================="
    );

    $display("");


    #100;

    $finish;

end


// ============================================================
// Global watchdog
// ============================================================

initial begin

    #100000;

    $fatal(
        1,
        "M3-D PAYLOAD COMMIT BUFFER GLOBAL TIMEOUT"
    );

end


endmodule
