// paper_frame_buffer.sv -- simple dual-port, BRAM-style frame store (1 write port, 1 read port).
// One 8-bit magnitude per pixel, W*H deep.  Read data is registered (1-cycle latency).
// Default 64x64 for simulation; synchronous-read style so it can map to block RAM later.
module paper_frame_buffer #(
  parameter int W  = 64,
  parameter int H  = 64,
  parameter int AW = (W*H > 1) ? $clog2(W*H) : 1
) (
  input  logic          clk,
  input  logic          we,
  input  logic [AW-1:0] waddr,
  input  logic [7:0]    wdata,
  input  logic [AW-1:0] raddr,
  output logic [7:0]    rdata
);
  logic [7:0] mem [0:W*H-1];

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
