// rgb2gray -- gray = (77*R + 150*G + 29*B) >> 8, shift-add only (coefficients sum to 256).
//   77 = 64+8+4+1   150 = 128+16+4+2   29 = 16+8+4+1.  Two register stages, II = 1.
// The demo path stores gray images (camera path not built), so core_top takes gray; this block is the
// "grayscale" stage of the spec for an RGB source and is unit-tested against golden.rgb_to_gray.
module rgb2gray (
  input  logic       clk,
  input  logic [7:0] r, g, b,
  output logic [7:0] y
);
  logic [15:0] pr, pg, pb;
  always_ff @(posedge clk) begin
    pr <= ({8'b0, r} << 6) + ({8'b0, r} << 3) + ({8'b0, r} << 2) + {8'b0, r};
    pg <= ({8'b0, g} << 7) + ({8'b0, g} << 4) + ({8'b0, g} << 2) + ({8'b0, g} << 1);
    pb <= ({8'b0, b} << 4) + ({8'b0, b} << 3) + ({8'b0, b} << 2) + {8'b0, b};
    y  <= 8'((pr + pg + pb) >> 8);
  end
endmodule
