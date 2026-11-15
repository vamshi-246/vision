`default_nettype none

// Valid-only source timing checker and coordinate generator.  It deliberately
// does not advance during blanking: line buffers consume this same interface.
module ctrl_sync #(
  parameter int unsigned IMG_W = 640,
  parameter int unsigned IMG_H = 480,
  parameter int unsigned X_W = $clog2(IMG_W),
  parameter int unsigned Y_W = $clog2(IMG_H)
) (
  input  wire            clk,
  input  wire            rst,
  input  wire            in_valid,
  input  wire            in_sof,
  input  wire            in_eol,
  output logic [X_W-1:0] x,
  output logic [Y_W-1:0] y,
  output logic           out_valid,
  output logic           out_sof,
  output logic           out_eol,
  output logic           out_eof,
  output logic           sync_error
);
  always_comb begin
    out_valid = in_valid;
    out_sof = in_valid && in_sof;
    out_eol = in_valid && in_eol;
    out_eof = in_valid && in_eol && (y == IMG_H - 1);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      x <= '0;
      y <= '0;
      sync_error <= 1'b0;
    end else if (in_valid) begin
      if ((in_sof != ((x == '0) && (y == '0))) ||
          (in_eol != (x == X_W'(IMG_W - 1)))) begin
        sync_error <= 1'b1;
      end
      if (in_sof) begin
        x <= in_eol ? '0 : {{(X_W-1){1'b0}}, 1'b1};
        y <= in_eol ? {{(Y_W-1){1'b0}}, 1'b1} : '0;
      end else if (in_eol) begin
        x <= '0;
        y <= (y == Y_W'(IMG_H - 1)) ? '0 : y + 1'b1;
      end else begin
        x <= x + 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
