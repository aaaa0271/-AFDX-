module elab_615a_download_top;
  reg clk, rst, upload_busy, package_valid;
  reg [2:0] file_count;
  reg [255:0] read_name;
  reg [15:0] read_length;
  reg [7:0] read_data;
  reg rx_valid;
  reg [31:0] rx_ip;
  reg [15:0] rx_sport, rx_dport;
  reg [10:0] rx_length;
  reg [4127:0] rx_bytes;
  reg tx_ready;
  wire [1:0] read_file;
  wire [15:0] read_address;
  wire tx_valid;
  wire [31:0] tx_ip;
  wire [15:0] tx_sport, tx_dport;
  wire [10:0] tx_length;
  wire [4127:0] tx_bytes;
  wire active, idle, complete, failed;

  afdx_615a_download #(.TIMEOUT_CYCLES(1000), .CLK_HZ(1000)) dut (
    .clk(clk), .rst(rst), .loader_ip(32'd0), .upload_busy(upload_busy),
    .package_valid(package_valid), .file_count(file_count),
    .read_file(read_file), .read_address(read_address),
    .read_name(read_name), .read_length(read_length), .read_data(read_data),
    .rx_valid(rx_valid), .rx_ip(rx_ip), .rx_sport(rx_sport), .rx_dport(rx_dport),
    .rx_length(rx_length), .rx_bytes(rx_bytes),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_ip(tx_ip),
    .tx_sport(tx_sport), .tx_dport(tx_dport), .tx_length(tx_length), .tx_bytes(tx_bytes),
    .active(active), .idle(idle), .complete(complete), .failed(failed)
  );

  initial begin
    clk = 0; rst = 0; upload_busy = 0; package_valid = 0; file_count = 0;
    read_name = 0; read_length = 0; read_data = 0;
    rx_valid = 0; rx_ip = 0; rx_sport = 0; rx_dport = 0; rx_length = 0; rx_bytes = 0;
    tx_ready = 0;
  end
endmodule
