`timescale 1ns / 1ps

module afdx_rx_redundancy_eliminator #(
    // Integration must configure this for its clock and maximum VL silence.
    // 0 disables idle recovery; default is 160 ms at 100 MHz.
    parameter integer HISTORY_TIMEOUT_CYCLES = 16_000_000,
    parameter integer SKEW_MAX0 = HISTORY_TIMEOUT_CYCLES,
    parameter integer SKEW_MAX1 = HISTORY_TIMEOUT_CYCLES,
    parameter integer SKEW_MAX2 = HISTORY_TIMEOUT_CYCLES,
    parameter integer SKEW_MAX3 = HISTORY_TIMEOUT_CYCLES,
    parameter [3:0] IC_ENABLE = 4'hf,
    parameter [3:0] RM_ENABLE = 4'hf
) (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Clear all RX sequence/history/statistics state
    // ========================================================

    input  wire        clear,

    // ========================================================
    // Parsed physical RX frame
    //
    // rx_network:
    //   0 = Network A
    //   1 = Network B
    // ========================================================

    input  wire        rx_valid,
    output wire        rx_ready,

    input  wire        rx_network,
    input  wire [1:0]  rx_vl_id,
    input  wire [7:0]  rx_seq,
    input  wire [31:0] rx_payload,

    // ========================================================
    // Eliminated logical RX frame
    //
    // Only the first valid copy of a new sequence reaches here.
    // ========================================================

    output reg         out_valid,
    input  wire        out_ready,

    output reg  [1:0]  out_vl_id,
    output reg  [7:0]  out_seq,
    output reg  [31:0] out_payload,
    output reg         out_network,

    // ========================================================
    // One-cycle event pulses
    // ========================================================

    output reg         accept_event,
    output reg         duplicate_event,
    output reg         stale_event,
    output reg         gap_event,

    // ========================================================
    // Statistics
    // ========================================================

    output reg  [31:0] accepted_count,

    output reg  [31:0] accepted_a_count,
    output reg  [31:0] accepted_b_count,

    output reg  [31:0] duplicate_count,

    output reg  [31:0] cross_network_duplicate_count,
    output reg  [31:0] same_network_repeat_count,

    output reg  [31:0] stale_count,

    output reg  [31:0] sequence_gap_count,

    // ========================================================
    // Per-VL debug
    // ========================================================

    output wire        last_valid0_dbg,
    output wire        last_valid1_dbg,
    output wire        last_valid2_dbg,
    output wire        last_valid3_dbg,

    output wire [7:0]  last_seq0_dbg,
    output wire [7:0]  last_seq1_dbg,
    output wire [7:0]  last_seq2_dbg,
    output wire [7:0]  last_seq3_dbg,

    output wire [1:0]  seen_mask0_dbg,
    output wire [1:0]  seen_mask1_dbg,
    output wire [1:0]  seen_mask2_dbg,
    output wire [1:0]  seen_mask3_dbg
);
    reg [7:0] psn [0:7];
    reg [7:0] psn_valid;
    reg [7:0] last_seq [0:3];
    reg [3:0] last_valid;
    reg [1:0] seen_mask [0:3];
    reg [31:0] logical_age [0:3];
    reg [1:0] reset_seen [0:3];
    reg [3:0] reset_epoch_valid;
    reg [31:0] reset_age [0:3];
    wire [2:0] channel = {rx_vl_id, rx_network};
    function [31:0] skew_limit;
        input [1:0] vl;
        begin case(vl)
            0:skew_limit=SKEW_MAX0;1:skew_limit=SKEW_MAX1;
            2:skew_limit=SKEW_MAX2;3:skew_limit=SKEW_MAX3;
        endcase end
    endfunction
    wire logical_expired = skew_limit(rx_vl_id)!=0 &&
                           logical_age[rx_vl_id]>=skew_limit(rx_vl_id)-1;
    wire epoch_expired = skew_limit(rx_vl_id)!=0 &&
                         reset_age[rx_vl_id]>=skew_limit(rx_vl_id)-1;
    function [7:0] seq_next;
        input [7:0] sn;
        begin seq_next = sn==255 ? 8'd1 : sn+8'd1; end
    endfunction
    // Distance in the non-zero ring, not modulo 256. The transition from
    // reset marker 0 to 1 is also one step; a received zero is handled first.
    function [7:0] seq_distance;
        input [7:0] prev, sn;
        begin
            if(sn>=prev) seq_distance=sn-prev;
            else seq_distance=8'd255-prev+sn;
        end
    endfunction
    wire ic_first = !psn_valid[channel] || logical_expired;
    wire ic_accept = !IC_ENABLE[rx_vl_id] || ic_first || rx_seq==0 ||
                     rx_seq==seq_next(psn[channel]) ||
                     rx_seq==seq_next(seq_next(psn[channel]));
    wire ic_repeat = !ic_first && rx_seq!=0 && rx_seq==psn[channel];
    wire [7:0] delta = seq_distance(last_seq[rx_vl_id], rx_seq);
    wire logical_first = !last_valid[rx_vl_id] || logical_expired;
    wire late_reset_copy = reset_epoch_valid[rx_vl_id] && !epoch_expired &&
                           !reset_seen[rx_vl_id][rx_network];
    // Secondary late-reset criterion: when the SN=0 reset marker was lost on
    // BOTH physical paths, the logical channel has already accepted a
    // non-zero SN from one network and a zero then arrives from the OTHER
    // (never-seen) network, it is an orphaned reset copy rather than a new
    // epoch. Accepting it would roll the logical history back to 0 and let
    // the following SN=1 be delivered a second time. A zero emitted by the
    // network that already owns the logical stream stays a legitimate
    // transmitter reset and is accepted below. The last_seq==255 exception
    // preserves the legal 255->0 sequence wrap (see TC-M5-D2c3-07).
    wire late_reset_orphan = !reset_epoch_valid[rx_vl_id] && !logical_first &&
                             last_valid[rx_vl_id] && last_seq[rx_vl_id]!=8'd0 &&
                             last_seq[rx_vl_id]!=8'd255 &&
                             !seen_mask[rx_vl_id][rx_network];
    reg take,duplicate,stale,gap,cross_copy,same_repeat;
    always @* begin
        take=0;duplicate=0;stale=0;gap=0;cross_copy=0;same_repeat=0;
        // Integrity always precedes redundancy removal. Rejected frames still
        // advance the *physical* PSN, allowing the next consecutive SN to recover.
        if(!ic_accept) begin
            if(ic_repeat && !logical_first && rx_seq==last_seq[rx_vl_id]) begin duplicate=1;same_repeat=1;end
            else stale=1;
        end else if(!RM_ENABLE[rx_vl_id] || logical_first) take=1;
        else if(rx_seq==last_seq[rx_vl_id]) begin
            duplicate=1;
            same_repeat=seen_mask[rx_vl_id][rx_network];
            cross_copy=!same_repeat;
        end else if(rx_seq==0) begin
            // Delayed B reset copy after A has already sent sequence 1 must
            // not roll the logical history back or replay the reset payload.
            if(late_reset_copy) begin duplicate=1;cross_copy=1;end
            else if(late_reset_orphan) begin
                duplicate=1;
                same_repeat=seen_mask[rx_vl_id][rx_network];
                cross_copy=!same_repeat;
            end
            else take=1;
        end else if(delta>=128) stale=1;
        else begin take=1;gap=delta>1;end
    end
    assign rx_ready = rst_n && !clear && (!take || !out_valid || out_ready);
    wire fire = rx_valid && rx_ready;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            psn_valid<=0;last_valid<=0;reset_epoch_valid<=0;
            out_valid<=0;out_vl_id<=0;out_seq<=0;out_payload<=0;out_network<=0;
            accept_event<=0;duplicate_event<=0;stale_event<=0;gap_event<=0;
            accepted_count<=0;accepted_a_count<=0;accepted_b_count<=0;
            duplicate_count<=0;cross_network_duplicate_count<=0;same_network_repeat_count<=0;
            stale_count<=0;sequence_gap_count<=0;
            for(i=0;i<8;i=i+1) begin psn[i]<=0;end
            for(i=0;i<4;i=i+1) begin
                last_seq[i]<=0;seen_mask[i]<=0;logical_age[i]<=0;reset_seen[i]<=0;reset_age[i]<=0;
            end
        end else if(clear) begin
            psn_valid<=0;last_valid<=0;reset_epoch_valid<=0;
            out_valid<=0;out_vl_id<=0;out_seq<=0;out_payload<=0;out_network<=0;
            accept_event<=0;duplicate_event<=0;stale_event<=0;gap_event<=0;
            accepted_count<=0;accepted_a_count<=0;accepted_b_count<=0;
            duplicate_count<=0;cross_network_duplicate_count<=0;same_network_repeat_count<=0;
            stale_count<=0;sequence_gap_count<=0;
            for(i=0;i<8;i=i+1) begin psn[i]<=0;end
            for(i=0;i<4;i=i+1) begin
                last_seq[i]<=0;seen_mask[i]<=0;logical_age[i]<=0;reset_seen[i]<=0;reset_age[i]<=0;
            end
        end else begin
            accept_event<=0;duplicate_event<=0;stale_event<=0;gap_event<=0;
            if(out_valid && out_ready) out_valid<=0;
            for(i=0;i<4;i=i+1) if(skew_limit(i)!=0) begin
                if(logical_age[i]<skew_limit(i)) logical_age[i]<=logical_age[i]+1'b1;
                if(reset_age[i]<skew_limit(i)) reset_age[i]<=reset_age[i]+1'b1;
                // Per-VL SkewMax expiry resets BOTH physical IC histories.
                // Invalid sequences do not refresh the valid-frame timer.
                if(logical_age[i]>=skew_limit(i)-1) begin
                    psn_valid[i*2+:2]<=0;last_valid[i]<=0;reset_epoch_valid[i]<=0;
                end
            end
            if(fire) begin
                psn[channel]<=rx_seq;psn_valid[channel]<=1;
                if(ic_accept) logical_age[rx_vl_id]<=0;
                if(take) begin
                    out_valid<=1;out_vl_id<=rx_vl_id;out_seq<=rx_seq;out_payload<=rx_payload;out_network<=rx_network;
                    accept_event<=1;accepted_count<=accepted_count+1'b1;
                    if(rx_network) accepted_b_count<=accepted_b_count+1'b1;
                    else accepted_a_count<=accepted_a_count+1'b1;
                    if(gap) begin gap_event<=1;sequence_gap_count<=sequence_gap_count+{24'd0,delta}-32'd1;end
                    last_valid[rx_vl_id]<=1;last_seq[rx_vl_id]<=rx_seq;
                    seen_mask[rx_vl_id]<=rx_network?2'b10:2'b01;logical_age[rx_vl_id]<=0;
                    if(rx_seq==0) begin
                        reset_epoch_valid[rx_vl_id]<=1;
                        reset_seen[rx_vl_id]<=rx_network?2'b10:2'b01;reset_age[rx_vl_id]<=0;
                    end
                end else if(duplicate) begin
                    duplicate_event<=1;duplicate_count<=duplicate_count+1'b1;
                    if(cross_copy) cross_network_duplicate_count<=cross_network_duplicate_count+1'b1;
                    if(same_repeat) same_network_repeat_count<=same_network_repeat_count+1'b1;
                    if(rx_seq==last_seq[rx_vl_id]) seen_mask[rx_vl_id][rx_network]<=1;
                    if(rx_seq==0) reset_seen[rx_vl_id][rx_network]<=1;
                end else begin stale_event<=1;stale_count<=stale_count+1'b1;end
            end
        end
    end
    assign last_valid0_dbg=last_valid[0];
    assign last_seq0_dbg=last_seq[0];
    assign seen_mask0_dbg=seen_mask[0];
    assign last_valid1_dbg=last_valid[1];
    assign last_seq1_dbg=last_seq[1];
    assign seen_mask1_dbg=seen_mask[1];
    assign last_valid2_dbg=last_valid[2];
    assign last_seq2_dbg=last_seq[2];
    assign seen_mask2_dbg=seen_mask[2];
    assign last_valid3_dbg=last_valid[3];
    assign last_seq3_dbg=last_seq[3];
    assign seen_mask3_dbg=seen_mask[3];
endmodule
