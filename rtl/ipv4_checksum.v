module ipv4_checksum (
    input  wire [31:0] src_ip,
    input  wire [31:0] dst_ip,
    input  wire [15:0] total_length,

    output reg  [15:0] checksum
);

reg [31:0] sum;

always @(*) begin

    sum = 32'd0;

    // Version = 4, IHL = 5
    // DSCP / ECN = 0
    sum = sum + 16'h4500;

    // Total Length
    sum = sum + total_length;

    // Identification
    sum = sum + 16'h0000;

    // Flags + Fragment Offset
    sum = sum + 16'h0000;

    // TTL = 64, Protocol = UDP(17)
    sum = sum + 16'h4011;

    // Header checksum field itself is zero
    sum = sum + 16'h0000;

    // Source IP
    sum = sum + src_ip[31:16];
    sum = sum + src_ip[15:0];

    // Destination IP
    sum = sum + dst_ip[31:16];
    sum = sum + dst_ip[15:0];


    // Fold carry bits back into lower 16 bits
    sum = (sum & 32'h0000FFFF)
        + (sum >> 16);

    sum = (sum & 32'h0000FFFF)
        + (sum >> 16);


    // One's complement
    checksum = ~sum[15:0];

end

endmodule
