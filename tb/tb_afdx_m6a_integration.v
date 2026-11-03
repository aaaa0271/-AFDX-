`timescale 1ns / 1ps

module tb_afdx_m6a_integration;
    reg clk, rst_n;
    reg d1_clear, rx_valid, rx_network;
    reg [1:0] rx_vl_id;
    reg [7:0] rx_seq;
    reg [31:0] rx_payload;
    wire rx_ready;
    wire d1_out_valid;
    wire [1:0] d1_out_vl_id;
    wire [7:0] d1_out_seq;
    wire [31:0] d1_out_payload;
    wire d1_out_network;
    wire accept_event, duplicate_event, stale_event, gap_event;
    wire [31:0] accepted_count, accepted_a_count, accepted_b_count;
    wire [31:0] duplicate_count, cross_network_duplicate_count;
    wire [31:0] same_network_repeat_count, stale_count, sequence_gap_count;
    wire last_valid0_dbg, last_valid1_dbg, last_valid2_dbg, last_valid3_dbg;
    wire [7:0] last_seq0_dbg, last_seq1_dbg, last_seq2_dbg, last_seq3_dbg;
    wire [1:0] seen_mask0_dbg, seen_mask1_dbg, seen_mask2_dbg, seen_mask3_dbg;

    reg snapshot_req, event_clear;
    wire snapshot_ack, snapshot_valid;
    wire [31:0] snapshot_id, rd_data;
    reg [7:0] rd_addr;
    wire rd_valid;
    reg network_a_enable, network_b_enable, degraded_mode;
    reg redundancy_ok, frame_count_match, active_byte_count_match;
    reg fault_applied_event;
    reg [31:0] tx_a_frame_count, tx_b_frame_count;
    reg [31:0] tx_a_active_byte_count, tx_b_active_byte_count;
    reg [31:0] tx_byte_mismatch_count, tx_frame_skew_cycle_count;
    reg [31:0] tx_frame_done_skew_count, tx_er_mismatch_count;
    reg [31:0] tx_a_error_cycle_count, tx_b_error_cycle_count;
    reg [31:0] tx_a_underrun_count, tx_b_underrun_count;
    integer errors, start_error;

    afdx_rx_redundancy_eliminator u_d1 (
        .clk(clk), .rst_n(rst_n), .clear(d1_clear),
        .rx_valid(rx_valid), .rx_ready(rx_ready), .rx_network(rx_network),
        .rx_vl_id(rx_vl_id), .rx_seq(rx_seq), .rx_payload(rx_payload),
        .out_valid(d1_out_valid), .out_ready(1'b1), .out_vl_id(d1_out_vl_id),
        .out_seq(d1_out_seq), .out_payload(d1_out_payload), .out_network(d1_out_network),
        .accept_event(accept_event), .duplicate_event(duplicate_event),
        .stale_event(stale_event), .gap_event(gap_event),
        .accepted_count(accepted_count), .accepted_a_count(accepted_a_count),
        .accepted_b_count(accepted_b_count), .duplicate_count(duplicate_count),
        .cross_network_duplicate_count(cross_network_duplicate_count),
        .same_network_repeat_count(same_network_repeat_count),
        .stale_count(stale_count), .sequence_gap_count(sequence_gap_count),
        .last_valid0_dbg(last_valid0_dbg), .last_valid1_dbg(last_valid1_dbg),
        .last_valid2_dbg(last_valid2_dbg), .last_valid3_dbg(last_valid3_dbg),
        .last_seq0_dbg(last_seq0_dbg), .last_seq1_dbg(last_seq1_dbg),
        .last_seq2_dbg(last_seq2_dbg), .last_seq3_dbg(last_seq3_dbg),
        .seen_mask0_dbg(seen_mask0_dbg), .seen_mask1_dbg(seen_mask1_dbg),
        .seen_mask2_dbg(seen_mask2_dbg), .seen_mask3_dbg(seen_mask3_dbg)
    );

    afdx_m6a_integration #(.CLK_HZ(1000)) u_m6a (
        .clk(clk), .rst_n(rst_n), .snapshot_req(snapshot_req),
        .snapshot_ack(snapshot_ack), .snapshot_valid(snapshot_valid),
        .snapshot_id(snapshot_id), .event_clear(event_clear), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid),
        .m5_network_a_enable(network_a_enable), .m5_network_b_enable(network_b_enable),
        .m5_degraded_mode(degraded_mode), .m5_redundancy_ok(redundancy_ok),
        .m5_frame_count_match(frame_count_match),
        .m5_active_byte_count_match(active_byte_count_match),
        .m5_fault_applied_event(fault_applied_event),
        .m5_rx_accepted_count(accepted_count), .m5_rx_accepted_a_count(accepted_a_count),
        .m5_rx_accepted_b_count(accepted_b_count), .m5_rx_duplicate_count(duplicate_count),
        .m5_rx_cross_network_duplicate_count(cross_network_duplicate_count),
        .m5_rx_same_network_repeat_count(same_network_repeat_count),
        .m5_rx_stale_count(stale_count), .m5_rx_sequence_gap_count(sequence_gap_count),
        .m5_tx_a_frame_count(tx_a_frame_count), .m5_tx_b_frame_count(tx_b_frame_count),
        .m5_tx_a_active_byte_count(tx_a_active_byte_count),
        .m5_tx_b_active_byte_count(tx_b_active_byte_count),
        .m5_tx_byte_mismatch_count(tx_byte_mismatch_count),
        .m5_tx_frame_skew_cycle_count(tx_frame_skew_cycle_count),
        .m5_tx_frame_done_skew_count(tx_frame_done_skew_count),
        .m5_tx_er_mismatch_count(tx_er_mismatch_count),
        .m5_tx_a_error_cycle_count(tx_a_error_cycle_count),
        .m5_tx_b_error_cycle_count(tx_b_error_cycle_count),
        .m5_tx_a_underrun_count(tx_a_underrun_count),
        .m5_tx_b_underrun_count(tx_b_underrun_count)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    task clear_d1;
    begin
        @(negedge clk); d1_clear = 1'b1;
        @(negedge clk); d1_clear = 1'b0;
        repeat (2) @(posedge clk);
    end
    endtask

    task send_frame;
        input net; input [1:0] vl; input [7:0] seq; input [31:0] payload;
        integer timeout;
    begin
        @(negedge clk); rx_network = net; rx_vl_id = vl; rx_seq = seq;
        rx_payload = payload; rx_valid = 1'b1; timeout = 0;
        while (!rx_ready && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
        if (timeout >= 100) begin $display("ERROR: D1 input timeout"); errors = errors + 1; end
        @(posedge clk); #1; @(negedge clk); rx_valid = 1'b0;
    end
    endtask

    task take_snapshot;
    begin
        @(negedge clk); snapshot_req = 1'b1;
        @(posedge clk); #1;
        if (!snapshot_ack || !snapshot_valid) begin $display("ERROR: snapshot not acknowledged"); errors = errors + 1; end
        @(negedge clk); snapshot_req = 1'b0;
    end
    endtask

    task read_expect;
        input [7:0] addr; input [31:0] expected;
    begin
        rd_addr = addr; #1;
        if (!rd_valid || rd_data !== expected) begin
            $display("ERROR: reg %02x expected %08x got %08x valid=%0d", addr, expected, rd_data, rd_valid);
            errors = errors + 1;
        end
    end
    endtask

    task clear_events;
    begin
        @(negedge clk); event_clear = 1'b1;
        @(posedge clk); #1; @(negedge clk); event_clear = 1'b0;
    end
    endtask

    initial begin
        errors = 0; rst_n = 0; d1_clear = 0; rx_valid = 0; rx_network = 0;
        rx_vl_id = 0; rx_seq = 0; rx_payload = 0; snapshot_req = 0;
        event_clear = 0; rd_addr = 0;
        network_a_enable = 1; network_b_enable = 1; degraded_mode = 0;
        redundancy_ok = 1; frame_count_match = 1; active_byte_count_match = 1;
        fault_applied_event = 0;
        tx_a_frame_count = 12; tx_b_frame_count = 12;
        tx_a_active_byte_count = 480; tx_b_active_byte_count = 480;
        tx_byte_mismatch_count = 0; tx_frame_skew_cycle_count = 0;
        tx_frame_done_skew_count = 0; tx_er_mismatch_count = 0;
        tx_a_error_cycle_count = 0; tx_b_error_cycle_count = 0;
        tx_a_underrun_count = 0; tx_b_underrun_count = 0;
        repeat (4) @(posedge clk); rst_n = 1;
        repeat (3) @(posedge clk);

        $display("==============================================");
        $display("M6A INTEGRATION REGRESSION");
        $display("==============================================");

        start_error = errors; clear_d1;
        send_frame(0, 0, 10, 32'hAAAA0010); send_frame(1, 0, 11, 32'hBBBB0011);
        take_snapshot; read_expect(8'h10, 2); read_expect(8'h11, 1); read_expect(8'h12, 1);
        read_expect(8'h20, 12); read_expect(8'h21, 12); read_expect(8'h03, 32'h3B);
        if (errors == start_error) $display("TC-M6A-I-01 PASS: normal A/B"); else $display("TC-M6A-I-01 FAIL");

        start_error = errors; clear_d1;
        send_frame(0, 0, 20, 32'hAAAA0020); send_frame(1, 0, 20, 32'hBBBB0020);
        take_snapshot; read_expect(8'h10, 1); read_expect(8'h13, 1); read_expect(8'h14, 1); read_expect(8'h15, 0);
        if (errors == start_error) $display("TC-M6A-I-02 PASS: cross-network duplicate"); else $display("TC-M6A-I-02 FAIL");

        start_error = errors; clear_d1;
        send_frame(0, 0, 30, 32'hAAAA0030); send_frame(0, 0, 30, 32'hAAAA0030);
        take_snapshot; read_expect(8'h10, 1); read_expect(8'h13, 1); read_expect(8'h15, 1);
        if (errors == start_error) $display("TC-M6A-I-03 PASS: same-network repeat"); else $display("TC-M6A-I-03 FAIL");

        start_error = errors; clear_d1;
        send_frame(0, 0, 40, 32'hAAAA0040); send_frame(1, 0, 39, 32'hBBBB0039);
        take_snapshot; read_expect(8'h10, 1); read_expect(8'h16, 1);
        if (errors == start_error) $display("TC-M6A-I-04 PASS: stale"); else $display("TC-M6A-I-04 FAIL");

        start_error = errors; clear_d1;
        send_frame(0, 0, 50, 32'hAAAA0050); send_frame(1, 0, 54, 32'hBBBB0054);
        take_snapshot; read_expect(8'h10, 2); read_expect(8'h17, 3);
        if (errors == start_error) $display("TC-M6A-I-05 PASS: sequence gap"); else $display("TC-M6A-I-05 FAIL");

        start_error = errors; clear_events; redundancy_ok = 1;
        repeat (2) @(posedge clk);
        @(negedge clk); network_a_enable = 0; network_b_enable = 1; degraded_mode = 1;
        redundancy_ok = 0; frame_count_match = 0; active_byte_count_match = 0; fault_applied_event = 1;
        tx_a_frame_count = 20; tx_b_frame_count = 19; tx_byte_mismatch_count = 1;
        @(posedge clk); #1; @(negedge clk); fault_applied_event = 0;
        repeat (2) @(posedge clk); take_snapshot;
        read_expect(8'h03, 6); read_expect(8'h04, 3); read_expect(8'h20, 20); read_expect(8'h21, 19); read_expect(8'h24, 1);
        if (errors == start_error) $display("TC-M6A-I-06 PASS: Network-A degraded/fault"); else $display("TC-M6A-I-06 FAIL");

        @(negedge clk); network_a_enable = 1; network_b_enable = 1; degraded_mode = 0;
        redundancy_ok = 1; frame_count_match = 1; active_byte_count_match = 1;
        repeat (2) @(posedge clk); clear_events;

        start_error = errors; clear_d1;
        send_frame(0, 1, 70, 32'hAAAA0070); take_snapshot; read_expect(8'h10, 1);
        send_frame(1, 1, 71, 32'hBBBB0071); read_expect(8'h10, 1);
        take_snapshot; read_expect(8'h10, 2);
        if (errors == start_error) $display("TC-M6A-I-07 PASS: snapshot isolated from changing M5 counters"); else $display("TC-M6A-I-07 FAIL");

        start_error = errors; fault_applied_event = 1; @(posedge clk); #1; @(negedge clk); fault_applied_event = 0;
        clear_events; send_frame(1, 1, 71, 32'hBBBB0071);
        if (accepted_count !== 2 || duplicate_count !== 1 || same_network_repeat_count !== 1) begin
            $display("ERROR: management clear modified D1 state"); errors = errors + 1;
        end
        take_snapshot; read_expect(8'h04, 0); read_expect(8'h10, 2); read_expect(8'h13, 1); read_expect(8'h15, 1);
        if (errors == start_error) $display("TC-M6A-I-08 PASS: M5 state unaffected by management"); else $display("TC-M6A-I-08 FAIL");

        if (errors == 0) begin
            $display("==============================================");
            $display("M6A-INTEGRATION ALL TESTS PASS");
            $display("M6A-I-01 .. M6A-I-08 PASS");
            $display("==============================================");
        end else $fatal(1, "M6A integration failed: %0d error(s)", errors);
        #50 $finish;
    end

    initial begin
        #500000 $fatal(1, "M6A integration global timeout");
    end
endmodule
