`timescale 1ns/1ps

module tb_afdx_frame_builder_varlen_cfg;

localparam integer MAX_SNMP_BYTES = 96;

reg clk;
reg rst;
reg start;
reg [7:0] seq_num;
reg [47:0] cfg_dst_mac;
reg [47:0] cfg_src_mac;
reg [31:0] cfg_src_ip;
reg [31:0] cfg_dst_ip;
reg [15:0] cfg_src_port;
reg [15:0] cfg_dst_port;
reg [7:0] payload_length;
reg [MAX_SNMP_BYTES*8-1:0] payload_bytes;
reg tx_ready;

wire [7:0] tx_data;
wire       tx_valid;
wire       tx_eof;
wire       busy;
wire       done;

integer cases;
integer frames;
integer fails;
integer i;

// Expected snapshot for the active frame.
reg [47:0] exp_dst_mac;
reg [47:0] exp_src_mac;
reg [31:0] exp_src_ip;
reg [31:0] exp_dst_ip;
reg [15:0] exp_src_port;
reg [15:0] exp_dst_port;
reg [7:0]  exp_payload_length;
reg [MAX_SNMP_BYTES*8-1:0] exp_payload_bytes;
reg [7:0]  exp_seq;


afdx_frame_builder_varlen_cfg #(
    .MAX_SNMP_BYTES(MAX_SNMP_BYTES)
) dut (
    .clk            (clk),
    .rst            (rst),
    .start          (start),
    .seq_num        (seq_num),
    .cfg_dst_mac    (cfg_dst_mac),
    .cfg_src_mac    (cfg_src_mac),
    .cfg_src_ip     (cfg_src_ip),
    .cfg_dst_ip     (cfg_dst_ip),
    .cfg_src_port   (cfg_src_port),
    .cfg_dst_port   (cfg_dst_port),
    .payload_length (payload_length),
    .payload_bytes  (payload_bytes),
    .tx_data        (tx_data),
    .tx_valid       (tx_valid),
    .tx_eof         (tx_eof),
    .tx_ready       (tx_ready),
    .busy           (busy),
    .done           (done)
);


// ------------------------------------------------------------
// Clock
// ------------------------------------------------------------

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end


// ------------------------------------------------------------
// Independent IPv4 checksum reference.
// ------------------------------------------------------------

function [15:0] ref_ipv4_checksum;
    input [31:0] src_ip;
    input [31:0] dst_ip;
    input [15:0] total_length;
    reg [31:0] sum;
    begin
        sum = 32'd0;
        sum = sum + 16'h4500;
        sum = sum + total_length;
        sum = sum + 16'h0000;
        sum = sum + 16'h0000;
        sum = sum + 16'h4011;
        sum = sum + 16'h0000;
        sum = sum + src_ip[31:16];
        sum = sum + src_ip[15:0];
        sum = sum + dst_ip[31:16];
        sum = sum + dst_ip[15:0];
        sum = (sum & 32'h0000FFFF) + (sum >> 16);
        sum = (sum & 32'h0000FFFF) + (sum >> 16);
        ref_ipv4_checksum = ~sum[15:0];
    end
endfunction


function integer ref_body_length;
    input integer n;
    begin
        if (n <= 17)
            ref_body_length = 60;
        else
            ref_body_length = 43 + n;
    end
endfunction


function integer ref_seq_index;
    input integer n;
    begin
        if (n <= 17)
            ref_seq_index = 59;
        else
            ref_seq_index = 42 + n;
    end
endfunction


function [7:0] ref_byte;
    input integer idx;
    integer pidx;
    reg [15:0] ip_total;
    reg [15:0] udp_len;
    reg [15:0] ip_csum;
    begin
        pidx = 0;
        ip_total = 16'd28 + exp_payload_length;
        udp_len  = 16'd8  + exp_payload_length;
        ip_csum  = ref_ipv4_checksum(
            exp_src_ip,
            exp_dst_ip,
            ip_total
        );

        case (idx)
            0:  ref_byte = exp_dst_mac[47:40];
            1:  ref_byte = exp_dst_mac[39:32];
            2:  ref_byte = exp_dst_mac[31:24];
            3:  ref_byte = exp_dst_mac[23:16];
            4:  ref_byte = exp_dst_mac[15:8];
            5:  ref_byte = exp_dst_mac[7:0];

            6:  ref_byte = exp_src_mac[47:40];
            7:  ref_byte = exp_src_mac[39:32];
            8:  ref_byte = exp_src_mac[31:24];
            9:  ref_byte = exp_src_mac[23:16];
            10: ref_byte = exp_src_mac[15:8];
            11: ref_byte = exp_src_mac[7:0];

            12: ref_byte = 8'h08;
            13: ref_byte = 8'h00;

            14: ref_byte = 8'h45;
            15: ref_byte = 8'h00;
            16: ref_byte = ip_total[15:8];
            17: ref_byte = ip_total[7:0];
            18: ref_byte = 8'h00;
            19: ref_byte = 8'h00;
            20: ref_byte = 8'h00;
            21: ref_byte = 8'h00;
            22: ref_byte = 8'h40;
            23: ref_byte = 8'h11;
            24: ref_byte = ip_csum[15:8];
            25: ref_byte = ip_csum[7:0];

            26: ref_byte = exp_src_ip[31:24];
            27: ref_byte = exp_src_ip[23:16];
            28: ref_byte = exp_src_ip[15:8];
            29: ref_byte = exp_src_ip[7:0];

            30: ref_byte = exp_dst_ip[31:24];
            31: ref_byte = exp_dst_ip[23:16];
            32: ref_byte = exp_dst_ip[15:8];
            33: ref_byte = exp_dst_ip[7:0];

            34: ref_byte = exp_src_port[15:8];
            35: ref_byte = exp_src_port[7:0];

            36: ref_byte = exp_dst_port[15:8];
            37: ref_byte = exp_dst_port[7:0];

            38: ref_byte = udp_len[15:8];
            39: ref_byte = udp_len[7:0];

            40: ref_byte = 8'h00;
            41: ref_byte = 8'h00;

            default: begin

                if ((idx >= 42) &&
                    (idx < (42 + exp_payload_length))) begin

                    pidx = idx - 42;

                    ref_byte =
                        exp_payload_bytes[pidx*8 +: 8];

                end
                else if (
                    idx ==
                    ref_seq_index(exp_payload_length)
                ) begin

                    ref_byte = exp_seq;

                end
                else begin

                    ref_byte = 8'h00;

                end

            end
        endcase
    end
endfunction


// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------

task fill_payload;

    input integer n;
    input [7:0] seed;

    integer k;

    begin

        payload_bytes =
            {MAX_SNMP_BYTES*8{1'b0}};

        for (k = 0; k < n; k = k + 1) begin

            payload_bytes[k*8 +: 8] =
                seed + (3*k);

        end

    end

endtask


task snapshot_expected;

    begin

        exp_dst_mac        = cfg_dst_mac;
        exp_src_mac        = cfg_src_mac;

        exp_src_ip         = cfg_src_ip;
        exp_dst_ip         = cfg_dst_ip;

        exp_src_port       = cfg_src_port;
        exp_dst_port       = cfg_dst_port;

        exp_payload_length = payload_length;
        exp_payload_bytes  = payload_bytes;

        exp_seq            = seq_num;

    end

endtask


task mark_fail;

    input integer case_id;
    input integer byte_id;
    input [8*80-1:0] msg;

    begin

        fails = fails + 1;

        $display(
            "FAIL case=%0d byte=%0d : %s",
            case_id,
            byte_id,
            msg
        );

    end

endtask


task run_valid_case;

    input integer n;
    input integer stall_mode;
    input integer mutate_midframe;
    input integer preserve_inputs;
    input [7:0] seq_value;

    integer case_id;
    integer accepted;
    integer cycles_in_frame;

    integer expected_len;
    integer expected_seq_idx;

    integer final_stall_cycles;

    reg [7:0] expected_data;

    reg mutated;

    reg hold_active;
    reg [7:0] held_data;
    reg held_eof;

    begin

        cases = cases + 1;
        case_id = cases;


        // ----------------------------------------------------
        // Generate one deterministic frame unless the caller
        // supplied the exact frozen M2 compatibility inputs.
        // ----------------------------------------------------

        if (!preserve_inputs) begin

            cfg_dst_mac =
                48'h020000000200 + n;

            cfg_src_mac =
                48'h020000000001;

            cfg_src_ip =
                32'h0A000001;

            cfg_dst_ip =
                32'h0A000100 + n;

            cfg_src_port =
                16'd161;

            cfg_dst_port =
                16'h4000 + n;

            payload_length = n;

            seq_num = seq_value;

            fill_payload(
                n,
                8'h20 + n
            );

        end


        snapshot_expected;


        expected_len =
            ref_body_length(n);

        expected_seq_idx =
            ref_seq_index(n);


        accepted           = 0;
        cycles_in_frame    = 0;
        final_stall_cycles = 0;

        mutated     = 1'b0;

        hold_active = 1'b0;
        held_data   = 8'h00;
        held_eof    = 1'b0;

        tx_ready = 1'b1;


        // ----------------------------------------------------
        // Start pulse
        // ----------------------------------------------------

        @(negedge clk);

        start = 1'b1;

        @(posedge clk);

        @(negedge clk);

        start = 1'b0;


        if (!busy) begin

            mark_fail(
                case_id,
                -1,
                "builder did not enter busy after valid start"
            );

        end


        // ----------------------------------------------------
        // Consume the frame
        // ----------------------------------------------------

        while (busy) begin


            // ------------------------------------------------
            // Backpressure.
            //
            // stall_mode 2 additionally forces the final
            // sequence byte to remain stalled for two clocks.
            // ------------------------------------------------

            if (
                (stall_mode == 2) &&
                (accepted == expected_seq_idx) &&
                (final_stall_cycles < 2)
            ) begin

                tx_ready =
                    1'b0;

                final_stall_cycles =
                    final_stall_cycles + 1;

            end
            else if (stall_mode != 0) begin

                tx_ready =
                    !(
                        ((cycles_in_frame % 5) == 1) ||
                        ((cycles_in_frame % 11) == 7)
                     );

            end
            else begin

                tx_ready =
                    1'b1;

            end


            // ------------------------------------------------
            // Change every external frame input while this
            // frame is active.
            //
            // Also issue another start pulse while busy.
            // Neither is allowed to affect the active frame.
            // ------------------------------------------------

            if (
                mutate_midframe &&
                !mutated &&
                (accepted >= 10)
            ) begin

                cfg_dst_mac =
                    48'hAABBCCDDEEFF;

                cfg_src_mac =
                    48'h112233445566;

                cfg_src_ip =
                    32'hC0A80101;

                cfg_dst_ip =
                    32'hC0A80102;

                cfg_src_port =
                    16'hAAAA;

                cfg_dst_port =
                    16'hBBBB;

                payload_length =
                    8'd1;

                seq_num =
                    8'hFE;

                payload_bytes =
                    {MAX_SNMP_BYTES*8{1'b1}};

                start =
                    1'b1;

                mutated =
                    1'b1;

            end
            else begin

                start =
                    1'b0;

            end


            @(posedge clk);


            // ------------------------------------------------
            // During backpressure, both data and EOF must
            // remain stable.
            // ------------------------------------------------

            if (tx_valid && !tx_ready) begin

                if (!hold_active) begin

                    held_data =
                        tx_data;

                    held_eof =
                        tx_eof;

                    hold_active =
                        1'b1;

                end
                else begin

                    if (
                        (tx_data !== held_data) ||
                        (tx_eof  !== held_eof)
                    ) begin

                        mark_fail(
                            case_id,
                            accepted,
                            "tx_data/tx_eof changed during backpressure stall"
                        );

                    end

                end

            end


            // ------------------------------------------------
            // Accepted byte scoreboard
            // ------------------------------------------------

            if (tx_valid && tx_ready) begin

                hold_active =
                    1'b0;

                expected_data =
                    ref_byte(accepted);


                if (
                    tx_data !== expected_data
                ) begin

                    $display(
                        "DATA MISMATCH case=%0d N=%0d idx=%0d expected=%02h got=%02h",
                        case_id,
                        n,
                        accepted,
                        expected_data,
                        tx_data
                    );

                    fails =
                        fails + 1;

                end


                if (
                    accepted ==
                    expected_seq_idx
                ) begin

                    if (
                        tx_eof !== 1'b1
                    ) begin

                        mark_fail(
                            case_id,
                            accepted,
                            "tx_eof missing on final sequence byte"
                        );

                    end

                end
                else begin

                    if (
                        tx_eof !== 1'b0
                    ) begin

                        mark_fail(
                            case_id,
                            accepted,
                            "tx_eof asserted before final sequence byte"
                        );

                    end

                end


                accepted =
                    accepted + 1;

            end


            cycles_in_frame =
                cycles_in_frame + 1;


            @(negedge clk);


            if (
                cycles_in_frame > 1000
            ) begin

                mark_fail(
                    case_id,
                    -1,
                    "frame did not terminate"
                );

                start =
                    1'b0;

                tx_ready =
                    1'b1;

                disable run_valid_case;

            end

        end


        start =
            1'b0;

        tx_ready =
            1'b1;


        // ----------------------------------------------------
        // Exact body length
        // ----------------------------------------------------

        if (
            accepted != expected_len
        ) begin

            $display(
                "LENGTH MISMATCH case=%0d N=%0d expected=%0d got=%0d",
                case_id,
                n,
                expected_len,
                accepted
            );

            fails =
                fails + 1;

        end


        // Builder done belongs to the final accepted body byte.
        if (
            done !== 1'b1
        ) begin

            mark_fail(
                case_id,
                -1,
                "done pulse missing after final byte handshake"
            );

        end


        frames =
            frames + 1;


        // done must be one cycle only.
        @(posedge clk);

        #1;

        if (
            done !== 1'b0
        ) begin

            mark_fail(
                case_id,
                -1,
                "done is wider than one cycle"
            );

        end


        // ----------------------------------------------------
        // Boundary milestone transcript
        // ----------------------------------------------------

        if (
            (n == 1)  ||
            (n == 4)  ||
            (n == 17) ||
            (n == 18) ||
            (n == 44) ||
            (n == 96)
        ) begin

            $display(
                "MILESTONE PASS N=%0d UDP=%0d IP=%0d BODY=%0d SEQ_IDX=%0d",
                n,
                8+n,
                28+n,
                expected_len,
                expected_seq_idx
            );

        end

    end

endtask


task run_invalid_length_case;

    input integer n;

    integer case_id;
    integer k;

    begin

        cases =
            cases + 1;

        case_id =
            cases;


        payload_length =
            n;

        payload_bytes =
            {MAX_SNMP_BYTES*8{1'b0}};

        seq_num =
            8'h55;

        tx_ready =
            1'b1;


        @(negedge clk);

        start =
            1'b1;


        @(posedge clk);

        @(negedge clk);

        start =
            1'b0;


        for (
            k = 0;
            k < 4;
            k = k + 1
        ) begin

            @(posedge clk);

            #1;

            if (
                busy ||
                tx_valid ||
                done
            ) begin

                mark_fail(
                    case_id,
                    -1,
                    "invalid length unexpectedly started a frame"
                );

            end

        end

    end

endtask


// ------------------------------------------------------------
// Main regression
// ------------------------------------------------------------

initial begin

    rst =
        1'b1;

    start =
        1'b0;

    seq_num =
        8'd0;

    cfg_dst_mac =
        48'd0;

    cfg_src_mac =
        48'd0;

    cfg_src_ip =
        32'd0;

    cfg_dst_ip =
        32'd0;

    cfg_src_port =
        16'd0;

    cfg_dst_port =
        16'd0;

    payload_length =
        8'd0;

    payload_bytes =
        {MAX_SNMP_BYTES*8{1'b0}};

    tx_ready =
        1'b1;


    cases =
        0;

    frames =
        0;

    fails =
        0;


    repeat (4)
        @(posedge clk);

    @(negedge clk);

    rst =
        1'b0;


    // ========================================================
    // CASE 1
    //
    // Frozen old M2 4-byte compatibility anchor.
    //
    // Expected payload bytes on wire:
    // DE AD BE EF
    //
    // IP checksum:
    // 66 CB
    //
    // sequence:
    // body byte 59
    //
    // body:
    // exactly 60 bytes
    // ========================================================

    cfg_dst_mac =
        48'h020000000002;

    cfg_src_mac =
        48'h020000000001;

    cfg_src_ip =
        32'h0A000001;

    cfg_dst_ip =
        32'h0A000002;

    cfg_src_port =
        16'h2710;

    cfg_dst_port =
        16'h2711;

    payload_length =
        8'd4;

    payload_bytes =
        {MAX_SNMP_BYTES*8{1'b0}};

    payload_bytes[0*8 +: 8] =
        8'hDE;

    payload_bytes[1*8 +: 8] =
        8'hAD;

    payload_bytes[2*8 +: 8] =
        8'hBE;

    payload_bytes[3*8 +: 8] =
        8'hEF;

    seq_num =
        8'h00;


    snapshot_expected;


    if (
        ref_ipv4_checksum(
            32'h0A000001,
            32'h0A000002,
            16'h0020
        )
        !==
        16'h66CB
    ) begin

        $display(
            "FAIL: reference checksum anchor is not 16'h66CB"
        );

        fails =
            fails + 1;

    end


    run_valid_case(
        4,
        1,
        0,
        1,
        8'h00
    );


    $display(
        "M2_4BYTE_COMPAT_PASS"
    );


    // ========================================================
    // CASE 2
    //
    // 44-byte frame.
    //
    // Verify:
    // - all inputs latch at start
    // - start while busy is ignored
    // - final sequence/EOF survives a forced 2-cycle stall
    // ========================================================

    run_valid_case(
        44,
        2,
        1,
        0,
        8'hA5
    );


    // ========================================================
    // CASES 3..98
    //
    // Exhaustive supported-length sweep.
    // ========================================================

    for (
        i = 1;
        i <= 96;
        i = i + 1
    ) begin

        run_valid_case(
            i,
            1,
            0,
            0,
            i ^ 8'h5A
        );

    end


    // ========================================================
    // CASES 99..100
    //
    // Defensive range rejection.
    // ========================================================

    run_invalid_length_case(0);

    run_invalid_length_case(97);


    $display("");

    $display(
        "M6E_CASES=%0d FRAMES=%0d FAILS=%0d",
        cases,
        frames,
        fails
    );


    if (
        (cases  == 100) &&
        (frames == 98)  &&
        (fails  == 0)
    ) begin

        $display(
            "M6E_01B_TB_PASS"
        );

    end
    else begin

        $display(
            "M6E_01B_TB_FAIL"
        );

    end


    $finish;

end


// ------------------------------------------------------------
// Bounded-simulation watchdog
// ------------------------------------------------------------

initial begin

    #400000;

    $display(
        "M6E_01B_TB_TIMEOUT"
    );

    $finish;

end

endmodule
