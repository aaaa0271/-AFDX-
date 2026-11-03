`timescale 1ns / 1ps

module afdx_management_telemetry #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Management control
    // ========================================================

    // One-cycle request.
    // All management-visible values are captured atomically
    // on this request.
    input  wire        snapshot_req,

    // One-cycle acknowledgement.
    output reg         snapshot_ack,

    // At least one valid snapshot has been captured.
    output reg         snapshot_valid,

    // Monotonically increments for every snapshot.
    output reg [31:0]  snapshot_id,

    // Clear M6A event latches only.
    // This MUST NOT clear M5 statistics/history.
    input  wire        event_clear,

    // ========================================================
    // Management read interface
    // ========================================================

    input  wire [7:0]  rd_addr,
    output reg  [31:0] rd_data,
    output reg         rd_valid,

    // ========================================================
    // Live status from frozen M5
    // ========================================================

    input  wire        network_a_enable,
    input  wire        network_b_enable,
    input  wire        degraded_mode,

    input  wire        redundancy_ok,
    input  wire        frame_count_match,
    input  wire        active_byte_count_match,

    // ========================================================
    // Live one-cycle events from frozen M5
    // ========================================================

    input  wire        redundancy_fault_event,
    input  wire        fault_applied_event,

    // ========================================================
    // RX redundancy statistics from M5-D1
    // ========================================================

    input  wire [31:0] rx_accepted_count,
    input  wire [31:0] rx_accepted_a_count,
    input  wire [31:0] rx_accepted_b_count,

    input  wire [31:0] rx_duplicate_count,
    input  wire [31:0] rx_cross_network_duplicate_count,
    input  wire [31:0] rx_same_network_repeat_count,

    input  wire [31:0] rx_stale_count,
    input  wire [31:0] rx_sequence_gap_count,

    // ========================================================
    // TX redundancy integrity statistics
    // ========================================================

    input  wire [31:0] tx_a_frame_count,
    input  wire [31:0] tx_b_frame_count,

    input  wire [31:0] tx_a_active_byte_count,
    input  wire [31:0] tx_b_active_byte_count,

    input  wire [31:0] tx_byte_mismatch_count,
    input  wire [31:0] tx_frame_skew_cycle_count,
    input  wire [31:0] tx_frame_done_skew_count,
    input  wire [31:0] tx_er_mismatch_count,

    input  wire [31:0] tx_a_error_cycle_count,
    input  wire [31:0] tx_b_error_cycle_count,

    input  wire [31:0] tx_a_underrun_count,
    input  wire [31:0] tx_b_underrun_count
);


    // ========================================================
    // M6A version
    // ========================================================

    localparam [31:0] M6A_VERSION = 32'h0006_0A01;


    // ========================================================
    // Management uptime
    //
    // SNMP sysUpTime uses 1/100 second units.
    // Therefore one tick = 10 ms.
    // ========================================================

    localparam integer TICKS_PER_10MS = CLK_HZ / 100;

    reg [31:0] uptime_divider;
    reg [31:0] uptime_ticks;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            uptime_divider <= 32'd0;
            uptime_ticks   <= 32'd0;

        end
        else begin

            if (uptime_divider == TICKS_PER_10MS - 1) begin

                uptime_divider <= 32'd0;
                uptime_ticks   <= uptime_ticks + 32'd1;

            end
            else begin

                uptime_divider <= uptime_divider + 32'd1;

            end

        end

    end


    // ========================================================
    // Sticky management event latch
    //
    // M6A is allowed to remember management events.
    // It does NOT modify M5.
    //
    // bit 0 = redundancy fault observed
    // bit 1 = fault injection applied
    // ========================================================

    reg [31:0] event_flags_live;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            event_flags_live <= 32'd0;

        end
        else begin

            if (event_clear)
                event_flags_live <= 32'd0;

            // Event SET has priority over clear.
            if (redundancy_fault_event)
                event_flags_live[0] <= 1'b1;

            if (fault_applied_event)
                event_flags_live[1] <= 1'b1;

        end

    end


    // ========================================================
    // Snapshot registers
    // ========================================================

    reg [31:0] snap_uptime_ticks;
    reg [31:0] snap_system_status;
    reg [31:0] snap_event_flags;

    reg [31:0] snap_rx_accepted_count;
    reg [31:0] snap_rx_accepted_a_count;
    reg [31:0] snap_rx_accepted_b_count;

    reg [31:0] snap_rx_duplicate_count;
    reg [31:0] snap_rx_cross_network_duplicate_count;
    reg [31:0] snap_rx_same_network_repeat_count;

    reg [31:0] snap_rx_stale_count;
    reg [31:0] snap_rx_sequence_gap_count;

    reg [31:0] snap_tx_a_frame_count;
    reg [31:0] snap_tx_b_frame_count;

    reg [31:0] snap_tx_a_active_byte_count;
    reg [31:0] snap_tx_b_active_byte_count;

    reg [31:0] snap_tx_byte_mismatch_count;
    reg [31:0] snap_tx_frame_skew_cycle_count;
    reg [31:0] snap_tx_frame_done_skew_count;
    reg [31:0] snap_tx_er_mismatch_count;

    reg [31:0] snap_tx_a_error_cycle_count;
    reg [31:0] snap_tx_b_error_cycle_count;

    reg [31:0] snap_tx_a_underrun_count;
    reg [31:0] snap_tx_b_underrun_count;


    // ========================================================
    // Atomic snapshot
    //
    // Every register below is captured on exactly the same
    // rising clock edge.
    //
    // This is critical:
    //
    // SNMP may read registers over many cycles.
    // Without a snapshot, counters could change between reads
    // and the manager would observe an inconsistent state.
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            snapshot_ack   <= 1'b0;
            snapshot_valid <= 1'b0;
            snapshot_id    <= 32'd0;

            snap_uptime_ticks  <= 32'd0;
            snap_system_status <= 32'd0;
            snap_event_flags   <= 32'd0;

            snap_rx_accepted_count                <= 32'd0;
            snap_rx_accepted_a_count              <= 32'd0;
            snap_rx_accepted_b_count              <= 32'd0;

            snap_rx_duplicate_count               <= 32'd0;
            snap_rx_cross_network_duplicate_count <= 32'd0;
            snap_rx_same_network_repeat_count     <= 32'd0;

            snap_rx_stale_count                   <= 32'd0;
            snap_rx_sequence_gap_count            <= 32'd0;

            snap_tx_a_frame_count                 <= 32'd0;
            snap_tx_b_frame_count                 <= 32'd0;

            snap_tx_a_active_byte_count           <= 32'd0;
            snap_tx_b_active_byte_count           <= 32'd0;

            snap_tx_byte_mismatch_count           <= 32'd0;
            snap_tx_frame_skew_cycle_count        <= 32'd0;
            snap_tx_frame_done_skew_count         <= 32'd0;
            snap_tx_er_mismatch_count             <= 32'd0;

            snap_tx_a_error_cycle_count           <= 32'd0;
            snap_tx_b_error_cycle_count           <= 32'd0;

            snap_tx_a_underrun_count              <= 32'd0;
            snap_tx_b_underrun_count              <= 32'd0;

        end
        else begin

            snapshot_ack <= 1'b0;

            if (snapshot_req) begin

                snapshot_ack   <= 1'b1;
                snapshot_valid <= 1'b1;
                snapshot_id    <= snapshot_id + 32'd1;

                snap_uptime_ticks <= uptime_ticks;

                snap_system_status <= {
                    26'd0,
                    active_byte_count_match,
                    frame_count_match,
                    redundancy_ok,
                    degraded_mode,
                    network_b_enable,
                    network_a_enable
                };

                snap_event_flags <= event_flags_live;

                // RX
                snap_rx_accepted_count
                    <= rx_accepted_count;

                snap_rx_accepted_a_count
                    <= rx_accepted_a_count;

                snap_rx_accepted_b_count
                    <= rx_accepted_b_count;

                snap_rx_duplicate_count
                    <= rx_duplicate_count;

                snap_rx_cross_network_duplicate_count
                    <= rx_cross_network_duplicate_count;

                snap_rx_same_network_repeat_count
                    <= rx_same_network_repeat_count;

                snap_rx_stale_count
                    <= rx_stale_count;

                snap_rx_sequence_gap_count
                    <= rx_sequence_gap_count;

                // TX
                snap_tx_a_frame_count
                    <= tx_a_frame_count;

                snap_tx_b_frame_count
                    <= tx_b_frame_count;

                snap_tx_a_active_byte_count
                    <= tx_a_active_byte_count;

                snap_tx_b_active_byte_count
                    <= tx_b_active_byte_count;

                snap_tx_byte_mismatch_count
                    <= tx_byte_mismatch_count;

                snap_tx_frame_skew_cycle_count
                    <= tx_frame_skew_cycle_count;

                snap_tx_frame_done_skew_count
                    <= tx_frame_done_skew_count;

                snap_tx_er_mismatch_count
                    <= tx_er_mismatch_count;

                snap_tx_a_error_cycle_count
                    <= tx_a_error_cycle_count;

                snap_tx_b_error_cycle_count
                    <= tx_b_error_cycle_count;

                snap_tx_a_underrun_count
                    <= tx_a_underrun_count;

                snap_tx_b_underrun_count
                    <= tx_b_underrun_count;

            end

        end

    end


    // ========================================================
    // Snapshot read mux
    //
    // IMPORTANT:
    // This interface exposes SNAPSHOT data, not live data.
    // ========================================================

    always @(*) begin

        rd_data  = 32'd0;
        rd_valid = snapshot_valid;

        case (rd_addr)

            // ------------------------------------------------
            // System
            // ------------------------------------------------

            8'h00:
                rd_data = M6A_VERSION;

            8'h01:
                rd_data = snapshot_id;

            8'h02:
                rd_data = snap_uptime_ticks;

            8'h03:
                rd_data = snap_system_status;

            8'h04:
                rd_data = snap_event_flags;


            // ------------------------------------------------
            // RX redundancy
            // ------------------------------------------------

            8'h10:
                rd_data = snap_rx_accepted_count;

            8'h11:
                rd_data = snap_rx_accepted_a_count;

            8'h12:
                rd_data = snap_rx_accepted_b_count;

            8'h13:
                rd_data = snap_rx_duplicate_count;

            8'h14:
                rd_data =
                    snap_rx_cross_network_duplicate_count;

            8'h15:
                rd_data =
                    snap_rx_same_network_repeat_count;

            8'h16:
                rd_data = snap_rx_stale_count;

            8'h17:
                rd_data = snap_rx_sequence_gap_count;


            // ------------------------------------------------
            // TX redundancy integrity
            // ------------------------------------------------

            8'h20:
                rd_data = snap_tx_a_frame_count;

            8'h21:
                rd_data = snap_tx_b_frame_count;

            8'h22:
                rd_data = snap_tx_a_active_byte_count;

            8'h23:
                rd_data = snap_tx_b_active_byte_count;

            8'h24:
                rd_data = snap_tx_byte_mismatch_count;

            8'h25:
                rd_data = snap_tx_frame_skew_cycle_count;

            8'h26:
                rd_data = snap_tx_frame_done_skew_count;

            8'h27:
                rd_data = snap_tx_er_mismatch_count;

            8'h28:
                rd_data = snap_tx_a_error_cycle_count;

            8'h29:
                rd_data = snap_tx_b_error_cycle_count;

            8'h2A:
                rd_data = snap_tx_a_underrun_count;

            8'h2B:
                rd_data = snap_tx_b_underrun_count;


            default: begin

                rd_data  = 32'd0;
                rd_valid = 1'b0;

            end

        endcase

    end


endmodule
