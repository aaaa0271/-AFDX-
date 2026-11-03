`timescale 1ns / 1ps


module afdx_payload_commit_buffer
#(
    parameter integer MAX_PAYLOAD_BYTES = 1471,
    parameter integer ADDR_WIDTH        = 11
)
(
    input  wire       clk,
    input  wire       rst,


    // ========================================================
    // Capture interface
    //
    // Payload stream from M3-B.
    // ========================================================

    input  wire [7:0] in_data,
    input  wire       in_valid,
    output wire       in_ready,

    input  wire       in_sof,
    input  wire       in_eof,


    // ========================================================
    // Final frame decision
    //
    // decision_accept = 1:
    //     replay buffered payload to application
    //
    // decision_accept = 0:
    //     discard entire buffered payload
    // ========================================================

    input  wire       decision_valid,
    input  wire       decision_accept,


    // ========================================================
    // Application output
    // ========================================================

    output wire [7:0] out_data,
    output wire       out_valid,
    input  wire       out_ready,

    output wire       out_sof,
    output wire       out_eof,


    // ========================================================
    // Status
    // ========================================================

    output wire       capture_active,
    output wire       frame_buffered,
    output wire       replay_active,

    output reg        overflow_error
);


// ============================================================
// State encoding
// ============================================================

localparam [1:0]
    ST_CAPTURE = 2'd0,
    ST_WAIT    = 2'd1,
    ST_REPLAY  = 2'd2;


// ============================================================
// Payload memory
// ============================================================

reg [7:0] payload_mem [0:MAX_PAYLOAD_BYTES-1];


// ============================================================
// Capture state
// ============================================================

reg [1:0] state;

reg [ADDR_WIDTH-1:0] write_ptr;

reg [ADDR_WIDTH:0] payload_count;


// ============================================================
// Replay state
// ============================================================

reg [ADDR_WIDTH-1:0] read_ptr;


// ============================================================
// Early decision latch
//
// A decision is allowed to arrive while payload is still being
// captured. This is useful because M3-C may reject a frame before
// the end of the payload.
//
// The final frontend integration will combine M3-C and M3-D into
// one final decision event.
// ============================================================

reg decision_pending;
reg decision_value;


// ============================================================
// Handshake
// ============================================================

wire capture_fire;
wire replay_fire;


assign in_ready =

    (state == ST_CAPTURE) &&

    (payload_count < MAX_PAYLOAD_BYTES);


assign capture_fire =
    in_valid &&
    in_ready;


assign out_valid =
    (state == ST_REPLAY);


assign replay_fire =
    out_valid &&
    out_ready;


// ============================================================
// Output data
// ============================================================

assign out_data =
    payload_mem[read_ptr];


assign out_sof =
    (state == ST_REPLAY) &&
    (read_ptr == {ADDR_WIDTH{1'b0}});


assign out_eof =
    (state == ST_REPLAY) &&
    (payload_count != 0) &&
    (read_ptr == payload_count - 1'b1);


// ============================================================
// Status
// ============================================================

assign capture_active =
    (state == ST_CAPTURE);


assign frame_buffered =
    (state == ST_WAIT);


assign replay_active =
    (state == ST_REPLAY);


// ============================================================
// Main sequential logic
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        state            <= ST_CAPTURE;

        write_ptr        <= {ADDR_WIDTH{1'b0}};
        read_ptr         <= {ADDR_WIDTH{1'b0}};

        payload_count    <= {(ADDR_WIDTH+1){1'b0}};

        decision_pending <= 1'b0;
        decision_value   <= 1'b0;

        overflow_error   <= 1'b0;

    end
    else begin

        // ----------------------------------------------------
        // Default sticky/error behavior
        // ----------------------------------------------------

        if (
            (state == ST_CAPTURE) &&
            in_valid &&
            !in_ready
        ) begin

            overflow_error <= 1'b1;

        end


        // ====================================================
        // CAPTURE
        // ====================================================

        if (state == ST_CAPTURE) begin

            // ------------------------------------------------
            // Capture decision if it arrives before EOF.
            // ------------------------------------------------

            if (decision_valid) begin

                decision_pending <= 1'b1;
                decision_value   <= decision_accept;

            end


            // ------------------------------------------------
            // Capture payload byte
            // ------------------------------------------------

            if (capture_fire) begin

                payload_mem[write_ptr] <= in_data;

                write_ptr <=
                    write_ptr + 1'b1;


                // --------------------------------------------
                // End of payload
                // --------------------------------------------

                if (in_eof) begin

                    payload_count <=
                        payload_count + 1'b1;

                    read_ptr <=
                        {ADDR_WIDTH{1'b0}};


                    // ----------------------------------------
                    // Decision arrives on exactly same cycle
                    // as EOF.
                    // ----------------------------------------

                    if (decision_valid) begin

                        decision_pending <= 1'b0;

                        if (decision_accept) begin

                            state <= ST_REPLAY;

                        end
                        else begin

                            state <= ST_CAPTURE;

                            write_ptr <=
                                {ADDR_WIDTH{1'b0}};

                            payload_count <=
                                {(ADDR_WIDTH+1){1'b0}};

                        end

                    end


                    // ----------------------------------------
                    // Decision was already received earlier.
                    // ----------------------------------------

                    else if (decision_pending) begin

                        decision_pending <= 1'b0;

                        if (decision_value) begin

                            state <= ST_REPLAY;

                        end
                        else begin

                            state <= ST_CAPTURE;

                            write_ptr <=
                                {ADDR_WIDTH{1'b0}};

                            payload_count <=
                                {(ADDR_WIDTH+1){1'b0}};

                        end

                    end


                    // ----------------------------------------
                    // No decision yet.
                    // ----------------------------------------

                    else begin

                        state <= ST_WAIT;

                    end

                end
                else begin

                    payload_count <=
                        payload_count + 1'b1;

                end

            end

        end


        // ====================================================
        // WAIT FOR FINAL DECISION
        // ====================================================

        else if (state == ST_WAIT) begin

            if (decision_valid) begin

                decision_pending <= 1'b0;

                if (decision_accept) begin

                    read_ptr <=
                        {ADDR_WIDTH{1'b0}};

                    state <= ST_REPLAY;

                end
                else begin

                    write_ptr <=
                        {ADDR_WIDTH{1'b0}};

                    read_ptr <=
                        {ADDR_WIDTH{1'b0}};

                    payload_count <=
                        {(ADDR_WIDTH+1){1'b0}};

                    state <= ST_CAPTURE;

                end

            end

        end


        // ====================================================
        // REPLAY
        // ====================================================

        else if (state == ST_REPLAY) begin

            if (replay_fire) begin

                // --------------------------------------------
                // Last byte accepted by application.
                // --------------------------------------------

                if (
                    (payload_count != 0) &&
                    (read_ptr == payload_count - 1'b1)
                ) begin

                    state <= ST_CAPTURE;

                    write_ptr <=
                        {ADDR_WIDTH{1'b0}};

                    read_ptr <=
                        {ADDR_WIDTH{1'b0}};

                    payload_count <=
                        {(ADDR_WIDTH+1){1'b0}};

                    decision_pending <=
                        1'b0;

                    decision_value <=
                        1'b0;

                end
                else begin

                    read_ptr <=
                        read_ptr + 1'b1;

                end

            end

        end

    end

end


endmodule
