`default_nettype none

// Arithmetic core for an already-aligned 3x3 window.  The line buffer and
// border controller own coordinate/valid generation.
module gauss #(
  parameter int unsigned DATA_W = 8
) (
  input  wire               clk,
  input  wire               in_valid,
  input  wire  [DATA_W-1:0] w00,
  input  wire  [DATA_W-1:0] w01,
  input  wire  [DATA_W-1:0] w02,
  input  wire  [DATA_W-1:0] w10,
  input  wire  [DATA_W-1:0] w11,
  input  wire  [DATA_W-1:0] w12,
  input  wire  [DATA_W-1:0] w20,
  input  wire  [DATA_W-1:0] w21,
  input  wire  [DATA_W-1:0] w22,
  output logic              out_valid,
  output logic [DATA_W-1:0] smooth
);
  localparam int unsigned SUM_W = DATA_W + 4;
  logic [SUM_W-1:0] weighted_sum;
  always_comb begin
    weighted_sum = SUM_W'(w00) + (SUM_W'(w01) << 1) + SUM_W'(w02) +
                   (SUM_W'(w10) << 1) + (SUM_W'(w11) << 2) + (SUM_W'(w12) << 1) +
                   SUM_W'(w20) + (SUM_W'(w21) << 1) + SUM_W'(w22) + SUM_W'(8);
  end
  always_ff @(posedge clk) begin
    // Register the current window result.  Keeping valid in this same stage
    // prevents the one-cycle data/valid skew that a separate sum register
    // would introduce.
    smooth    <= weighted_sum[SUM_W-1:4];
    out_valid <= in_valid;
  end
endmodule

`default_nettype wire

