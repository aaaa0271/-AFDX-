module afdx_tx_engine #(
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    parameter BAG_CYCLES = 400000
)(
    input  wire       clk,
    input  wire       rst,

    // Application traffic request.
    input  wire       tx_request,

    // Output byte stream.
    output wire [7:0] tx_data,
    output wire       tx_valid,
    input  wire       tx_ready,

    // Status
    output wire       busy,
    output wire       frame_done
);


wire frame_start;
wire [7:0] frame_seq_num;

wire builder_busy;


// ----------------------------------------------------
// TX control:
// BAG + Sequence
// ----------------------------------------------------

afdx_tx_ctrl #(
    .BAG_CYCLES(BAG_CYCLES)
) u_tx_ctrl (
    .clk           (clk),
    .rst           (rst),

    .tx_request    (tx_request),

    .frame_ready   (~builder_busy),

    .frame_start   (frame_start),
    .frame_seq_num (frame_seq_num)
);


// ----------------------------------------------------
// Frame builder
// ----------------------------------------------------

afdx_frame_builder u_frame_builder (
    .clk      (clk),
    .rst      (rst),

    .start    (frame_start),
    .seq_num  (frame_seq_num),

    .tx_data  (tx_data),
    .tx_valid (tx_valid),
    .tx_ready (tx_ready),

    .busy     (builder_busy),
    .done     (frame_done)
);


assign busy = builder_busy;


endmodule
