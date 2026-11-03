// Optional trusted LOCAL register interface, separate from existing AFDX/sec buses.
// A transfer occurs on a rising edge with cfg_valid && cfg_ready.
module afdx_defense_ai_csr #(
    parameter WEIGHTS_FILE = "aihw_plugin/rtl/weights.mem",
    parameter BIASES_FILE = "aihw_plugin/rtl/biases.mem",
    parameter THRESHOLDS_FILE = "aihw_plugin/rtl/thresholds.mem",
    parameter SHIFTS_FILE = "aihw_plugin/rtl/shifts.mem",
    parameter integer INPUT_TIMEOUT_CYCLES = 65536
) (
    input wire clk,
    input wire rst_n,
    input wire cfg_valid,
    input wire cfg_write,
    input wire [7:0] cfg_addr,
    input wire [31:0] cfg_wdata,
    output reg cfg_ready,
    output reg cfg_error,
    output reg [31:0] cfg_rdata,
    output wire tap_valid,tap_idle,output wire [7:0] tap_mask,output wire [15:0] tap_status,
    output wire [31:0] tap_job_id,output wire [143:0] tap_logits
);
    wire job_ready, feature_ready, result_valid;
    wire [31:0] model_tag, result_job_id, result_cycles;
    wire [143:0] logits;
    wire [7:0] mask;
    wire [15:0] status;
    wire [2:0] saturation;
    reg [31:0] job_id_q, job_tag_q;
    reg [17:0] feature_mask_q;
    reg [15:0] flags_q;
    wire transfer = cfg_valid && cfg_ready && !cfg_error;
    wire start_job = transfer && cfg_write && cfg_addr == 8'h1c && cfg_wdata[0];
    wire send_feature = transfer && cfg_write && cfg_addr == 8'h20;
    wire ack_result = transfer && cfg_write && cfg_addr == 8'h24 && cfg_wdata[0];

    afdx_ai_tcn_plugin #(.WEIGHTS_FILE(WEIGHTS_FILE), .BIASES_FILE(BIASES_FILE),
        .THRESHOLDS_FILE(THRESHOLDS_FILE), .SHIFTS_FILE(SHIFTS_FILE),
        .INPUT_TIMEOUT_CYCLES(INPUT_TIMEOUT_CYCLES)) core (
        .clk(clk), .rst_n(rst_n), .job_valid(start_job), .job_ready(job_ready),
        .job_id(job_id_q), .job_model_tag(job_tag_q), .job_feature_mask(feature_mask_q),
        .job_flags(flags_q), .feature_valid(send_feature), .feature_ready(feature_ready),
        .feature_data(cfg_wdata[15:0]), .feature_last(cfg_wdata[16]),
        .result_valid(result_valid), .result_ready(ack_result), .result_job_id(result_job_id),
        .result_model_tag(model_tag), .result_logits(logits), .result_candidate_mask(mask),
        .result_status(status), .result_saturation(saturation), .result_compute_cycles(result_cycles)
    );

    always @* begin
        cfg_ready = 1;
        cfg_error = 0;
        cfg_rdata = 0;
        if (cfg_addr[1:0] != 0) cfg_error = 1;
        else if (cfg_write) begin
            case (cfg_addr)
                8'h0c, 8'h10: begin end
                8'h14: if (cfg_wdata[31:18] != 0) cfg_error = 1;
                8'h18: if (cfg_wdata[31:16] != 0) cfg_error = 1;
                8'h1c: begin
                    if (cfg_wdata != 1) cfg_error = 1;
                    else cfg_ready = job_ready;
                end
                8'h20: begin
                    if (cfg_wdata[31:17] != 0) cfg_error = 1;
                    else cfg_ready = feature_ready;
                end
                8'h24: begin
                    if (cfg_wdata != 1) cfg_error = 1;
                    else cfg_ready = result_valid;
                end
                default: cfg_error = 1;
            endcase
        end else begin
            case (cfg_addr)
                8'h00: cfg_rdata = 32'h41494831; // ASCII AIH1
                8'h04: cfg_rdata = model_tag;
                8'h08: cfg_rdata = {29'd0, result_valid, feature_ready, job_ready};
                8'h0c: cfg_rdata = job_id_q;
                8'h10: cfg_rdata = job_tag_q;
                8'h14: cfg_rdata = {14'd0, feature_mask_q};
                8'h18: cfg_rdata = {16'd0, flags_q};
                8'h28: cfg_rdata = result_job_id;
                8'h2c: cfg_rdata = {mask, 5'd0, saturation, status};
                8'h30: cfg_rdata = result_cycles;
                8'h34,8'h38,8'h3c,8'h40,8'h44,8'h48,8'h4c,8'h50,8'h54:
                    cfg_rdata = {16'd0, logits[((cfg_addr-8'h34)>>2)*16 +: 16]};
                default: cfg_error = 1;
            endcase
        end
        if (cfg_error) begin cfg_ready = 1; cfg_rdata = 32'hffffffff; end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            job_id_q <= 0;
            job_tag_q <= 0;
            feature_mask_q <= 0;
            flags_q <= 0;
        end else if (transfer && cfg_write) begin
            case (cfg_addr)
                8'h0c: job_id_q <= cfg_wdata;
                8'h10: job_tag_q <= cfg_wdata;
                8'h14: feature_mask_q <= cfg_wdata[17:0];
                8'h18: flags_q <= cfg_wdata[15:0];
                default: begin end
            endcase
        end
    end
assign tap_valid=result_valid;assign tap_idle=job_ready&&!result_valid;assign tap_mask=mask;assign tap_status=status;
    assign tap_job_id=result_job_id;assign tap_logits=logits;
endmodule
