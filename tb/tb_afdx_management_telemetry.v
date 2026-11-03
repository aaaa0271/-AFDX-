`timescale 1ns / 1ps

module tb_afdx_management_telemetry;


    reg clk;
    reg rst_n;

    reg snapshot_req;
    wire snapshot_ack;
    wire snapshot_valid;
    wire [31:0] snapshot_id;

    reg event_clear;

    reg [7:0] rd_addr;
    wire [31:0] rd_data;
    wire rd_valid;


    // ========================================================
    // Status
    // ========================================================

    reg network_a_enable;
    reg network_b_enable;
    reg degraded_mode;

    reg redundancy_ok;
    reg frame_count_match;
    reg active_byte_count_match;

    reg redundancy_fault_event;
    reg fault_applied_event;


    // ========================================================
    // RX counters
    // ========================================================

    reg [31:0] rx_accepted_count;
    reg [31:0] rx_accepted_a_count;
    reg [31:0] rx_accepted_b_count;

    reg [31:0] rx_duplicate_count;
    reg [31:0] rx_cross_network_duplicate_count;
    reg [31:0] rx_same_network_repeat_count;

    reg [31:0] rx_stale_count;
    reg [31:0] rx_sequence_gap_count;


    // ========================================================
    // TX counters
    // ========================================================

    reg [31:0] tx_a_frame_count;
    reg [31:0] tx_b_frame_count;

    reg [31:0] tx_a_active_byte_count;
    reg [31:0] tx_b_active_byte_count;

    reg [31:0] tx_byte_mismatch_count;
    reg [31:0] tx_frame_skew_cycle_count;
    reg [31:0] tx_frame_done_skew_count;
    reg [31:0] tx_er_mismatch_count;

    reg [31:0] tx_a_error_cycle_count;
    reg [31:0] tx_b_error_cycle_count;

    reg [31:0] tx_a_underrun_count;
    reg [31:0] tx_b_underrun_count;


    integer errors;


    // Small CLK_HZ for simulation speed.
    afdx_management_telemetry #(
        .CLK_HZ(1000)
    )
    dut (
        .clk(clk),
        .rst_n(rst_n),

        .snapshot_req(snapshot_req),
        .snapshot_ack(snapshot_ack),
        .snapshot_valid(snapshot_valid),
        .snapshot_id(snapshot_id),

        .event_clear(event_clear),

        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),

        .network_a_enable(network_a_enable),
        .network_b_enable(network_b_enable),
        .degraded_mode(degraded_mode),

        .redundancy_ok(redundancy_ok),
        .frame_count_match(frame_count_match),
        .active_byte_count_match(active_byte_count_match),

        .redundancy_fault_event(redundancy_fault_event),
        .fault_applied_event(fault_applied_event),

        .rx_accepted_count(rx_accepted_count),
        .rx_accepted_a_count(rx_accepted_a_count),
        .rx_accepted_b_count(rx_accepted_b_count),

        .rx_duplicate_count(rx_duplicate_count),

        .rx_cross_network_duplicate_count(
            rx_cross_network_duplicate_count
        ),

        .rx_same_network_repeat_count(
            rx_same_network_repeat_count
        ),

        .rx_stale_count(rx_stale_count),

        .rx_sequence_gap_count(
            rx_sequence_gap_count
        ),

        .tx_a_frame_count(tx_a_frame_count),
        .tx_b_frame_count(tx_b_frame_count),

        .tx_a_active_byte_count(
            tx_a_active_byte_count
        ),

        .tx_b_active_byte_count(
            tx_b_active_byte_count
        ),

        .tx_byte_mismatch_count(
            tx_byte_mismatch_count
        ),

        .tx_frame_skew_cycle_count(
            tx_frame_skew_cycle_count
        ),

        .tx_frame_done_skew_count(
            tx_frame_done_skew_count
        ),

        .tx_er_mismatch_count(
            tx_er_mismatch_count
        ),

        .tx_a_error_cycle_count(
            tx_a_error_cycle_count
        ),

        .tx_b_error_cycle_count(
            tx_b_error_cycle_count
        ),

        .tx_a_underrun_count(
            tx_a_underrun_count
        ),

        .tx_b_underrun_count(
            tx_b_underrun_count
        )
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ========================================================
    // Snapshot helper
    // ========================================================

    task take_snapshot;
    begin

        @(negedge clk);
        snapshot_req = 1'b1;

        @(negedge clk);
        snapshot_req = 1'b0;

        @(posedge clk);
        #1;

        if (!snapshot_valid) begin
            $display("ERROR: snapshot_valid not asserted");
            errors = errors + 1;
        end

    end
    endtask


    // ========================================================
    // Read checker
    // ========================================================

    task check_reg;

        input [7:0]  addr;
        input [31:0] expected;

    begin

        rd_addr = addr;
        #1;

        if (!rd_valid) begin

            $display(
                "ERROR addr=%02x rd_valid=0",
                addr
            );

            errors = errors + 1;

        end
        else if (rd_data !== expected) begin

            $display(
                "ERROR addr=%02x expected=%08x got=%08x",
                addr,
                expected,
                rd_data
            );

            errors = errors + 1;

        end

    end
    endtask


    // ========================================================
    // Main test
    // ========================================================

    initial begin

        errors = 0;

        rst_n = 0;

        snapshot_req = 0;
        event_clear  = 0;
        rd_addr      = 0;

        network_a_enable = 0;
        network_b_enable = 0;
        degraded_mode    = 0;

        redundancy_ok          = 0;
        frame_count_match      = 0;
        active_byte_count_match = 0;

        redundancy_fault_event = 0;
        fault_applied_event    = 0;

        rx_accepted_count = 0;
        rx_accepted_a_count = 0;
        rx_accepted_b_count = 0;

        rx_duplicate_count = 0;
        rx_cross_network_duplicate_count = 0;
        rx_same_network_repeat_count = 0;

        rx_stale_count = 0;
        rx_sequence_gap_count = 0;

        tx_a_frame_count = 0;
        tx_b_frame_count = 0;

        tx_a_active_byte_count = 0;
        tx_b_active_byte_count = 0;

        tx_byte_mismatch_count = 0;
        tx_frame_skew_cycle_count = 0;
        tx_frame_done_skew_count = 0;
        tx_er_mismatch_count = 0;

        tx_a_error_cycle_count = 0;
        tx_b_error_cycle_count = 0;

        tx_a_underrun_count = 0;
        tx_b_underrun_count = 0;


        repeat (5) @(posedge clk);

        rst_n = 1;

        repeat (3) @(posedge clk);


        // ====================================================
        // TC-01 Reset / no snapshot
        // ====================================================

        if (snapshot_valid !== 1'b0) begin
            $display("TC-M6A-01 FAIL");
            errors = errors + 1;
        end
        else begin
            $display(
                "TC-M6A-01 PASS: reset / no snapshot"
            );
        end


        // ====================================================
        // TC-02 Basic atomic snapshot
        // ====================================================

        network_a_enable = 1;
        network_b_enable = 1;
        degraded_mode    = 0;

        redundancy_ok           = 1;
        frame_count_match       = 1;
        active_byte_count_match = 1;

        rx_accepted_count   = 32'd100;
        rx_accepted_a_count = 32'd60;
        rx_accepted_b_count = 32'd40;

        rx_duplicate_count = 32'd90;

        rx_cross_network_duplicate_count = 32'd80;
        rx_same_network_repeat_count     = 32'd10;

        rx_stale_count        = 32'd4;
        rx_sequence_gap_count = 32'd7;

        tx_a_frame_count = 32'd120;
        tx_b_frame_count = 32'd120;

        tx_a_active_byte_count = 32'd5000;
        tx_b_active_byte_count = 32'd5000;

        tx_byte_mismatch_count    = 32'd2;
        tx_frame_skew_cycle_count = 32'd3;
        tx_frame_done_skew_count  = 32'd1;
        tx_er_mismatch_count      = 32'd4;

        tx_a_error_cycle_count = 32'd5;
        tx_b_error_cycle_count = 32'd6;

        tx_a_underrun_count = 32'd7;
        tx_b_underrun_count = 32'd8;


        take_snapshot;


        check_reg(8'h10, 32'd100);
        check_reg(8'h11, 32'd60);
        check_reg(8'h12, 32'd40);

        check_reg(8'h13, 32'd90);
        check_reg(8'h14, 32'd80);
        check_reg(8'h15, 32'd10);

        check_reg(8'h16, 32'd4);
        check_reg(8'h17, 32'd7);

        check_reg(8'h20, 32'd120);
        check_reg(8'h21, 32'd120);

        check_reg(8'h24, 32'd2);

        $display(
            "TC-M6A-02 PASS: basic snapshot"
        );


        // ====================================================
        // TC-03 Snapshot isolation
        //
        // Change LIVE M5 counters.
        // Management snapshot MUST NOT change.
        // ====================================================

        rx_accepted_count   = 32'd999;
        rx_accepted_a_count = 32'd555;
        rx_accepted_b_count = 32'd444;

        tx_a_frame_count = 32'd888;
        tx_b_frame_count = 32'd777;

        repeat (5) @(posedge clk);

        check_reg(8'h10, 32'd100);
        check_reg(8'h11, 32'd60);
        check_reg(8'h12, 32'd40);

        check_reg(8'h20, 32'd120);
        check_reg(8'h21, 32'd120);

        $display(
            "TC-M6A-03 PASS: snapshot isolated from live changes"
        );


        // ====================================================
        // TC-04 New snapshot updates atomically
        // ====================================================

        take_snapshot;

        check_reg(8'h10, 32'd999);
        check_reg(8'h11, 32'd555);
        check_reg(8'h12, 32'd444);

        check_reg(8'h20, 32'd888);
        check_reg(8'h21, 32'd777);

        if (snapshot_id !== 32'd2) begin

            $display(
                "TC-M6A-04 FAIL: snapshot_id=%0d",
                snapshot_id
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "TC-M6A-04 PASS: second atomic snapshot"
            );

        end


        // ====================================================
        // TC-05 Sticky redundancy fault event
        // ====================================================

        @(negedge clk);
        redundancy_fault_event = 1;

        @(negedge clk);
        redundancy_fault_event = 0;

        repeat (3) @(posedge clk);

        take_snapshot;

        check_reg(8'h04, 32'h0000_0001);

        $display(
            "TC-M6A-05 PASS: fault event latched"
        );


        // ====================================================
        // TC-06 Fault injection event
        // ====================================================

        @(negedge clk);
        fault_applied_event = 1;

        @(negedge clk);
        fault_applied_event = 0;

        take_snapshot;

        check_reg(8'h04, 32'h0000_0003);

        $display(
            "TC-M6A-06 PASS: multiple events latched"
        );


        // ====================================================
        // TC-07 Event clear does NOT touch M5 counters
        // ====================================================

        @(negedge clk);
        event_clear = 1;

        @(negedge clk);
        event_clear = 0;

        take_snapshot;

        check_reg(8'h04, 32'd0);

        check_reg(8'h10, 32'd999);
        check_reg(8'h20, 32'd888);

        $display(
            "TC-M6A-07 PASS: management event clear isolated"
        );


        // ====================================================
        // TC-08 Status word
        // ====================================================

        network_a_enable = 1;
        network_b_enable = 0;
        degraded_mode    = 1;

        redundancy_ok           = 0;
        frame_count_match       = 0;
        active_byte_count_match = 0;

        take_snapshot;

        // bit0 A enable
        // bit1 B enable
        // bit2 degraded
        //
        // = 000...0101 = 0x5

        check_reg(
            8'h03,
            32'h0000_0005
        );

        $display(
            "TC-M6A-08 PASS: degraded status"
        );


        // ====================================================
        // TC-09 Invalid register
        // ====================================================

        rd_addr = 8'hFF;
        #1;

        if (rd_valid !== 1'b0) begin

            $display(
                "TC-M6A-09 FAIL: invalid register accepted"
            );

            errors = errors + 1;

        end
        else begin

            $display(
                "TC-M6A-09 PASS: invalid register rejected"
            );

        end


        // ====================================================
        // Final
        // ====================================================

        if (errors == 0) begin

            $display("");
            $display("======================================");
            $display("M6A MANAGEMENT TELEMETRY ALL TESTS PASS");
            $display("======================================");

        end
        else begin

            $display("");
            $display(
                "M6A FAIL: errors=%0d",
                errors
            );

        end

        #100;
        $stop;

    end


endmodule
