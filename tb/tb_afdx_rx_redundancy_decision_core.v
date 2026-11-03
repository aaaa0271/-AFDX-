`timescale 1ns / 1ps

module tb_afdx_rx_redundancy_decision_core;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;
reg clear;


initial begin

    clk = 1'b0;

    forever #5
        clk = ~clk;

end


// ============================================================
// A candidate
// ============================================================

reg         a_candidate_valid;
wire        a_candidate_ready;

reg [1:0]   a_candidate_vl_index;
reg [15:0]  a_candidate_vl_id;
reg [10:0]  a_candidate_payload_length;
reg [7:0]   a_candidate_sequence;


// ============================================================
// B candidate
// ============================================================

reg         b_candidate_valid;
wire        b_candidate_ready;

reg [1:0]   b_candidate_vl_index;
reg [15:0]  b_candidate_vl_id;
reg [10:0]  b_candidate_payload_length;
reg [7:0]   b_candidate_sequence;


// ============================================================
// Decisions
// ============================================================

wire a_decision_valid;
wire a_decision_accept;

wire b_decision_valid;
wire b_decision_accept;


// ============================================================
// Events
// ============================================================

wire accept_event;
wire duplicate_event;
wire stale_event;
wire gap_event;


// ============================================================
// Statistics
// ============================================================

wire [31:0] accepted_count;

wire [31:0] accepted_a_count;
wire [31:0] accepted_b_count;

wire [31:0] duplicate_count;

wire [31:0] cross_network_duplicate_count;
wire [31:0] same_network_repeat_count;

wire [31:0] stale_count;
wire [31:0] sequence_gap_count;


// ============================================================
// Debug
// ============================================================

wire       arb_valid;
wire       arb_ready;
wire       arb_network;
wire [1:0] arb_vl_index;
wire [7:0] arb_sequence;

wire decision_pending_network;


// ============================================================
// DUT
// ============================================================

afdx_rx_redundancy_decision_core dut (

    .clk (
        clk
    ),

    .rst (
        rst
    ),

    .clear (
        clear
    ),


    .a_candidate_valid (
        a_candidate_valid
    ),

    .a_candidate_ready (
        a_candidate_ready
    ),

    .a_candidate_vl_index (
        a_candidate_vl_index
    ),

    .a_candidate_vl_id (
        a_candidate_vl_id
    ),

    .a_candidate_payload_length (
        a_candidate_payload_length
    ),

    .a_candidate_sequence (
        a_candidate_sequence
    ),


    .b_candidate_valid (
        b_candidate_valid
    ),

    .b_candidate_ready (
        b_candidate_ready
    ),

    .b_candidate_vl_index (
        b_candidate_vl_index
    ),

    .b_candidate_vl_id (
        b_candidate_vl_id
    ),

    .b_candidate_payload_length (
        b_candidate_payload_length
    ),

    .b_candidate_sequence (
        b_candidate_sequence
    ),


    .a_decision_valid (
        a_decision_valid
    ),

    .a_decision_accept (
        a_decision_accept
    ),

    .b_decision_valid (
        b_decision_valid
    ),

    .b_decision_accept (
        b_decision_accept
    ),


    .accept_event (
        accept_event
    ),

    .duplicate_event (
        duplicate_event
    ),

    .stale_event (
        stale_event
    ),

    .gap_event (
        gap_event
    ),


    .accepted_count (
        accepted_count
    ),

    .accepted_a_count (
        accepted_a_count
    ),

    .accepted_b_count (
        accepted_b_count
    ),

    .duplicate_count (
        duplicate_count
    ),

    .cross_network_duplicate_count (
        cross_network_duplicate_count
    ),

    .same_network_repeat_count (
        same_network_repeat_count
    ),

    .stale_count (
        stale_count
    ),

    .sequence_gap_count (
        sequence_gap_count
    ),


    .arb_valid (
        arb_valid
    ),

    .arb_ready (
        arb_ready
    ),

    .arb_network (
        arb_network
    ),

    .arb_vl_index (
        arb_vl_index
    ),

    .arb_sequence (
        arb_sequence
    ),

    .decision_pending_network (
        decision_pending_network
    )

);


// ============================================================
// Test state
// ============================================================

integer error_count;
integer start_error;


// ============================================================
// Clear all candidate inputs
// ============================================================

task clear_candidates;

    begin

        a_candidate_valid =
            1'b0;

        a_candidate_vl_index =
            2'd0;

        a_candidate_vl_id =
            16'd0;

        a_candidate_payload_length =
            11'd0;

        a_candidate_sequence =
            8'd0;


        b_candidate_valid =
            1'b0;

        b_candidate_vl_index =
            2'd0;

        b_candidate_vl_id =
            16'd0;

        b_candidate_payload_length =
            11'd0;

        b_candidate_sequence =
            8'd0;

    end

endtask


// ============================================================
// Pulse clear
// ============================================================

task pulse_clear;

    begin

        @(negedge clk);

        clear =
            1'b1;


        @(posedge clk);

        #1;


        @(negedge clk);

        clear =
            1'b0;


        repeat (2)
            @(posedge clk);

    end

endtask


// ============================================================
// Send one A candidate
// ============================================================

task send_a;

    input [1:0] vl;
    input [7:0] seq;

    begin

        @(negedge clk);


        a_candidate_vl_index =
            vl;

        a_candidate_vl_id =
            16'h0002 + vl;

        a_candidate_payload_length =
            11'd4;

        a_candidate_sequence =
            seq;

        a_candidate_valid =
            1'b1;


        #1;


        while (
            a_candidate_ready
            !==
            1'b1
        )
            @(posedge clk);


        @(posedge clk);

        #1;


        @(negedge clk);

        a_candidate_valid =
            1'b0;

    end

endtask


// ============================================================
// Send one B candidate
// ============================================================

task send_b;

    input [1:0] vl;
    input [7:0] seq;

    begin

        @(negedge clk);


        b_candidate_vl_index =
            vl;

        b_candidate_vl_id =
            16'h0002 + vl;

        b_candidate_payload_length =
            11'd4;

        b_candidate_sequence =
            seq;

        b_candidate_valid =
            1'b1;


        #1;


        while (
            b_candidate_ready
            !==
            1'b1
        )
            @(posedge clk);


        @(posedge clk);

        #1;


        @(negedge clk);

        b_candidate_valid =
            1'b0;

    end

endtask


// ============================================================
// Expect A decision
// ============================================================

task expect_a_decision;

    input expected_accept;

    integer timeout;

    begin

        timeout =
            0;


        while (
            (a_decision_valid !== 1'b1)
            &&
            (timeout < 20)
        ) begin

            @(posedge clk);

            #1;

            timeout =
                timeout + 1;

        end


        if (
            timeout >= 20
        ) begin

            $display(
                "ERROR: timeout waiting A decision"
            );

            error_count =
                error_count + 1;

        end
        else begin

            if (
                a_decision_accept
                !==
                expected_accept
            ) begin

                $display(
                    "ERROR: A decision accept=%0d expected=%0d",
                    a_decision_accept,
                    expected_accept
                );

                error_count =
                    error_count + 1;

            end


            if (
                b_decision_valid
                !==
                1'b0
            ) begin

                $display(
                    "ERROR: A decision leaked to B"
                );

                error_count =
                    error_count + 1;

            end


            // Let the one-cycle decision pulse expire before
            // returning, so the next TC does not read a stale
            // pulse from this transaction.

            @(posedge clk);
            #1;

        end

    end

endtask


// ============================================================
// Expect B decision
// ============================================================

task expect_b_decision;

    input expected_accept;

    integer timeout;

    begin

        timeout =
            0;


        while (
            (b_decision_valid !== 1'b1)
            &&
            (timeout < 20)
        ) begin

            @(posedge clk);

            #1;

            timeout =
                timeout + 1;

        end


        if (
            timeout >= 20
        ) begin

            $display(
                "ERROR: timeout waiting B decision"
            );

            error_count =
                error_count + 1;

        end
        else begin

            if (
                b_decision_accept
                !==
                expected_accept
            ) begin

                $display(
                    "ERROR: B decision accept=%0d expected=%0d",
                    b_decision_accept,
                    expected_accept
                );

                error_count =
                    error_count + 1;

            end


            if (
                a_decision_valid
                !==
                1'b0
            ) begin

                $display(
                    "ERROR: B decision leaked to A"
                );

                error_count =
                    error_count + 1;

            end


            // Let the one-cycle decision pulse expire before
            // returning, so the next TC does not read a stale
            // pulse from this transaction.

            @(posedge clk);
            #1;

        end

    end

endtask


// ============================================================
// Main
// ============================================================

initial begin

    error_count =
        0;


    clear_candidates;


    clear =
        1'b0;

    rst =
        1'b1;


    repeat (5)
        @(posedge clk);


    @(negedge clk);

    rst =
        1'b0;


    repeat (3)
        @(posedge clk);


    $display("");

    $display(
        "=============================================="
    );

    $display(
        "M5-D2c1 REDUNDANCY DECISION CORE TEST"
    );

    $display(
        "=============================================="
    );

    $display("");


    // ========================================================
    // TC-01
    // Reset
    // ========================================================

    start_error =
        error_count;


    if (
        accepted_count
        !==
        32'd0
    ) begin

        $display(
            "TC-M5-D2c1-01 ERROR: accepted_count not zero"
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
            "TC-M5-D2c1-01 PASS: reset / idle"
        );
    else
        $display(
            "TC-M5-D2c1-01 FAIL"
        );


    // ========================================================
    // TC-02
    // First A copy accepted.
    // ========================================================

    start_error =
        error_count;


    fork

        send_a(
            2'd0,
            8'h10
        );

        expect_a_decision(
            1'b1
        );

    join


    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-02 ERROR: accepted_count=%0d",
            accepted_count
        );

        error_count =
            error_count + 1;

    end


    if (
        accepted_a_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-02 ERROR: accepted_a_count=%0d",
            accepted_a_count
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
            "TC-M5-D2c1-02 PASS: A first copy accepted and routed to A"
        );
    else
        $display(
            "TC-M5-D2c1-02 FAIL"
        );


    // ========================================================
    // TC-03
    // Same sequence from B = cross-network duplicate.
    // Must reject B only.
    // ========================================================

    start_error =
        error_count;


    fork

        send_b(
            2'd0,
            8'h10
        );

        expect_b_decision(
            1'b0
        );

    join


    if (
        cross_network_duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-03 ERROR: cross dup count=%0d",
            cross_network_duplicate_count
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
            "TC-M5-D2c1-03 PASS: B cross-network duplicate rejected to B"
        );
    else
        $display(
            "TC-M5-D2c1-03 FAIL"
        );


    // ========================================================
    // TC-04
    // Same sequence B again = same-network repeat.
    // ========================================================

    start_error =
        error_count;


    fork

        send_b(
            2'd0,
            8'h10
        );

        expect_b_decision(
            1'b0
        );

    join


    if (
        same_network_repeat_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-04 ERROR: same repeat count=%0d",
            same_network_repeat_count
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
            "TC-M5-D2c1-04 PASS: B same-network repeat rejected to B"
        );
    else
        $display(
            "TC-M5-D2c1-04 FAIL"
        );


    // ========================================================
    // TC-05
    // New B sequence accepted.
    // ========================================================

    start_error =
        error_count;


    fork

        send_b(
            2'd0,
            8'h11
        );

        expect_b_decision(
            1'b1
        );

    join


    if (
        accepted_b_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-05 ERROR: accepted_b_count=%0d",
            accepted_b_count
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
            "TC-M5-D2c1-05 PASS: newer B copy accepted and routed to B"
        );
    else
        $display(
            "TC-M5-D2c1-05 FAIL"
        );


    // ========================================================
    // TC-06
    // Old A sequence = stale.
    // ========================================================

    start_error =
        error_count;


    fork

        send_a(
            2'd0,
            8'h10
        );

        expect_a_decision(
            1'b0
        );

    join


    if (
        stale_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-06 ERROR: stale_count=%0d",
            stale_count
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
            "TC-M5-D2c1-06 PASS: stale A copy rejected to A"
        );
    else
        $display(
            "TC-M5-D2c1-06 FAIL"
        );


    // ========================================================
    // TC-07
    // Wrap 255 -> 1.
    // ========================================================

    start_error =
        error_count;


    pulse_clear;


    fork

        send_a(
            2'd1,
            8'hFF
        );

        expect_a_decision(
            1'b1
        );

    join


    fork

        send_b(
            2'd1,
            8'h01
        );

        expect_b_decision(
            1'b1
        );

    join


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "TC-M5-D2c1-07 ERROR: wrap accepted_count=%0d expected=2",
            accepted_count
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
            "TC-M5-D2c1-07 PASS: 255->0 wrap accepted with correct ownership"
        );
    else
        $display(
            "TC-M5-D2c1-07 FAIL"
        );


    // ========================================================
    // TC-08
    // Simultaneous A/B same sequence.
    //
    // D2b first tie after clear is not necessarily reset,
    // so reset the whole DUT here to make first tie A.
    //
    // Expected:
    //   A accepted
    //   B cross-network duplicate
    //
    // Most important:
    //   first decision goes only to A
    //   second decision goes only to B
    // ========================================================

    start_error =
        error_count;


    @(negedge clk);

    rst =
        1'b1;


    clear_candidates;


    repeat (3)
        @(posedge clk);


    @(negedge clk);

    rst =
        1'b0;


    repeat (3)
        @(posedge clk);


    @(negedge clk);


    a_candidate_valid =
        1'b1;

    a_candidate_vl_index =
        2'd2;

    a_candidate_vl_id =
        16'h1002;

    a_candidate_payload_length =
        11'd4;

    a_candidate_sequence =
        8'h55;


    b_candidate_valid =
        1'b1;

    b_candidate_vl_index =
        2'd2;

    b_candidate_vl_id =
        16'h1002;

    b_candidate_payload_length =
        11'd4;

    b_candidate_sequence =
        8'h55;


    // First tie must select A.

    #1;


    if (
        !(
            a_candidate_ready
            &&
            !b_candidate_ready
        )
    ) begin

        $display(
            "TC-M5-D2c1-08 ERROR: first tie did not select A"
        );

        error_count =
            error_count + 1;

    end


    // A handshake.

    @(posedge clk);

    #1;


    @(negedge clk);

    a_candidate_valid =
        1'b0;


    // Wait for A accept decision.

    begin : wait_a_accept

        integer timeout_a;

        timeout_a =
            0;


        while (
            (a_decision_valid !== 1'b1)
            &&
            (timeout_a < 20)
        ) begin

            @(posedge clk);

            #1;

            timeout_a =
                timeout_a + 1;

        end


        if (
            timeout_a >= 20
        ) begin

            $display(
                "TC-M5-D2c1-08 ERROR: timeout A decision"
            );

            error_count =
                error_count + 1;

        end
        else begin

            if (
                a_decision_accept
                !==
                1'b1
            ) begin

                $display(
                    "TC-M5-D2c1-08 ERROR: A should accept"
                );

                error_count =
                    error_count + 1;

            end


            if (
                b_decision_valid
                !==
                1'b0
            ) begin

                $display(
                    "TC-M5-D2c1-08 ERROR: A decision leaked to B"
                );

                error_count =
                    error_count + 1;

            end

        end

    end


    // B must still be pending and eventually handshake.

    while (
        b_candidate_ready
        !==
        1'b1
    )
        @(posedge clk);


    @(posedge clk);

    #1;


    @(negedge clk);

    b_candidate_valid =
        1'b0;


    // B must receive reject.

    expect_b_decision(
        1'b0
    );


    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-08 ERROR: accepted_count=%0d expected=1",
            accepted_count
        );

        error_count =
            error_count + 1;

    end


    if (
        cross_network_duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "TC-M5-D2c1-08 ERROR: cross dup=%0d expected=1",
            cross_network_duplicate_count
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
            "TC-M5-D2c1-08 PASS: simultaneous A/B ownership routing"
        );
    else
        $display(
            "TC-M5-D2c1-08 FAIL"
        );


    // ========================================================
    // Final
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
            "M5-D2c1 ALL TESTS PASS"
        );

    end
    else begin

        $display(
            "M5-D2c1 FAILED: %0d error(s)",
            error_count
        );

        $fatal(
            1,
            "M5-D2c1 regression failed"
        );

    end


    $display(
        "=============================================="
    );


    #50;

    $finish;

end


// ============================================================
// Watchdog
// ============================================================

initial begin

    #200000;

    $fatal(
        1,
        "M5-D2c1 GLOBAL TIMEOUT"
    );

end


endmodule
