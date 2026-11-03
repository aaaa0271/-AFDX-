module bag_regulator #(
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    parameter BAG_CYCLES = 400000
)(
    input  wire clk,
    input  wire rst,

    input  wire send_request,
    output wire send_grant
);

reg [31:0] bag_counter;


// A frame can be granted only when:
// 1. a send request exists
// 2. BAG timer has expired
assign send_grant =
        send_request &&
        (bag_counter == 32'd0);


always @(posedge clk) begin

    if (rst) begin

        bag_counter <= 32'd0;

    end
    else begin

        // A frame is granted.
        // Reload BAG timer.
        if (send_grant) begin

            bag_counter <= BAG_CYCLES - 1;

        end

        // Count down until transmission is allowed again.
        else if (bag_counter != 32'd0) begin

            bag_counter <= bag_counter - 1'b1;

        end

    end

end

endmodule
