`timescale 1ns/1ps
`default_nettype none

module tb_gauss;
  logic clk = 1'b0;
  logic in_valid;
  logic [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
  logic out_valid;
  logic [7:0] smooth;

  always #5 clk = ~clk;
  gauss dut (.*);

  initial begin
    in_valid = 0;
    {w00,w01,w02,w10,w11,w12,w20,w21,w22} = '0;
    @(negedge clk);
    // Weighted sum = 255*16; exact normalisation must return 255.
    in_valid = 1;
    {w00,w01,w02,w10,w11,w12,w20,w21,w22} = {9{8'hff}};
    @(posedge clk); #1;
    if (!out_valid || smooth != 8'hff) $fatal(1, "full-scale Gaussian failed: %0d", smooth);
    @(negedge clk);
    // Centre-only contribution: (8 + rounding 8) >> 4 = 1.
    {w00,w01,w02,w10,w11,w12,w20,w21,w22} = '0;
    w11 = 8'd2;
    @(posedge clk); #1;
    if (!out_valid || smooth != 8'd1) $fatal(1, "Gaussian rounding failed: %0d", smooth);
    @(negedge clk); in_valid = 0;
    @(posedge clk); #1;
    if (out_valid) $fatal(1, "out_valid did not track input");
    $display("PASS tb_gauss");
    $finish;
  end
endmodule

`default_nettype wire
