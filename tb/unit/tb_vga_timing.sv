`timescale 1ns/1ps
`default_nettype none

module tb_vga_timing;
  logic clk = 1'b0;
  logic rst = 1'b1;
  logic [2:0] h_count, v_count;
  logic de, hsync, vsync, sof, eol, eof;
  int active_count, hs_low_count, vs_low_count, sof_count, eol_count, eof_count;

  always #5 clk = ~clk;

  vga_timing #(
    .H_ACTIVE(4), .H_FP(1), .H_SYNC(2), .H_BP(1),
    .V_ACTIVE(3), .V_FP(1), .V_SYNC(1), .V_BP(1)
  ) dut (
    .clk, .rst, .h_count, .v_count, .de, .hsync, .vsync, .sof, .eol, .eof
  );

  initial begin
    repeat (2) @(posedge clk);
    rst = 1'b0;
    // Sample all 8x6 positions after their registered outputs settle.
    repeat (48) begin
      @(posedge clk); #1;
      active_count += de;
      hs_low_count += !hsync;
      vs_low_count += !vsync;
      sof_count += sof;
      eol_count += eol;
      eof_count += eof;
    end
    if (active_count != 12) $fatal(1, "DE count %0d, expected 12", active_count);
    if (hs_low_count != 12) $fatal(1, "HS low count %0d, expected 12", hs_low_count);
    if (vs_low_count != 8)  $fatal(1, "VS low count %0d, expected 8", vs_low_count);
    if (sof_count != 1 || eol_count != 3 || eof_count != 1)
      $fatal(1, "markers sof/eol/eof=%0d/%0d/%0d", sof_count, eol_count, eof_count);
    $display("PASS tb_vga_timing");
    $finish;
  end
endmodule

`default_nettype wire
