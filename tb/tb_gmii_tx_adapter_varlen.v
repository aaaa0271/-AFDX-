`timescale 1ns/1ps

module tb_gmii_tx_adapter_varlen;

// ====================================================
// Signals
// ====================================================

reg clk;
reg rst;

// Variable-length DUT source
reg [7:0] src_idx;
wire [7:0] s_data_v;
wire       s_valid_v;
wire       s_eof_v;
wire       s_ready_v;
wire [7:0] gmii_txd_v;
wire       gmii_tx_en_v;
wire       gmii_tx_er_v;
wire       frame_done_v;
wire       underrun_v;

// Frozen 60-byte golden source
reg [7:0] src_idx_60;
wire [7:0] s_data_60;
wire       s_valid_60;
wire       s_ready_60;
wire [7:0] gmii_txd_60;
wire       gmii_tx_en_60;
wire       gmii_tx_er_60;
wire       frame_done_60;
wire       underrun_60;

// Shared source drive
reg send_active;
reg [8*140-1:0] body_bytes;
integer body_len;

integer fails;
integer cases;
integer frames;
integer i;
integer stage_fails;


// ====================================================
// DUT
// ====================================================

gmii_tx_adapter_varlen dut (
    .clk        (clk),
    .rst        (rst),
    .s_data     (s_data_v),
    .s_valid    (s_valid_v),
    .s_eof      (s_eof_v),
    .s_ready    (s_ready_v),
    .gmii_txd   (gmii_txd_v),
    .gmii_tx_en (gmii_tx_en_v),
    .gmii_tx_er (gmii_tx_er_v),
    .frame_done (frame_done_v),
    .underrun   (underrun_v)
);


// ====================================================
// Frozen 60-byte golden
// ====================================================

gmii_tx_adapter_60 golden (
    .clk        (clk),
    .rst        (rst),
    .s_data     (s_data_60),
    .s_valid    (s_valid_60),
    .s_ready    (s_ready_60),
    .gmii_txd   (gmii_txd_60),
    .gmii_tx_en (gmii_tx_en_60),
    .gmii_tx_er (gmii_tx_er_60),
    .frame_done (frame_done_60),
    .underrun   (underrun_60)
);


// ====================================================
// Source drive (variable-length DUT)
// ====================================================

assign s_data_v  = body_bytes[src_idx*8 +: 8];
assign s_valid_v = send_active;
assign s_eof_v   = send_active && (src_idx == body_len - 1);

always @(posedge clk) begin
    if (rst) begin
        src_idx <= 0;
    end
    else if (send_active && s_ready_v) begin
        if (src_idx == body_len - 1)
            src_idx <= 0;
        else
            src_idx <= src_idx + 1;
    end
end


// ====================================================
// Source drive (frozen 60-byte golden)
// ====================================================

assign s_data_60  = body_bytes[src_idx_60*8 +: 8];
assign s_valid_60 = send_active;

always @(posedge clk) begin
    if (rst) begin
        src_idx_60 <= 0;
    end
    else if (send_active && s_ready_60) begin
        if (src_idx_60 == body_len - 1)
            src_idx_60 <= 0;
        else
            src_idx_60 <= src_idx_60 + 1;
    end
end


// ====================================================
// Clock
// ====================================================

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end


// ====================================================
// Reference CRC32 (mirrors DUT reflected polynomial)
// ====================================================

function [31:0] crc32_ref;
    input [31:0] crc_in;
    input [7:0]  data_in;
    reg [31:0] crc_tmp;
    integer i;
    begin
        crc_tmp = crc_in ^ {24'd0, data_in};
        for (i = 0; i < 8; i = i + 1) begin
            if (crc_tmp[0])
                crc_tmp = (crc_tmp >> 1) ^ 32'hEDB88320;
            else
                crc_tmp = crc_tmp >> 1;
        end
        crc32_ref = crc_tmp;
    end
endfunction


// ====================================================
// Helpers
// ====================================================

task fill_body;
    input integer n;
    input [7:0] seed;
    integer k;
    begin
        body_bytes = {8*140{1'b0}};
        for (k = 0; k < n; k = k + 1)
            body_bytes[k*8 +: 8] = seed + (3*k);
    end
endtask


// ====================================================
// Single-frame full check (sweep / milestone)
// ====================================================

task run_single_frame;
    input integer blen;
    input [7:0] seed;

    integer gmii_count;
    integer fcs_idx;
    integer fd_count;
    integer k;
    reg [31:0] ref_crc;
    reg [31:0] ref_fcs;
    reg [7:0]  exp;

    begin

        gmii_count = 0;
        fcs_idx    = 0;
        fd_count   = 0;

        body_len = blen;
        fill_body(blen, seed);

        ref_crc = 32'hFFFFFFFF;
        for (k = 0; k < blen; k = k + 1)
            ref_crc = crc32_ref(ref_crc, body_bytes[k*8 +: 8]);
        ref_fcs = ~ref_crc;

        @(negedge clk);
        send_active = 1;
        src_idx = 0;

        while (fd_count == 0) begin

            @(negedge clk);

            if (gmii_tx_en_v) begin

                if (gmii_count < 7) begin
                    if (gmii_txd_v !== 8'h55) begin
                        $display("FAIL blen=%0d preamble byte %0d got %02h", blen, gmii_count, gmii_txd_v);
                        fails = fails + 1;
                    end
                end
                else if (gmii_count == 7) begin
                    if (gmii_txd_v !== 8'hD5) begin
                        $display("FAIL blen=%0d SFD got %02h", blen, gmii_txd_v);
                        fails = fails + 1;
                    end
                end
                else if (gmii_count < 8 + blen) begin
                    if (gmii_txd_v !== body_bytes[(gmii_count-8)*8 +: 8]) begin
                        $display("FAIL blen=%0d body byte %0d got %02h exp %02h",
                            blen, gmii_count-8, gmii_txd_v, body_bytes[(gmii_count-8)*8 +: 8]);
                        fails = fails + 1;
                    end
                end
                else if (gmii_count < 8 + blen + 4) begin
                    case (fcs_idx)
                        0: exp = ref_fcs[7:0];
                        1: exp = ref_fcs[15:8];
                        2: exp = ref_fcs[23:16];
                        3: exp = ref_fcs[31:24];
                        default: exp = 8'h00;
                    endcase
                    if (gmii_txd_v !== exp) begin
                        $display("FAIL blen=%0d FCS byte %0d got %02h exp %02h", blen, fcs_idx, gmii_txd_v, exp);
                        fails = fails + 1;
                    end
                    fcs_idx = fcs_idx + 1;
                end
                else begin
                    $display("FAIL blen=%0d extra GMII byte", blen);
                    fails = fails + 1;
                end

                gmii_count = gmii_count + 1;

            end

            if (frame_done_v)
                fd_count = fd_count + 1;

            @(posedge clk);

        end

        if (gmii_count != blen + 12) begin
            $display("FAIL blen=%0d gmii_count=%0d exp=%0d", blen, gmii_count, blen+12);
            fails = fails + 1;
        end

        if (fd_count != 1) begin
            $display("FAIL blen=%0d frame_done count=%0d", blen, fd_count);
            fails = fails + 1;
        end

        // frame_done must be a single-cycle pulse.
        @(negedge clk);
        if (frame_done_v) begin
            $display("FAIL blen=%0d frame_done not single cycle", blen);
            fails = fails + 1;
        end

        send_active = 0;
        frames = frames + 1;

    end

endtask


// ====================================================
// Frozen 60-byte legacy cycle-for-cycle compatibility
// ====================================================

task run_compat_60;
    reg fd_v;
    reg fd_60;
    begin

        body_len = 60;
        fill_body(60, 8'h20);

        fd_v  = 0;
        fd_60 = 0;

        @(negedge clk);
        send_active = 1;
        src_idx    = 0;
        src_idx_60 = 0;

        while (!(fd_v && fd_60)) begin

            @(negedge clk);

            if (s_ready_v !== s_ready_60) begin
                $display("FAIL compat s_ready");
                fails = fails + 1;
            end
            if (gmii_txd_v !== gmii_txd_60) begin
                $display("FAIL compat txd got %02h exp %02h", gmii_txd_v, gmii_txd_60);
                fails = fails + 1;
            end
            if (gmii_tx_en_v !== gmii_tx_en_60) begin
                $display("FAIL compat tx_en");
                fails = fails + 1;
            end
            if (gmii_tx_er_v !== gmii_tx_er_60) begin
                $display("FAIL compat tx_er");
                fails = fails + 1;
            end
            if (frame_done_v !== frame_done_60) begin
                $display("FAIL compat frame_done");
                fails = fails + 1;
            end
            if (underrun_v !== underrun_60) begin
                $display("FAIL compat underrun");
                fails = fails + 1;
            end

            if (frame_done_v)  fd_v  = 1;
            if (frame_done_60) fd_60 = 1;

            @(posedge clk);

        end

        @(negedge clk);
        send_active = 0;

    end

endtask


// ====================================================
// Final-byte FCS sensitivity (hard-coded anchors)
// ====================================================

task run_anchor_crc;
    input [7:0]  last_byte;
    input [31:0] exp_fcs_wire;

    integer k;
    integer gmii_count;
    integer fd_count;
    reg [7:0] fcs_cap [0:3];

    begin

        body_bytes = {8*140{1'b0}};
        for (k = 0; k < 59; k = k + 1)
            body_bytes[k*8 +: 8] = k[7:0];
        body_bytes[59*8 +: 8] = last_byte;
        body_len = 60;

        gmii_count = 0;
        fd_count   = 0;

        @(negedge clk);
        send_active = 1;
        src_idx = 0;

        while (fd_count == 0) begin
            @(negedge clk);
            if (gmii_tx_en_v) begin
                if (gmii_count >= 68 && gmii_count < 72)
                    fcs_cap[gmii_count - 68] = gmii_txd_v;
                gmii_count = gmii_count + 1;
            end
            if (frame_done_v)
                fd_count = fd_count + 1;
            @(posedge clk);
        end

        @(negedge clk);
        send_active = 0;

        if (fcs_cap[0] !== exp_fcs_wire[7:0]) begin
            $display("FAIL anchor FCS0 last=%02h got %02h exp %02h", last_byte, fcs_cap[0], exp_fcs_wire[7:0]);
            fails = fails + 1;
        end
        if (fcs_cap[1] !== exp_fcs_wire[15:8]) begin
            $display("FAIL anchor FCS1 last=%02h got %02h exp %02h", last_byte, fcs_cap[1], exp_fcs_wire[15:8]);
            fails = fails + 1;
        end
        if (fcs_cap[2] !== exp_fcs_wire[23:16]) begin
            $display("FAIL anchor FCS2 last=%02h got %02h exp %02h", last_byte, fcs_cap[2], exp_fcs_wire[23:16]);
            fails = fails + 1;
        end
        if (fcs_cap[3] !== exp_fcs_wire[31:24]) begin
            $display("FAIL anchor FCS3 last=%02h got %02h exp %02h", last_byte, fcs_cap[3], exp_fcs_wire[31:24]);
            fails = fails + 1;
        end

    end

endtask


// ====================================================
// Underrun detection
// ====================================================

task run_underrun;
    reg in_body;
    begin

        body_len = 60;
        fill_body(60, 8'h33);

        @(negedge clk);
        send_active = 1;
        src_idx = 0;

        // Wait until the adapter enters BODY (s_ready asserted).
        in_body = 0;
        while (!in_body) begin
            @(negedge clk);
            if (s_ready_v) in_body = 1;
            else @(posedge clk);
        end

        // Consume a few body bytes, then drop s_valid mid-body.
        repeat (5) @(posedge clk);

        @(negedge clk);
        send_active = 0;

        repeat (3) @(posedge clk);

        if (underrun_v !== 1'b1) begin
            $display("FAIL underrun not detected state=%0d", dut.state);
            fails = fails + 1;
        end
        if (frame_done_v !== 1'b0) begin
            $display("FAIL underrun frame_done should be 0");
            fails = fails + 1;
        end

        // Recover via reset.
        @(negedge clk);
        rst = 1;
        @(posedge clk);
        @(negedge clk);
        rst = 0;
        send_active = 0;

    end

endtask


// ====================================================
// Back-to-back IFG
// ====================================================

task run_back_to_back;
    integer k;
    reg w;
    begin

        // First frame (60 bytes).
        body_len = 60;
        fill_body(60, 8'h10);

        @(negedge clk);
        send_active = 1;
        src_idx = 0;

        w = 0;
        while (!w) begin
            @(negedge clk);
            if (frame_done_v) w = 1;
            else @(posedge clk);
        end

        // Second frame (61 bytes) prepared during IFG; s_valid stays 1.
        body_len = 61;
        fill_body(61, 8'h20);

        // Advance one posedge into IFG (TX_EN falls to 0).
        @(posedge clk);

        // Exactly 12 idle cycles, s_ready must stay 0 throughout.
        for (k = 0; k < 12; k = k + 1) begin
            @(negedge clk);
            if (gmii_tx_en_v) begin
                $display("FAIL back2back TX_EN high during IFG (idle %0d)", k);
                fails = fails + 1;
            end
            if (s_ready_v) begin
                $display("FAIL back2back s_ready high during IFG (idle %0d)", k);
                fails = fails + 1;
            end
            @(posedge clk);
        end

        // Next byte must be the second frame preamble 55.
        @(negedge clk);
        if (!gmii_tx_en_v) begin
            $display("FAIL back2back second frame not started");
            fails = fails + 1;
        end
        if (gmii_txd_v !== 8'h55) begin
            $display("FAIL back2back second frame preamble got %02h", gmii_txd_v);
            fails = fails + 1;
        end

        // Wait for second frame completion.
        w = 0;
        while (!w) begin
            @(negedge clk);
            if (frame_done_v) w = 1;
            else @(posedge clk);
        end

        @(negedge clk);
        send_active = 0;

    end

endtask


// ====================================================
// Main regression
// ====================================================

initial begin

    rst = 1;
    send_active = 0;
    src_idx = 0;
    src_idx_60 = 0;
    body_len = 60;
    body_bytes = {8*140{1'b0}};

    fails  = 0;
    cases  = 0;
    frames = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 0;


    // ====================================================
    // LEGACY_60_COMPAT
    // ====================================================
    cases = cases + 1;
    stage_fails = fails;
    run_compat_60;
    if (fails == stage_fails) $display("LEGACY_60_COMPAT_PASS");


    // ====================================================
    // FINAL_BYTE_CRC (independent anchors)
    // ====================================================
    cases = cases + 1;
    stage_fails = fails;
    run_anchor_crc(8'h00, 32'h01E796CA); // wire FCS: CA 96 E7 01
    run_anchor_crc(8'h01, 32'h76E0A65C); // wire FCS: 5C A6 E0 76
    if (fails == stage_fails) $display("FINAL_BYTE_CRC_PASS");


    // ====================================================
    // BODY_LENGTH_SWEEP 60..139
    // ====================================================
    stage_fails = fails;
    for (i = 60; i <= 139; i = i + 1) begin
        run_single_frame(i, i[7:0]);
        if (i == 60 || i == 61 || i == 87 || i == 139)
            $display("MILESTONE PASS BODY=%0d GMII_BYTES=%0d", i, i+12);
    end
    if (fails == stage_fails) $display("BODY_LENGTH_SWEEP_PASS 60..139");


    // ====================================================
    // UNDERRUN_DETECTION
    // ====================================================
    cases = cases + 1;
    stage_fails = fails;
    run_underrun;
    if (fails == stage_fails) $display("UNDERRUN_DETECTION_PASS");


    // ====================================================
    // BACK_TO_BACK_IFG
    // ====================================================
    cases = cases + 1;
    stage_fails = fails;
    run_back_to_back;
    if (fails == stage_fails) $display("BACK_TO_BACK_IFG_PASS");


    $display("");
    $display("M6E_01C_FAILS=%0d", fails);

    if (fails == 0)
        $display("M6E_01C_TB_PASS");
    else
        $display("M6E_01C_TB_FAIL");

    $finish;

end


// ====================================================
// Bounded-simulation watchdog
// ====================================================

initial begin
    #500000;
    $display("M6E_01C_TB_TIMEOUT");
    $finish;
end

endmodule
