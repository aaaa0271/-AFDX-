`timescale 1ns / 1ps

module tb_afdx_rx_payload_frame_arbiter;


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
// A
// ============================================================

reg [7:0] a_data;
reg       a_valid;
wire      a_ready;
reg       a_sof;
reg       a_eof;


// ============================================================
// B
// ============================================================

reg [7:0] b_data;
reg       b_valid;
wire      b_ready;
reg       b_sof;
reg       b_eof;


// ============================================================
// Output
// ============================================================

wire [7:0] out_data;
wire       out_valid;
reg        out_ready;
wire       out_sof;
wire       out_eof;
wire       out_network;
wire       frame_active;


// ============================================================
// DUT
// ============================================================

afdx_rx_payload_frame_arbiter dut (

    .clk (
        clk
    ),

    .rst (
        rst
    ),


    .a_data (
        a_data
    ),

    .a_valid (
        a_valid
    ),

    .a_ready (
        a_ready
    ),

    .a_sof (
        a_sof
    ),

    .a_eof (
        a_eof
    ),


    .b_data (
        b_data
    ),

    .b_valid (
        b_valid
    ),

    .b_ready (
        b_ready
    ),

    .b_sof (
        b_sof
    ),

    .b_eof (
        b_eof
    ),


    .out_data (
        out_data
    ),

    .out_valid (
        out_valid
    ),

    .out_ready (
        out_ready
    ),

    .out_sof (
        out_sof
    ),

    .out_eof (
        out_eof
    ),

    .out_network (
        out_network
    ),

    .frame_active (
        frame_active
    )

);


// ============================================================
// Scoreboard
// ============================================================

integer error_count;
integer output_count;


reg [7:0] captured_data [0:255];
reg       captured_sof  [0:255];
reg       captured_eof  [0:255];
reg       captured_net  [0:255];


always @(posedge clk) begin

    if (rst) begin

        output_count =
            0;

    end
    else if (
        out_valid
        &&
        out_ready
    ) begin

        captured_data[output_count] =
            out_data;

        captured_sof[output_count] =
            out_sof;

        captured_eof[output_count] =
            out_eof;

        captured_net[output_count] =
            out_network;

        output_count =
            output_count + 1;

    end

end


// ============================================================
// Test variables
// ============================================================

integer start_error;
integer base_output;
integer timeout;


// ============================================================
// Clear inputs
// ============================================================

task clear_inputs;

    begin

        a_data =
            8'd0;

        a_valid =
            1'b0;

        a_sof =
            1'b0;

        a_eof =
            1'b0;


        b_data =
            8'd0;

        b_valid =
            1'b0;

        b_sof =
            1'b0;

        b_eof =
            1'b0;

    end

endtask


// ============================================================
// Send one A byte
// ============================================================

task send_a_byte;

    input [7:0] data_value;
    input       sof_value;
    input       eof_value;

    begin

        @(negedge clk);

        a_data =
            data_value;

        a_sof =
            sof_value;

        a_eof =
            eof_value;

        a_valid =
            1'b1;


        #1;


        while (
            a_ready
            !==
            1'b1
        ) begin

            @(posedge clk);

            #1;

        end


        @(posedge clk);

        #1;


        @(negedge clk);

        a_valid =
            1'b0;

        a_sof =
            1'b0;

        a_eof =
            1'b0;

    end

endtask


// ============================================================
// Send one B byte
// ============================================================

task send_b_byte;

    input [7:0] data_value;
    input       sof_value;
    input       eof_value;

    begin

        @(negedge clk);

        b_data =
            data_value;

        b_sof =
            sof_value;

        b_eof =
            eof_value;

        b_valid =
            1'b1;


        #1;


        while (
            b_ready
            !==
            1'b1
        ) begin

            @(posedge clk);

            #1;

        end


        @(posedge clk);

        #1;


        @(negedge clk);

        b_valid =
            1'b0;

        b_sof =
            1'b0;

        b_eof =
            1'b0;

    end

endtask


// ============================================================
// Check captured byte
// ============================================================

task expect_byte;

    input integer index;
    input         expected_network;
    input [7:0]   expected_data;
    input         expected_sof;
    input         expected_eof;

    begin

        if (
            captured_net[index]
            !==
            expected_network
        ) begin

            $display(
                "ERROR [%0d]: network=%0d expected=%0d",
                index,
                captured_net[index],
                expected_network
            );

            error_count =
                error_count + 1;

        end


        if (
            captured_data[index]
            !==
            expected_data
        ) begin

            $display(
                "ERROR [%0d]: data=%02x expected=%02x",
                index,
                captured_data[index],
                expected_data
            );

            error_count =
                error_count + 1;

        end


        if (
            captured_sof[index]
            !==
            expected_sof
        ) begin

            $display(
                "ERROR [%0d]: sof=%0d expected=%0d",
                index,
                captured_sof[index],
                expected_sof
            );

            error_count =
                error_count + 1;

        end


        if (
            captured_eof[index]
            !==
            expected_eof
        ) begin

            $display(
                "ERROR [%0d]: eof=%0d expected=%0d",
                index,
                captured_eof[index],
                expected_eof
            );

            error_count =
                error_count + 1;

        end

    end

endtask


// ============================================================
// Wait for output count
// ============================================================

task wait_output_count;

    input integer expected;

    begin

        timeout =
            0;


        while (
            (output_count < expected)
            &&
            (timeout < 100)
        ) begin

            @(posedge clk);

            #1;

            timeout =
                timeout + 1;

        end


        if (
            timeout >= 100
        ) begin

            $display(
                "ERROR: output timeout got=%0d expected=%0d",
                output_count,
                expected
            );

            error_count =
                error_count + 1;

        end

    end

endtask


// ============================================================
// Main
// ============================================================

initial begin

    error_count =
        0;


    clear_inputs;


    out_ready =
        1'b1;

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
        "M5-D2c2 PAYLOAD FRAME ARBITER TEST"
    );

    $display(
        "=============================================="
    );

    $display("");


    // ========================================================
    // TC-01 Reset / idle
    // ========================================================

    start_error =
        error_count;


    if (
        out_valid
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2c2-01 ERROR: out_valid after reset"
        );

        error_count =
            error_count + 1;

    end


    if (
        frame_active
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2c2-01 ERROR: frame_active after reset"
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
            "TC-M5-D2c2-01 PASS: reset / idle"
        );
    else
        $display(
            "TC-M5-D2c2-01 FAIL"
        );


    // ========================================================
    // TC-02 A-only 3-byte frame
    // ========================================================

    start_error =
        error_count;

    base_output =
        output_count;


    send_a_byte(
        8'hA1,
        1'b1,
        1'b0
    );

    send_a_byte(
        8'hA2,
        1'b0,
        1'b0
    );

    send_a_byte(
        8'hA3,
        1'b0,
        1'b1
    );


    wait_output_count(
        base_output + 3
    );


    expect_byte(
        base_output + 0,
        1'b0,
        8'hA1,
        1'b1,
        1'b0
    );

    expect_byte(
        base_output + 1,
        1'b0,
        8'hA2,
        1'b0,
        1'b0
    );

    expect_byte(
        base_output + 2,
        1'b0,
        8'hA3,
        1'b0,
        1'b1
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-02 PASS: A-only frame"
        );
    else
        $display(
            "TC-M5-D2c2-02 FAIL"
        );


    // ========================================================
    // TC-03 B-only 3-byte frame
    // ========================================================

    start_error =
        error_count;

    base_output =
        output_count;


    send_b_byte(
        8'hB1,
        1'b1,
        1'b0
    );

    send_b_byte(
        8'hB2,
        1'b0,
        1'b0
    );

    send_b_byte(
        8'hB3,
        1'b0,
        1'b1
    );


    wait_output_count(
        base_output + 3
    );


    expect_byte(
        base_output + 0,
        1'b1,
        8'hB1,
        1'b1,
        1'b0
    );

    expect_byte(
        base_output + 1,
        1'b1,
        8'hB2,
        1'b0,
        1'b0
    );

    expect_byte(
        base_output + 2,
        1'b1,
        8'hB3,
        1'b0,
        1'b1
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-03 PASS: B-only frame"
        );
    else
        $display(
            "TC-M5-D2c2-03 FAIL"
        );


    // ========================================================
    // TC-04
    // Frame atomicity.
    //
    // A starts first.
    // B becomes valid while A frame is active.
    //
    // B MUST NOT receive ready until A EOF.
    // ========================================================

    start_error =
        error_count;

    base_output =
        output_count;


    // A first byte -> locks A.

    send_a_byte(
        8'h41,
        1'b1,
        1'b0
    );


    // Present B SOF while A frame remains active.

    @(negedge clk);

    b_data =
        8'h51;

    b_sof =
        1'b1;

    b_eof =
        1'b0;

    b_valid =
        1'b1;


    #1;


    if (
        b_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2c2-04 ERROR: B ready during active A frame"
        );

        error_count =
            error_count + 1;

    end


    // Continue A.

    send_a_byte(
        8'h42,
        1'b0,
        1'b0
    );


    #1;


    if (
        b_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2c2-04 ERROR: B stole middle of A frame"
        );

        error_count =
            error_count + 1;

    end


    // A EOF.

    send_a_byte(
        8'h43,
        1'b0,
        1'b1
    );


    // Now B must eventually become ready.

    timeout =
        0;


    while (
        (b_ready !== 1'b1)
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
            "TC-M5-D2c2-04 ERROR: B not released after A EOF"
        );

        error_count =
            error_count + 1;

    end


    // B first byte handshake.

    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;

    b_sof =
        1'b0;


    send_b_byte(
        8'h52,
        1'b0,
        1'b1
    );


    wait_output_count(
        base_output + 5
    );


    expect_byte(
        base_output + 0,
        1'b0,
        8'h41,
        1'b1,
        1'b0
    );

    expect_byte(
        base_output + 1,
        1'b0,
        8'h42,
        1'b0,
        1'b0
    );

    expect_byte(
        base_output + 2,
        1'b0,
        8'h43,
        1'b0,
        1'b1
    );

    expect_byte(
        base_output + 3,
        1'b1,
        8'h51,
        1'b1,
        1'b0
    );

    expect_byte(
        base_output + 4,
        1'b1,
        8'h52,
        1'b0,
        1'b1
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-04 PASS: frame atomicity A then B"
        );
    else
        $display(
            "TC-M5-D2c2-04 FAIL"
        );


    // ========================================================
    // TC-05 Output backpressure
    // ========================================================

    start_error =
        error_count;

    base_output =
        output_count;


    out_ready =
        1'b0;


    @(negedge clk);

    a_data =
        8'h61;

    a_sof =
        1'b1;

    a_eof =
        1'b0;

    a_valid =
        1'b1;


    #1;


    if (
        a_ready
        !==
        1'b0
    ) begin

        $display(
            "TC-M5-D2c2-05 ERROR: A ready during output stall"
        );

        error_count =
            error_count + 1;

    end


    repeat (5) begin

        @(posedge clk);

        #1;


        if (
            output_count
            !=
            base_output
        ) begin

            $display(
                "TC-M5-D2c2-05 ERROR: output transferred while stalled"
            );

            error_count =
                error_count + 1;

        end


        if (
            out_data
            !==
            8'h61
        ) begin

            $display(
                "TC-M5-D2c2-05 ERROR: output data changed during stall"
            );

            error_count =
                error_count + 1;

        end

    end


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
            "TC-M5-D2c2-05 ERROR: A not released"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;

    a_sof =
        1'b0;


    send_a_byte(
        8'h62,
        1'b0,
        1'b1
    );


    wait_output_count(
        base_output + 2
    );


    expect_byte(
        base_output + 0,
        1'b0,
        8'h61,
        1'b1,
        1'b0
    );

    expect_byte(
        base_output + 1,
        1'b0,
        8'h62,
        1'b0,
        1'b1
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-05 PASS: output backpressure"
        );
    else
        $display(
            "TC-M5-D2c2-05 FAIL"
        );


    // ========================================================
    // TC-06
    // Simultaneous single-byte frames.
    //
    // Reset makes first tie choose A.
    // Both must survive.
    // ========================================================

    start_error =
        error_count;


    @(negedge clk);

    rst =
        1'b1;


    clear_inputs;


    repeat (3)
        @(posedge clk);


    @(negedge clk);

    rst =
        1'b0;


    repeat (2)
        @(posedge clk);


    base_output =
        output_count;


    @(negedge clk);


    a_data =
        8'h71;

    a_sof =
        1'b1;

    a_eof =
        1'b1;

    a_valid =
        1'b1;


    b_data =
        8'h81;

    b_sof =
        1'b1;

    b_eof =
        1'b1;

    b_valid =
        1'b1;


    #1;


    if (
        !(
            a_ready
            &&
            !b_ready
        )
    ) begin

        $display(
            "TC-M5-D2c2-06 ERROR: first tie did not select A"
        );

        error_count =
            error_count + 1;

    end


    // A transfers.

    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;

    a_sof =
        1'b0;

    a_eof =
        1'b0;


    // B remains valid and must transfer.

    #1;


    if (
        b_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2c2-06 ERROR: B lost after A single-byte frame"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;

    b_sof =
        1'b0;

    b_eof =
        1'b0;


    wait_output_count(
        base_output + 2
    );


    expect_byte(
        base_output + 0,
        1'b0,
        8'h71,
        1'b1,
        1'b1
    );

    expect_byte(
        base_output + 1,
        1'b1,
        8'h81,
        1'b1,
        1'b1
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-06 PASS: simultaneous frames preserved"
        );
    else
        $display(
            "TC-M5-D2c2-06 FAIL"
        );


    // ========================================================
    // TC-07
    // Round-robin tie reversal.
    //
    // Previous winner from TC-06 ended B.
    // Next simultaneous tie must choose A.
    //
    // Then create another tie after A winner;
    // it must choose B.
    // ========================================================

    start_error =
        error_count;

    base_output =
        output_count;


    // Previous last grant = B.
    // Tie should select A.

    @(negedge clk);


    a_data =
        8'h91;

    a_sof =
        1'b1;

    a_eof =
        1'b1;

    a_valid =
        1'b1;


    b_data =
        8'hA1;

    b_sof =
        1'b1;

    b_eof =
        1'b1;

    b_valid =
        1'b1;


    #1;


    if (
        !(
            a_ready
            &&
            !b_ready
        )
    ) begin

        $display(
            "TC-M5-D2c2-07 ERROR: tie after B should choose A"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    #1;


    if (
        b_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2c2-07 ERROR: pending B not released"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    // At this point last completed source = B again.
    //
    // Force an A-only single-byte frame so last_grant becomes A.

    send_a_byte(
        8'h92,
        1'b1,
        1'b1
    );


    // Now next tie must select B.

    @(negedge clk);


    a_data =
        8'h93;

    a_sof =
        1'b1;

    a_eof =
        1'b1;

    a_valid =
        1'b1;


    b_data =
        8'hA3;

    b_sof =
        1'b1;

    b_eof =
        1'b1;

    b_valid =
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
            "TC-M5-D2c2-07 ERROR: tie after A should choose B"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    b_valid =
        1'b0;


    #1;


    if (
        a_ready
        !==
        1'b1
    ) begin

        $display(
            "TC-M5-D2c2-07 ERROR: pending A not released"
        );

        error_count =
            error_count + 1;

    end


    @(posedge clk);

    #1;


    @(negedge clk);

    a_valid =
        1'b0;


    wait_output_count(
        base_output + 5
    );


    if (
        error_count
        ==
        start_error
    )
        $display(
            "TC-M5-D2c2-07 PASS: round-robin frame arbitration"
        );
    else
        $display(
            "TC-M5-D2c2-07 FAIL"
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
            "M5-D2c2 ALL TESTS PASS"
        );

    end
    else begin

        $display(
            "M5-D2c2 FAILED: %0d error(s)",
            error_count
        );

        $fatal(
            1,
            "M5-D2c2 regression failed"
        );

    end


    $display(
        "=============================================="
    );


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
        "M5-D2c2 GLOBAL TIMEOUT"
    );

end


endmodule
