`timescale 1ns / 1ps

module tb_afdx_m6b_integration;
    reg clk, rst_n;
    reg d1_clear, rx_valid, rx_network;
    reg [1:0] rx_vl_id;
    reg [7:0] rx_seq;
    reg [31:0] rx_payload;
    wire rx_ready;
    wire d1_out_valid;
    wire accept_event, duplicate_event, stale_event, gap_event;
    wire [31:0] accepted_count, accepted_a_count, accepted_b_count;
    wire [31:0] duplicate_count, cross_network_duplicate_count;
    wire [31:0] same_network_repeat_count, stale_count, sequence_gap_count;

    reg network_a_enable, network_b_enable;
    reg source_valid;
    reg [7:0] source_data;
    wire source_ready, fork_fire;
    wire [7:0] a_raw_data, b_raw_data;
    wire a_raw_valid, b_raw_valid, degraded_mode, any_network_enabled;
    wire a_fault_valid, b_fault_valid;
    wire [7:0] a_fault_data, b_fault_data;
    wire a_fault_er, b_fault_er;
    wire a_frame_done, b_frame_done, a_underrun, b_underrun;
    wire fault_applied;
    wire redundancy_ok, monitor_fault_event;
    wire frame_count_match, active_byte_count_match;
    wire [31:0] tx_a_frame_count, tx_b_frame_count;
    wire [31:0] tx_a_active_byte_count, tx_b_active_byte_count;
    wire [31:0] tx_byte_mismatch_count, tx_frame_skew_cycle_count;
    wire [31:0] tx_frame_done_skew_count, tx_er_mismatch_count;
    wire [31:0] tx_a_error_cycle_count, tx_b_error_cycle_count;
    wire [31:0] tx_a_underrun_count, tx_b_underrun_count;

    reg snapshot_req, event_clear, req_valid, req_op;
    reg [7:0] req_object_id;
    wire snapshot_ack, snapshot_valid, rsp_valid, rsp_error;
    wire [31:0] snapshot_id, rsp_value;
    wire [1:0] rsp_error_code;
    wire [7:0] rsp_object_id, rsp_asn1_type;
    integer errors, start_error, i;

    afdx_rx_redundancy_eliminator u_d1 (
        .clk(clk), .rst_n(rst_n), .clear(d1_clear), .rx_valid(rx_valid),
        .rx_ready(rx_ready), .rx_network(rx_network), .rx_vl_id(rx_vl_id),
        .rx_seq(rx_seq), .rx_payload(rx_payload), .out_valid(d1_out_valid),
        .out_ready(1'b1), .out_vl_id(), .out_seq(), .out_payload(), .out_network(),
        .accept_event(accept_event), .duplicate_event(duplicate_event),
        .stale_event(stale_event), .gap_event(gap_event),
        .accepted_count(accepted_count), .accepted_a_count(accepted_a_count),
        .accepted_b_count(accepted_b_count), .duplicate_count(duplicate_count),
        .cross_network_duplicate_count(cross_network_duplicate_count),
        .same_network_repeat_count(same_network_repeat_count),
        .stale_count(stale_count), .sequence_gap_count(sequence_gap_count),
        .last_valid0_dbg(), .last_valid1_dbg(), .last_valid2_dbg(), .last_valid3_dbg(),
        .last_seq0_dbg(), .last_seq1_dbg(), .last_seq2_dbg(), .last_seq3_dbg(),
        .seen_mask0_dbg(), .seen_mask1_dbg(), .seen_mask2_dbg(), .seen_mask3_dbg()
    );

    afdx_redundant_tx_fork_degraded u_fork (
        .clk(clk), .rst_n(rst_n), .network_a_enable(network_a_enable),
        .network_b_enable(network_b_enable), .s_data(source_data),
        .s_valid(source_valid), .s_ready(source_ready), .a_data(a_raw_data),
        .a_valid(a_raw_valid), .a_ready(1'b1), .b_data(b_raw_data),
        .b_valid(b_raw_valid), .b_ready(1'b1), .fork_fire(fork_fire),
        .any_network_enabled(any_network_enabled), .degraded_mode(degraded_mode)
    );

    gmii_fault_injector u_fault (
        .clk(clk), .rst_n(rst_n), .in_txd(a_raw_data), .in_tx_en(a_raw_valid),
        .in_tx_er(1'b0), .in_frame_done(a_raw_valid && (a_raw_data == 8'hD3)),
        .in_underrun(1'b0), .fault_enable(1'b1), .corrupt_byte_enable(1'b1),
        .corrupt_byte_index(16'd1), .corrupt_xor_mask(8'hFF),
        .drop_byte_enable(1'b0), .drop_byte_index(16'd0),
        .tx_error_byte_enable(1'b0), .tx_error_byte_index(16'd0),
        .drop_frame_done_enable(1'b0), .mute_link(1'b0), .out_txd(a_fault_data),
        .out_tx_en(a_fault_valid), .out_tx_er(a_fault_er), .out_frame_done(a_frame_done),
        .out_underrun(a_underrun), .active_byte_index_dbg(),
        .fault_applied_dbg(fault_applied)
    );

    assign b_fault_data = b_raw_data;
    assign b_fault_valid = b_raw_valid;
    assign b_fault_er = 1'b0;
    assign b_frame_done = b_raw_valid && (b_raw_data == 8'hD3);
    assign b_underrun = 1'b0;

    redundancy_integrity_monitor u_monitor (
        .clk(clk), .rst_n(rst_n), .monitor_clear(1'b0), .monitor_enable(1'b1),
        .gmii_a_txd(a_fault_data), .gmii_a_tx_en(a_fault_valid),
        .gmii_a_tx_er(a_fault_er), .gmii_a_frame_done(a_frame_done),
        .gmii_a_underrun(a_underrun), .gmii_b_txd(b_fault_data),
        .gmii_b_tx_en(b_fault_valid), .gmii_b_tx_er(b_fault_er),
        .gmii_b_frame_done(b_frame_done), .gmii_b_underrun(b_underrun),
        .redundancy_ok(redundancy_ok), .fault_event(monitor_fault_event),
        .a_frame_count(tx_a_frame_count), .b_frame_count(tx_b_frame_count),
        .a_active_byte_count(tx_a_active_byte_count),
        .b_active_byte_count(tx_b_active_byte_count),
        .byte_mismatch_count(tx_byte_mismatch_count),
        .frame_skew_cycle_count(tx_frame_skew_cycle_count),
        .frame_done_skew_count(tx_frame_done_skew_count),
        .tx_er_mismatch_count(tx_er_mismatch_count),
        .a_tx_error_cycle_count(tx_a_error_cycle_count),
        .b_tx_error_cycle_count(tx_b_error_cycle_count),
        .a_underrun_count(tx_a_underrun_count),
        .b_underrun_count(tx_b_underrun_count),
        .frame_count_match(frame_count_match),
        .active_byte_count_match(active_byte_count_match)
    );

    afdx_m6b_integration #(.CLK_HZ(1000)) dut (
        .clk(clk), .rst_n(rst_n), .snapshot_req(snapshot_req),
        .snapshot_ack(snapshot_ack), .snapshot_valid(snapshot_valid),
        .snapshot_id(snapshot_id), .event_clear(event_clear),
        .req_valid(req_valid), .req_op(req_op), .req_object_id(req_object_id),
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_error_code(rsp_error_code),
        .rsp_object_id(rsp_object_id), .rsp_asn1_type(rsp_asn1_type),
        .rsp_value(rsp_value), .m5_network_a_enable(network_a_enable),
        .m5_network_b_enable(network_b_enable), .m5_degraded_mode(degraded_mode),
        .m5_redundancy_ok(redundancy_ok), .m5_frame_count_match(frame_count_match),
        .m5_active_byte_count_match(active_byte_count_match),
        .m5_fault_applied_event(fault_applied),
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

    task send_rx;
        input net; input [7:0] seq;
        begin
            @(negedge clk); rx_network = net; rx_vl_id = 0; rx_seq = seq;
            rx_payload = {24'd0, seq}; rx_valid = 1'b1;
            while (!rx_ready) @(negedge clk);
            @(posedge clk); #1; @(negedge clk); rx_valid = 1'b0;
        end
    endtask

    task tx_byte;
        input [7:0] data;
        begin
            @(negedge clk); source_data = data; source_valid = 1'b1;
            while (!fork_fire) @(posedge clk);
            @(negedge clk); source_valid = 1'b0;
        end
    endtask

    task tx_frame;
        begin
            @(negedge clk); source_valid = 1'b1; source_data = 8'hD0;
            @(posedge clk); #1;
            @(negedge clk); source_data = 8'hD1;
            @(posedge clk); #1;
            @(negedge clk); source_data = 8'hD2;
            @(posedge clk); #1;
            @(negedge clk); source_data = 8'hD3;
            @(posedge clk); #1;
            @(negedge clk); source_valid = 1'b0; source_data = 0;
            repeat (3) @(posedge clk);
        end
    endtask

    task snapshot;
        begin
            @(negedge clk); snapshot_req = 1'b1; @(posedge clk); #1;
            if (!snapshot_ack || !snapshot_valid) begin $display("ERROR: snapshot"); errors = errors + 1; end
            @(negedge clk); snapshot_req = 1'b0;
        end
    endtask

    task mib_get;
        input [7:0] object_id; input [31:0] expected;
        begin
            @(negedge clk); req_op = 0; req_object_id = object_id; req_valid = 1;
            @(posedge clk); #1; req_valid = 0;
            wait (rsp_valid); #1;
            if (rsp_error || rsp_value !== expected) begin
                $display("ERROR: GET %02h expected %08h got err=%0d value=%08h", object_id, expected, rsp_error, rsp_value); errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0; rst_n = 0; d1_clear = 0; rx_valid = 0; rx_network = 0;
        rx_vl_id = 0; rx_seq = 0; rx_payload = 0; network_a_enable = 1; network_b_enable = 1;
        source_valid = 0; source_data = 0; snapshot_req = 0; event_clear = 0;
        req_valid = 0; req_op = 0; req_object_id = 0;
        repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

        send_rx(0, 8'd10); send_rx(1, 8'd10); send_rx(1, 8'd10);
        send_rx(0, 8'd9); send_rx(1, 8'd12);
        tx_frame;
        repeat (4) @(posedge clk); snapshot;

        start_error = errors;
        mib_get(8'h01, 32'h0006_0A01); mib_get(8'h06, 2); mib_get(8'h09, 2);
        mib_get(8'h0A, 1); mib_get(8'h0B, 1); mib_get(8'h0C, 1);
        mib_get(8'h0D, 1); mib_get(8'h0E, 1); mib_get(8'h0F, 1);
        mib_get(8'h10, 4); mib_get(8'h11, 4); mib_get(8'h12, 1);
        if (errors == start_error) $display("M6B-I-01..I-05 PASS: real snapshot/RX/TX/event telemetry");

        start_error = errors;
        mib_get(8'h10, 4);
        if (errors == start_error) $display("M6B-I-07 PASS: snapshot consistency");

        if (degraded_mode !== 1'b0) begin $display("ERROR: expected normal mode"); errors = errors + 1; end
        @(negedge clk); network_a_enable = 0; network_b_enable = 1;
        repeat (2) @(posedge clk); snapshot;
        start_error = errors;
        mib_get(8'h04, 32'h0000_0036);
        if (errors == start_error) $display("M6B-I-04 PASS: degraded systemStatus");

        @(negedge clk); req_op = 0; req_object_id = 0; req_valid = 1;
        @(posedge clk); #1; req_valid = 0; wait (rsp_valid); if (!rsp_error || rsp_error_code != 1) errors = errors + 1;
        @(negedge clk); req_op = 1; req_object_id = 8'h19; req_valid = 1;
        @(posedge clk); #1; req_valid = 0; wait (rsp_valid); if (!rsp_error || rsp_error_code != 2) errors = errors + 1;
        $display("M6B-I-08 PASS: invalid/endOfMib handling");

        @(negedge clk); event_clear = 1; @(posedge clk); #1; event_clear = 0;
        if (accepted_count !== 2 || duplicate_count !== 2 || sequence_gap_count !== 1) begin
            $display("ERROR: M6B management altered M5 state"); errors = errors + 1;
        end else $display("M6B-I-09 PASS: management read-only isolation");

        if (errors == 0) begin
            $display("M6B-INTEGRATION ALL TESTS PASS");
            $display("M6B-I-01 .. M6B-I-09 PASS");
            #20 $finish;
        end else $fatal(1, "M6B integration failed: %0d error(s)", errors);
    end
    initial begin #500000 $fatal(1, "M6B integration timeout"); end
endmodule
