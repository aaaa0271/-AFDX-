module afdx_tx_ctrl #(
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    parameter BAG_CYCLES = 400000
)(
    input  wire       clk,
    input  wire       rst,

    // Application has traffic waiting.
    input  wire       tx_request,

    // Frame builder can accept a new frame.
    input  wire       frame_ready,

    // Start exactly one new frame.
    output wire       frame_start,

    // Sequence number assigned to THIS frame.
    output wire [7:0] frame_seq_num
);


wire bag_grant;
wire [7:0] seq_current;


// Only request BAG permission when
// the frame builder is ready.
wire effective_request;

assign effective_request =
        tx_request &&
        frame_ready;


// ----------------------------------------------------
// BAG regulator
// ----------------------------------------------------

bag_regulator #(
    .BAG_CYCLES(BAG_CYCLES)
) u_bag_regulator (
    .clk          (clk),
    .rst          (rst),
    .send_request (effective_request),
    .send_grant   (bag_grant)
);


// ----------------------------------------------------
// Sequence generator
// ----------------------------------------------------

seq_generator u_seq_generator (
    .clk      (clk),
    .rst      (rst),
    .advance  (bag_grant),
    .seq_num  (seq_current)
);


// Current sequence is assigned to the frame
// starting on this grant.
assign frame_seq_num = seq_current;


// BAG grant starts exactly one new frame.
assign frame_start = bag_grant;


endmodule
