`default_nettype none
// Operator-library characterisation wrappers (hls/sobel_hls.py unit-delay model is checked against these).
// Every operator is register-to-register so the routed path = clk-to-q + operator + setup.
module op_sub9 (input wire clk, input wire [7:0] a, b, output logic signed [9:0] y);
  logic [7:0] ra, rb; always_ff @(posedge clk) begin ra <= a; rb <= b; y <= $signed({1'b0,ra}) - $signed({1'b0,rb}); end
endmodule
module op_add11 (input wire clk, input wire signed [10:0] a, b, output logic signed [10:0] y);
  logic signed [10:0] ra, rb; always_ff @(posedge clk) begin ra <= a; rb <= b; y <= ra + rb; end
endmodule
module op_abs11 (input wire clk, input wire signed [10:0] a, output logic [10:0] y);
  logic signed [10:0] ra; always_ff @(posedge clk) begin ra <= a; y <= ra < 0 ? -ra : ra; end
endmodule
module op_mul13 (input wire clk, input wire [10:0] a, output logic [15:0] y);
  logic [10:0] ra; always_ff @(posedge clk) begin ra <= a; y <= ({5'b0,ra} << 3) + ({5'b0,ra} << 2) + {5'b0,ra}; end
endmodule
module op_cmp16 (input wire clk, input wire [15:0] a, b, output logic y);
  logic [15:0] ra, rb; always_ff @(posedge clk) begin ra <= a; rb <= b; y <= ra <= rb; end
endmodule
module op_alu16 (input wire clk, input wire signed [15:0] a, b, input wire sub, output logic signed [15:0] y, output logic le);
  logic signed [15:0] ra, rb; logic rs;
  always_ff @(posedge clk) begin ra <= a; rb <= b; rs <= sub; y <= rs ? ra - rb : ra + rb; le <= ra <= rb; end
endmodule
module op_abs16 (input wire clk, input wire signed [15:0] a, output logic signed [15:0] y);
  logic signed [15:0] ra; always_ff @(posedge clk) begin ra <= a; y <= ra < 0 ? -ra : ra; end
endmodule
module op_mag_cmp_chain (input wire clk, input wire [10:0] ax, ay, output logic [10:0] mag, output logic c0);
  // the chained stage-3 work of the shipped sobel.sv: |Gx|+|Gy| and 32|Gy| <= 13|Gx| in one clock
  logic [10:0] rx, ry; always_ff @(posedge clk) begin rx <= ax; ry <= ay; mag <= rx + ry;
    c0 <= ({5'b0,ry} << 5) <= (({5'b0,rx} << 3) + ({5'b0,rx} << 2) + {5'b0,rx}); end
endmodule
`default_nettype wire
