// Fixed-ROM temporal inference plugin. Independent, synchronous ready/valid ports.
// No AFDX transmit, receive, firewall, loader or clock-control outputs.
module afdx_ai_tcn_plugin #(
    parameter WEIGHTS_FILE = "rtl/weights.mem",
    parameter BIASES_FILE = "rtl/biases.mem",
    parameter THRESHOLDS_FILE = "rtl/thresholds.mem",
    parameter SHIFTS_FILE = "rtl/shifts.mem",
    parameter integer INPUT_TIMEOUT_CYCLES = 65536
) (
    input wire clk,
    input wire rst_n,
    input wire job_valid,
    output wire job_ready,
    input wire [31:0] job_id,
    input wire [31:0] job_model_tag,
    input wire [17:0] job_feature_mask,
    input wire [15:0] job_flags,
    input wire feature_valid,
    output wire feature_ready,
    input wire signed [15:0] feature_data,
    input wire feature_last,
    output wire result_valid,
    input wire result_ready,
    output reg [31:0] result_job_id,
    output wire [31:0] result_model_tag,
    output reg [143:0] result_logits,
    output reg [7:0] result_candidate_mask,
    output reg [15:0] result_status,
    output reg [2:0] result_saturation,
    output reg [31:0] result_compute_cycles
);
    `include "ai_model_params.vh"

    localparam [4:0] IDLE=0, LOAD=1, C1_INIT=2, C1_MAC=3, C1_STORE=4,
        C2_INIT=5, C2_MAC=6, C2_STORE=7, POOL_INIT=8, POOL_ACC=9,
        POOL_STORE=10, FC_INIT=11, FC_MAC=12, FC_STORE=13, FINALIZE=14, HOLD=15;
    reg [4:0] state;
    reg signed [WEIGHT_BITS-1:0] weights [0:1919];
    reg signed [31:0] biases [0:40];
    reg signed [15:0] thresholds [0:7];
    reg [7:0] shifts [0:40];
    reg signed [15:0] input_mem [0:143];
    reg signed [15:0] h1 [0:127];
    reg signed [15:0] h2 [0:127];
    reg signed [15:0] rep [0:31];
    reg [7:0] load_index;
    reg [2:0] time_index;
    reg [4:0] output_index;
    reg [1:0] kernel_index;
    reg [5:0] channel_index;
    reg [31:0] idle_cycles;
    reg [31:0] compute_cycles;
    reg signed [47:0] accumulator;
    reg signed [15:0] mac_input;
    reg signed [WEIGHT_BITS-1:0] mac_weight;
    wire signed [15+WEIGHT_BITS:0] mac_product;
    wire signed [47:0] extended_product;
    integer source_time;
    integer weight_address;
    reg [7:0] requant_shift;
    wire signed [47:0] rounded_accumulator;

    initial begin
        $readmemh(WEIGHTS_FILE, weights);
        $readmemh(BIASES_FILE, biases);
        $readmemh(THRESHOLDS_FILE, thresholds);
        $readmemh(SHIFTS_FILE, shifts);
    end

    function signed [47:0] round_shift;
        input signed [47:0] value;
        input [7:0] shift;
        reg [47:0] magnitude;
        reg [47:0] rounded;
        begin
            if (shift == 0) round_shift = value;
            else begin
                magnitude = value < 0 ? -value : value;
                rounded = (magnitude + (48'd1 << (shift-1))) >> shift;
                round_shift = value < 0 ? -$signed(rounded) : $signed(rounded);
            end
        end
    endfunction

    function signed [15:0] clip_signed;
        input signed [47:0] value;
        begin
            if (value > 48'sd32767) clip_signed = 16'sd32767;
            else if (value < -48'sd32768) clip_signed = -16'sd32768;
            else clip_signed = value[15:0];
        end
    endfunction

    function signed [15:0] clip_relu;
        input signed [47:0] value;
        begin
            if (value < 0) clip_relu = 16'sd0;
            else if (value > 48'sd32767) clip_relu = 16'sd32767;
            else clip_relu = value[15:0];
        end
    endfunction

    assign job_ready = state == IDLE;
    assign feature_ready = state == LOAD;
    assign result_valid = state == HOLD;
    assign result_model_tag = MODEL_TAG;
    // One multiply datapath is shared by both convolutions and the dense layer.
    assign mac_product = mac_input * mac_weight;
    assign extended_product = {{(32-WEIGHT_BITS){mac_product[15+WEIGHT_BITS]}}, mac_product};
    assign rounded_accumulator = round_shift(accumulator, requant_shift);

    always @* begin
        mac_input = 16'sd0;
        mac_weight = 0;
        source_time = 0;
        weight_address = 0;
        requant_shift = 0;
        if (state == C1_MAC || state == C1_STORE) begin
            requant_shift = shifts[output_index];
            weight_address = output_index*54 + kernel_index*18 + channel_index;
            if (state == C1_MAC) begin
                source_time = time_index - kernel_index;
                if (source_time >= 0) mac_input = input_mem[source_time*18 + channel_index];
                mac_weight = weights[weight_address];
            end
        end else if (state == C2_MAC || state == C2_STORE) begin
            requant_shift = shifts[16+output_index];
            weight_address = 864 + output_index*48 + kernel_index*16 + channel_index;
            if (state == C2_MAC) begin
                source_time = time_index - kernel_index*2;
                if (source_time >= 0) mac_input = h1[source_time*16 + channel_index];
                mac_weight = weights[weight_address];
            end
        end else if (state == FC_MAC || state == FC_STORE) begin
            requant_shift = shifts[32+output_index];
            weight_address = 1632 + output_index*32 + channel_index;
            if (state == FC_MAC) begin
                mac_input = rep[channel_index];
                mac_weight = weights[weight_address];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            load_index <= 0;
            time_index <= 0;
            output_index <= 0;
            kernel_index <= 0;
            channel_index <= 0;
            idle_cycles <= 0;
            compute_cycles <= 0;
            accumulator <= 0;
            result_job_id <= 0;
            result_logits <= 0;
            result_candidate_mask <= 0;
            result_status <= 0;
            result_saturation <= 0;
            result_compute_cycles <= 0;
        end else begin
            if (state >= C1_INIT && state <= FINALIZE) compute_cycles <= compute_cycles + 1;
            case (state)
                IDLE: if (job_valid) begin
                    result_job_id <= job_id;
                    result_logits <= 0;
                    result_candidate_mask <= 0;
                    result_saturation <= 0;
                    result_compute_cycles <= 0;
                    compute_cycles <= 0;
                    load_index <= 0;
                    idle_cycles <= 0;
                    result_status <= (job_flags[0] ? 16'h0010 : 16'h0000) |
                                     (job_flags[1] ? 16'h0020 : 16'h0000) |
                                     (job_feature_mask != 18'h3ffff ? 16'h0002 : 16'h0000) |
                                     (job_model_tag != MODEL_TAG ? 16'h0004 : 16'h0000) |
                                     (job_flags[15:2] != 0 ? 16'h0040 : 16'h0000);
                    if (job_feature_mask != 18'h3ffff || job_model_tag != MODEL_TAG || job_flags[15:2] != 0)
                        state <= HOLD;
                    else state <= LOAD;
                end
                LOAD: begin
                    // A valid beat wins if it coincides with the timeout boundary.
                    if (feature_valid) begin
                        idle_cycles <= 0;
                        input_mem[load_index] <= feature_data;
                        if (feature_last != (load_index == 143)) begin
                            result_status <= result_status | 16'h0001;
                            state <= HOLD;
                        end else if (load_index == 143) begin
                            time_index <= 0;
                            output_index <= 0;
                            state <= C1_INIT;
                        end else load_index <= load_index + 1;
                    end else if (idle_cycles >= INPUT_TIMEOUT_CYCLES-1) begin
                        result_status <= result_status | 16'h0008;
                        state <= HOLD;
                    end else idle_cycles <= idle_cycles + 1;
                end
                C1_INIT: begin
                    accumulator <= {{16{biases[output_index][31]}}, biases[output_index]};
                    kernel_index <= 0;
                    channel_index <= 0;
                    state <= C1_MAC;
                end
                C1_MAC: begin
                    accumulator <= accumulator + extended_product;
                    if (channel_index == 17) begin
                        channel_index <= 0;
                        if (kernel_index == 2) state <= C1_STORE;
                        else kernel_index <= kernel_index + 1;
                    end else channel_index <= channel_index + 1;
                end
                C1_STORE: begin
                    h1[time_index*16+output_index] <= clip_relu(rounded_accumulator);
                    if (rounded_accumulator > 48'sd32767) result_saturation[0] <= 1;
                    if (output_index == 15) begin
                        output_index <= 0;
                        if (time_index == 7) begin time_index <= 0; state <= C2_INIT; end
                        else begin time_index <= time_index + 1; state <= C1_INIT; end
                    end else begin output_index <= output_index + 1; state <= C1_INIT; end
                end
                C2_INIT: begin
                    accumulator <= {{16{biases[16+output_index][31]}}, biases[16+output_index]};
                    kernel_index <= 0;
                    channel_index <= 0;
                    state <= C2_MAC;
                end
                C2_MAC: begin
                    accumulator <= accumulator + extended_product;
                    if (channel_index == 15) begin
                        channel_index <= 0;
                        if (kernel_index == 2) state <= C2_STORE;
                        else kernel_index <= kernel_index + 1;
                    end else channel_index <= channel_index + 1;
                end
                C2_STORE: begin
                    h2[time_index*16+output_index] <= clip_relu(rounded_accumulator);
                    if (rounded_accumulator > 48'sd32767) result_saturation[1] <= 1;
                    if (output_index == 15) begin
                        output_index <= 0;
                        if (time_index == 7) begin time_index <= 0; state <= POOL_INIT; end
                        else begin time_index <= time_index + 1; state <= C2_INIT; end
                    end else begin output_index <= output_index + 1; state <= C2_INIT; end
                end
                POOL_INIT: begin
                    rep[output_index] <= h2[112+output_index];
                    time_index <= 0;
                    accumulator <= 0;
                    state <= POOL_ACC;
                end
                POOL_ACC: begin
                    accumulator <= accumulator + {{32{h2[time_index*16+output_index][15]}}, h2[time_index*16+output_index]};
                    if (time_index == 7) state <= POOL_STORE;
                    else time_index <= time_index + 1;
                end
                POOL_STORE: begin
                    rep[16+output_index] <= clip_signed(round_shift(accumulator, 8'd3));
                    if (output_index == 15) begin output_index <= 0; state <= FC_INIT; end
                    else begin output_index <= output_index + 1; state <= POOL_INIT; end
                end
                FC_INIT: begin
                    accumulator <= {{16{biases[32+output_index][31]}}, biases[32+output_index]};
                    channel_index <= 0;
                    state <= FC_MAC;
                end
                FC_MAC: begin
                    accumulator <= accumulator + extended_product;
                    if (channel_index == 31) state <= FC_STORE;
                    else channel_index <= channel_index + 1;
                end
                FC_STORE: begin
                    result_logits[output_index*16 +: 16] <= clip_signed(rounded_accumulator);
                    if (rounded_accumulator > 48'sd32767 || rounded_accumulator < -48'sd32768)
                        result_saturation[2] <= 1;
                    if (output_index < 8)
                        result_candidate_mask[output_index] <= clip_signed(rounded_accumulator) >= thresholds[output_index];
                    if (output_index == 8) state <= FINALIZE;
                    else begin output_index <= output_index + 1; state <= FC_INIT; end
                end
                FINALIZE: begin
                    result_compute_cycles <= compute_cycles + 1;
                    if (result_saturation != 0) result_status <= result_status | 16'h0020;
                    if (result_status != 0 || result_saturation != 0) result_candidate_mask <= 0;
                    state <= HOLD;
                end
                HOLD: if (result_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
