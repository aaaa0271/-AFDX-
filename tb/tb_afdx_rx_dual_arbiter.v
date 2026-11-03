`timescale 1ns / 1ps

module tb_afdx_rx_dual_arbiter;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;


initial begin

    clk = 1'b0;

    forever #5
        clk = ~clk;

end


// ============================================================
// DUT signals
// ============================================================

// ---------------- A ----------------

reg         a_valid;
wire        a_ready;

reg  [1:0]  a_vl_index;
reg  [15:0] a_vl_id;
reg  [10:0] a_payload_length;
reg  [7:0]  a_sequence;


// ---------------- B ----------------

reg         b_valid;
wire        b_ready;

reg  [1:0]  b_vl_index;
reg  [15:0] b_vl_id;
reg  [10:0] b_payload_length;
reg  [7:0]  b_sequence;


// ---------------- Output ----------------

wire        out_valid;
reg         out_ready;

wire        out_network;

wire [1:0]  out_vl_index;
wire [15:0] out_vl_id;
wire [10:0] out_payload_length;
wire [7:0]  out_sequence;


// ============================================================
// DUT
// ============================================================

afdx_rx_dual_arbiter dut (

    .clk (
        clk
    ),

    .rst (
        rst
    ),


    // A

    .a_valid (
        a_valid
    ),

    .a_ready (
        a_ready
    ),

    .a_vl_index (
        a_vl_index
    ),

    .a_vl_id (
        a_vl_id
    ),

    .a_payload_length (
        a_payload_length
    ),

    .a_sequence (
        a_sequence
    ),


    // B

    .b_valid (
        b_valid
    ),

    .b_ready (
        b_ready
    ),

    .b_vl_index (
        b_vl_index
    ),

    .b_vl_id (
        b_vl_id
    ),

    .b_payload_length (
        b_payload_length
    ),

    .b_sequence (
        b_sequence
    ),


    // Output

    .out_valid (
        out_valid
    ),

    .out_ready (
        out_ready
    ),

    .out_network (
        out_network
    ),

    .out_vl_index (
        out_vl_index
    ),

    .out_vl_id (
        out_vl_id
    ),

    .out_payload_length (
        out_payload_length
    ),

    .out_sequence (
        out_sequence
    )

);


// ============================================================
// Scoreboard
// ============================================================

integer error_count;
integer transfer_count;


reg        cap_network  [0:63];
reg [1:0]  cap_vl_index [0:63];
reg [15:0] cap_vl_id    [0:63];
reg [10:0] cap_length   [0:63];
reg [7:0]  cap_sequence [0:63];


// Capture every real output handshake.

always @(posedge clk) begin

    if (rst) begin

        transfer_count = 0;

    end
    else if (
        out_valid
        &&
        out_ready
    ) begin

        cap_network[transfer_count] =
            out_network;

        cap_vl_index[transfer_count] =
            out_vl_index;

        cap_vl_id[transfer_count] =
            out_vl_id;

        cap_length[transfer_count] =
            out_payload_length;

        cap_sequence[transfer_count] =
            out_sequence;

        transfer_count =
            transfer_count + 1;

    end

end


// ============================================================
// Utility task: clear input
// ============================================================

task clear_inputs;

    begin

        a_valid = 1'b0;

        a_vl_index =
            2'd0;

        a_vl_id =
            16'd0;

        a_payload_length =
            11'd0;

        a_sequence =
            8'd0;


        b_valid = 1'b0;

        b_vl_index =
            2'd0;

        b_vl_id =
            16'd0;

        b_payload_length =
            11'd0;

        b_sequence =
            8'd0;

    end

endtask


// ============================================================
// Utility: wait transfer count
// ============================================================

task wait_transfer_count;

    input integer expected;

    integer timeout;

    begin

        timeout = 0;

        while (
            (transfer_count < expected)
            &&
            (timeout < 100)
        ) begin

            @(posedge clk);

            timeout =
                timeout + 1;

        end


        if (timeout >= 100) begin

            $display(
                "ERROR: transfer timeout, got=%0d expected=%0d",
                transfer_count,
                expected
            );

            error_count =
                error_count + 1;

        end

    end

endtask


// ============================================================
// Utility: verify captured transfer
// ============================================================

task expect_transfer;

    input integer index;

    input        expected_network;

    input [1:0]  expected_vl_index;

    input [15:0] expected_vl_id;

    input [10:0] expected_length;

    input [7:0]  expected_sequence;

    begin

        if (
            cap_network[index]
            !==
            expected_network
        ) begin

            $display(
                "ERROR transfer[%0d]: network=%0d expected=%0d",
                index,
                cap_network[index],
                expected_network
            );

            error_count =
                error_count + 1;

        end


        if (
            cap_vl_index[index]
            !==
            expected_vl_index
        ) begin

            $display(
                "ERROR transfer[%0d]: vl_index=%0d expected=%0d",
                index,
                cap_vl_index[index],
                expected_vl_index
            );

            error_count =
                error_count + 1;

        end


        if (
            cap_vl_id[index]
            !==
            expected_vl_id
        ) begin

            $display(
                "ERROR transfer[%0d]: vl_id=%04x expected=%04x",
                index,
                cap_vl_id[index],
                expected_vl_id
            );

            error_count =
                error_count + 1;

        end


        if (
            cap_length[index]
            !==
            expected_length
        ) begin

            $display(
                "ERROR transfer[%0d]: length=%0d expected=%0d",
                index,
                cap_length[index],
                expected_length
            );

            error_count =
                error_count + 1;

        end


        if (
            cap_sequence[index]
            !==
            expected_sequence
        ) begin

            $display(
                "ERROR transfer[%0d]: sequence=%02x expected=%02x",
                index,
                cap_sequence[index],
                expected_sequence
            );

            error_count =
                error_count + 1;

        end

    end

endtask


// ============================================================
// Main test
// ============================================================

integer start_error;
integer base_transfer;


reg        held_network;
reg [1:0]  held_vl_index;
reg [15:0] held_vl_id;
reg [10:0] held_length;
reg [7:0]  held_sequence;


initial begin

    error_count =
        0;


    clear_inputs;


    out_ready =
        1'b0;


    rst =
        1'b1;


    repeat (5)
        @(posedge clk);


    @(negedge clk);

    rst =
        1'b0;


    repeat (2)
        @(posedge clk);


    $display("");

    $display(
        "=============================================="
    );

    $display(
        "M5-D2b DUAL PARSED-FRAME ARBITER TEST"
    );

    $display(
        "=============================================="
    );

    $display("");


    // ========================================================
    // TC-M5-D2b-01
    // Reset / idle
    // ========================================================

    start_error =
        error_count;


    if (
        out_valid
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2b-01 ERROR: out_valid after reset"
        );

        error_count =
            error_count + 1;

    end


    if (
        a_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2b-01 ERROR: a_ready while invalid"
        );

        error_count =
            error_count + 1;

    end


    if (
        b_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2b-01 ERROR: b_ready while invalid"
        );

        error_count =
            error_count + 1;

    end


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-01 PASS: reset / idle"
        );
    else
        $display(
            "TC-M5-D2b-01 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-02
    // A only
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    out_ready =
        1'b1;


    @(negedge clk);

    a_valid =
        1'b1;

    a_vl_index =
        2'd0;

    a_vl_id =
        16'h0002;

    a_payload_length =
        11'd100;

    a_sequence =
        8'h10;


    // A should immediately become selected.

    #1;

    if (
        a_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-02 ERROR: a_ready not asserted"
        );

        error_count =
            error_count + 1;

    end


    if (
        b_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2b-02 ERROR: b_ready unexpectedly asserted"
        );

        error_count =
            error_count + 1;

    end


    // Handshake at next posedge.

    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 1
    );


    expect_transfer(
        base_transfer,
        1'b0,
        2'd0,
        16'h0002,
        11'd100,
        8'h10
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-02 PASS: A-only candidate"
        );
    else
        $display(
            "TC-M5-D2b-02 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-03
    // B only
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    @(negedge clk);

    b_valid =
        1'b1;

    b_vl_index =
        2'd1;

    b_vl_id =
        16'h0003;

    b_payload_length =
        11'd200;

    b_sequence =
        8'h20;


    #1;


    if (
        b_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-03 ERROR: b_ready not asserted"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 1
    );


    expect_transfer(
        base_transfer,
        1'b1,
        2'd1,
        16'h0003,
        11'd200,
        8'h20
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-03 PASS: B-only candidate"
        );
    else
        $display(
            "TC-M5-D2b-03 FAIL"
        );


    // ========================================================
    // Reset round-robin state.
    //
    // First simultaneous tie must grant A.
    // ========================================================

    @(negedge clk);

    rst =
        1'b1;


    repeat (2)
        @(posedge clk);


    @(negedge clk);

    rst =
        1'b0;


    repeat (2)
        @(posedge clk);


    // ========================================================
    // TC-M5-D2b-04
    //
    // A+B simultaneous.
    //
    // First tie:
    //   A ready = 1
    //   B ready = 0
    //
    // After A handshake:
    //   B remains valid
    //   B is transferred next.
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    @(negedge clk);


    // A

    a_valid =
        1'b1;

    a_vl_index =
        2'd0;

    a_vl_id =
        16'h00A0;

    a_payload_length =
        11'd111;

    a_sequence =
        8'h31;


    // B

    b_valid =
        1'b1;

    b_vl_index =
        2'd1;

    b_vl_id =
        16'h00B0;

    b_payload_length =
        11'd222;

    b_sequence =
        8'h32;


    #1;


    // First tie must grant A only.

    if (
        !(
            a_ready
            &&
            !b_ready
        )
    ) begin

        $display(
            "TC-M5-D2b-04 ERROR: first tie did not select A only"
        );

        $display(
            "  a_ready=%0d b_ready=%0d",
            a_ready,
            b_ready
        );

        error_count =
            error_count + 1;

    end


    // A handshake.

    @(posedge clk);

    #1;


    // Parser A would now remove its valid.

    @(negedge clk);

    a_valid =
        1'b0;


    #1;


    // B must still be present and selected.

    if (
        !(
            b_valid
            &&
            b_ready
        )
    ) begin

        $display(
            "TC-M5-D2b-04 ERROR: B lost after A grant"
        );

        error_count =
            error_count + 1;

    end


    // B handshake.

    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 2
    );


    expect_transfer(
        base_transfer,
        1'b0,
        2'd0,
        16'h00A0,
        11'd111,
        8'h31
    );


    expect_transfer(
        base_transfer + 1,
        1'b1,
        2'd1,
        16'h00B0,
        11'd222,
        8'h32
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-04 PASS: simultaneous A/B consumes one at a time"
        );
    else
        $display(
            "TC-M5-D2b-04 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-05
    // Round-robin tie reversal.
    //
    // Make A the last successful winner.
    // Then simultaneous A+B must choose B.
    // ========================================================

    start_error =
        error_count;


    // First transfer an A-only candidate.

    @(negedge clk);

    a_valid =
        1'b1;

    a_vl_index =
        2'd2;

    a_vl_id =
        16'h0A01;

    a_payload_length =
        11'd300;

    a_sequence =
        8'h40;


    #1;


    if (
        a_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-05 ERROR: setup A not ready"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    repeat (1)
        @(posedge clk);


    base_transfer =
        transfer_count;


    // Now A and B arrive together.

    @(negedge clk);


    a_valid =
        1'b1;

    a_vl_index =
        2'd2;

    a_vl_id =
        16'h0A02;

    a_payload_length =
        11'd301;

    a_sequence =
        8'h41;


    b_valid =
        1'b1;

    b_vl_index =
        2'd3;

    b_vl_id =
        16'h0B02;

    b_payload_length =
        11'd401;

    b_sequence =
        8'h42;


    #1;


    // Previous winner was A.
    // Therefore B must win this tie.

    if (
        !(
            !a_ready
            &&
            b_ready
        )
    ) begin

        $display(
            "TC-M5-D2b-05 ERROR: tie after A must choose B"
        );

        $display(
            "  a_ready=%0d b_ready=%0d",
            a_ready,
            b_ready
        );

        error_count =
            error_count + 1;

    end


    // B handshake.

    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    // A remains pending and transfers next.

    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 2
    );


    expect_transfer(
        base_transfer,
        1'b1,
        2'd3,
        16'h0B02,
        11'd401,
        8'h42
    );


    expect_transfer(
        base_transfer + 1,
        1'b0,
        2'd2,
        16'h0A02,
        11'd301,
        8'h41
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-05 PASS: round-robin tie reversal"
        );
    else
        $display(
            "TC-M5-D2b-05 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-06
    // Output backpressure.
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    out_ready =
        1'b0;


    @(negedge clk);


    a_valid =
        1'b1;

    a_vl_index =
        2'd1;

    a_vl_id =
        16'hA600;

    a_payload_length =
        11'd606;

    a_sequence =
        8'h61;


    b_valid =
        1'b0;


    #1;


    if (
        a_ready
        ||
        b_ready
    ) begin

        $display(
            "TC-M5-D2b-06 ERROR: input ready while output stalled"
        );

        error_count =
            error_count + 1;

    end


    if (
        out_valid
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-06 ERROR: out_valid missing during stall"
        );

        error_count =
            error_count + 1;

    end


    held_network =
        out_network;

    held_vl_index =
        out_vl_index;

    held_vl_id =
        out_vl_id;

    held_length =
        out_payload_length;

    held_sequence =
        out_sequence;


    repeat (8) begin

        @(posedge clk);

        #1;


        if (
            transfer_count
            !=
            base_transfer
        ) begin

            $display(
                "TC-M5-D2b-06 ERROR: transfer occurred while stalled"
            );

            error_count =
                error_count + 1;

        end


        if (
            (out_valid !== 1'b1)
            ||
            (out_network !== held_network)
            ||
            (out_vl_index !== held_vl_index)
            ||
            (out_vl_id !== held_vl_id)
            ||
            (out_payload_length !== held_length)
            ||
            (out_sequence !== held_sequence)
        ) begin

            $display(
                "TC-M5-D2b-06 ERROR: metadata changed during stall"
            );

            error_count =
                error_count + 1;

        end

    end


    // Release downstream.

    @(negedge clk);

    out_ready =
        1'b1;


    #1;


    if (
        a_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-06 ERROR: A not released"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 1
    );


    expect_transfer(
        base_transfer,
        1'b0,
        2'd1,
        16'hA600,
        11'd606,
        8'h61
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-06 PASS: output backpressure holds candidate"
        );
    else
        $display(
            "TC-M5-D2b-06 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-07
    //
    // A is pending while stalled.
    // B then arrives.
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    out_ready =
        1'b0;


    @(negedge clk);


    a_valid =
        1'b1;

    a_vl_index =
        2'd0;

    a_vl_id =
        16'hA700;

    a_payload_length =
        11'd700;

    a_sequence =
        8'h71;


    repeat (3)
        @(posedge clk);


    @(negedge clk);


    b_valid =
        1'b1;

    b_vl_index =
        2'd1;

    b_vl_id =
        16'hB700;

    b_payload_length =
        11'd701;

    b_sequence =
        8'h72;


    #1;


    if (
        a_ready
        ||
        b_ready
    ) begin

        $display(
            "TC-M5-D2b-07 ERROR: source consumed while stalled"
        );

        error_count =
            error_count + 1;

    end


    // Previous successful winner in TC-06 was A.
    // Therefore after release, A+B tie should choose B.

    @(negedge clk);

    out_ready =
        1'b1;


    #1;


    if (
        !(
            !a_ready
            &&
            b_ready
        )
    ) begin

        $display(
            "TC-M5-D2b-07 ERROR: expected B first"
        );

        error_count =
            error_count + 1;

    end


    // B handshake.

    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    // A next.

    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 2
    );


    expect_transfer(
        base_transfer,
        1'b1,
        2'd1,
        16'hB700,
        11'd701,
        8'h72
    );


    expect_transfer(
        base_transfer + 1,
        1'b0,
        2'd0,
        16'hA700,
        11'd700,
        8'h71
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-07 PASS: pending A + arriving B preserved"
        );
    else
        $display(
            "TC-M5-D2b-07 FAIL"
        );


    // ========================================================
    // TC-M5-D2b-08
    //
    // Metadata / sequence transparent pass-through.
    // ========================================================

    start_error =
        error_count;

    base_transfer =
        transfer_count;


    // A with sequence FF.

    @(negedge clk);


    a_valid =
        1'b1;

    a_vl_index =
        2'd3;

    a_vl_id =
        16'hCAFE;

    a_payload_length =
        11'd1234;

    a_sequence =
        8'hFF;


    #1;


    if (
        a_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-08 ERROR: A not ready"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 1
    );


    expect_transfer(
        base_transfer,
        1'b0,
        2'd3,
        16'hCAFE,
        11'd1234,
        8'hFF
    );


    // B with sequence 00.

    @(negedge clk);


    b_valid =
        1'b1;

    b_vl_index =
        2'd0;

    b_vl_id =
        16'hBEEF;

    b_payload_length =
        11'd17;

    b_sequence =
        8'h00;


    #1;


    if (
        b_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2b-08 ERROR: B not ready"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    wait_transfer_count(
        base_transfer + 2
    );


    expect_transfer(
        base_transfer + 1,
        1'b1,
        2'd0,
        16'hBEEF,
        11'd17,
        8'h00
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2b-08 PASS: metadata/sequence pass-through"
        );
    else
        $display(
            "TC-M5-D2b-08 FAIL"
        );


    // ========================================================
    // Final result
    // ========================================================

    $display("");

    $display(
        "=============================================="
    );


    if (
        error_count
        ==
        0
    ) begin

        $display(
            "M5-D2b ALL TESTS PASS"
        );

    end
    else begin

        $display(
            "M5-D2b FAILED: %0d error(s)",
            error_count
        );

        $fatal(
            1,
            "M5-D2b regression failed"
        );

    end


    $display(
        "=============================================="
    );

    $display("");


    #50;

    $finish;

end


// ============================================================
// Global watchdog
// ============================================================

initial begin

    #200000;

    $fatal(
        1,
        "M5-D2b GLOBAL TIMEOUT"
    );

end


endmodule
