`default_nettype none

// Arithmetic core for an already-aligned 3x3 window.  The line buffer and
// border controller own coordinate/valid generation.
module gauss #(
  parameter int unsigned DATA_W = 8
) (
  input  logic              clk,
  input  logic              in_valid,
  input  logic [DATA_W-1:0] w00,
  input  logic [DATA_W-1:0] w01,
  input  logic [DATA_W-1:0] w02,
  input  logic [DATA_W-1:0] w10,
  input  logic [DATA_W-1:0] w11,
  input  logic [DATA_W-1:0] w12,
  input  logic [DATA_W-1:0] w20,
  input  logic [DATA_W-1:0] w21,
  input  logic [DATA_W-1:0] w22,
  output logic              out_valid,
  output logic [DATA_W-1:0] smooth
);
  always_ff @(posedge clk) begin
    // Register the current window result.  Keeping valid in this same stage
    // prevents the one-cycle data/valid skew that a separate sum register
    // would introduce.
    smooth    <= (w00 + (w01 << 1) + w02 + (w10 << 1) + (w11 << 2) +
                  (w12 << 1) + w20 + (w21 << 1) + w22 + 8) >> 4;
    out_valid <= in_valid;
  end
endmodule

`default_nettype wire

