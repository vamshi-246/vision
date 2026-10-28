`timescale 1ns/1ps
`default_nettype none

// Full 640x480 image driver.  The expected map remains outside the DUT: the
// Python report compares it after simulation to make the RTL-generated output
// hex file a first-class, inspectable artefact.
module tb_image_scoreboard;
  localparam int W = 640;
  localparam int H = 480;
  localparam int PIXELS = W * H;
  logic clk = 0, rst = 1, in_valid, in_sof, in_eol, clear_hist;
  logic [7:0] in_gray;
  logic [10:0] thr_lo = 11'd80, thr_hi = 11'd200;
  logic [5:0] hist_rd_addr = 0;
  logic [18:0] hist_rd_data, hist_nnz;
  logic hist_valid, out_valid, out_sof, out_eol;
  logic [9:0] out_x;
  logic [8:0] out_y;
  logic [1:0] out_cls;
  logic [7:0] input_mem [0:PIXELS-1];
  logic [7:0] output_mem [0:PIXELS-1];
  string input_hex, output_hex;
  integer i, x, y, fd, rtl_edges;

  always #5 clk = ~clk;
  edge_pipeline dut (.*);

  initial begin
    if (!$value$plusargs("INPUT_HEX=%s", input_hex)) input_hex = "randomtests/image_input.hex";
    if (!$value$plusargs("OUT_HEX=%s", output_hex)) output_hex = "randomtests/image_rtl_output.hex";
    in_valid = 0; in_sof = 0; in_eol = 0; in_gray = 0; clear_hist = 0; rtl_edges = 0;
    for (i = 0; i < PIXELS; i = i + 1) output_mem[i] = 8'h00;
    $readmemh(input_hex, input_mem);
    repeat (2) @(posedge clk);
    rst = 0;
    for (y = 0; y < H; y = y + 1) begin
      for (x = 0; x < W; x = x + 1) begin
        @(negedge clk);
        in_valid = 1; in_sof = (x == 0 && y == 0); in_eol = (x == W - 1); in_gray = input_mem[y * W + x];
        @(posedge clk); #1;
        if (out_valid) begin
          output_mem[out_y * W + out_x] = (out_cls == 2'b10) ? 8'hff : 8'h00;
          if (out_cls == 2'b10) rtl_edges = rtl_edges + 1;
        end
      end
    end
    repeat (16) begin
      @(posedge clk); #1;
      if (out_valid) begin
        output_mem[out_y * W + out_x] = (out_cls == 2'b10) ? 8'hff : 8'h00;
        if (out_cls == 2'b10) rtl_edges = rtl_edges + 1;
      end
    end
    fd = $fopen(output_hex, "w");
    if (fd == 0) $fatal(1, "cannot open RTL output file %s", output_hex);
    for (i = 0; i < PIXELS; i = i + 1) $fdisplay(fd, "%02x", output_mem[i]);
    $fclose(fd);
    $display("RTL_IMAGE_DONE pixels=%0d strong_edges=%0d hist_nnz=%0d hist_valid=%0b", PIXELS, rtl_edges, hist_nnz, hist_valid);
    $finish;
  end
endmodule

`default_nettype wire
