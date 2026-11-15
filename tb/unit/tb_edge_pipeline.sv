`timescale 1ns/1ps
`default_nettype none

module tb_edge_pipeline;
  logic clk = 0, rst = 1, in_valid, in_sof, in_eol, clear_hist;
  logic [7:0] in_gray;
  logic [10:0] thr_lo = 80, thr_hi = 200;
  logic [5:0] hist_rd_addr = 0;
  logic [18:0] hist_rd_data, hist_nnz;
  logic hist_valid, out_valid, out_sof, out_eol;
  logic [2:0] out_x, out_y;
  logic [1:0] out_cls;
  int outputs;
  always #5 clk = ~clk;

  edge_pipeline #(.IMG_W(8), .IMG_H(8), .X_W(3), .Y_W(3)) dut (.smooth_valid(), .smooth_gray(), .*);

  initial begin : stimulus
    int x, y;
    in_valid=0; in_sof=0; in_eol=0; in_gray=0; clear_hist=0;
    repeat (2) @(posedge clk); rst=0;
    for (y=0; y<8; y++) begin
      for (x=0; x<8; x++) begin
        @(negedge clk);
        in_valid=1; in_sof=(x==0 && y==0); in_eol=(x==7); in_gray=(x >= 4) ? 8'd255 : 8'd0;
        @(posedge clk); #1;
        if (out_valid) begin
          if (out_x < 3 || out_x > 4 || out_y < 3 || out_y > 4) $fatal(1, "wrong output coordinate");
          // `model.golden.edge_frame` predicts strong pixels only at (4,3)
          // and (4,4), using the exact Appendix-A NMS tie convention.
          if (out_cls != ((out_x == 4) ? 2'b10 : 2'b00))
            $fatal(1, "golden mismatch at (%0d,%0d): class=%0b", out_x, out_y, out_cls);
          outputs++;
        end
      end
    end
    // Sobel pipeline is shorter than the following line-buffer fill, but give
    // the final registered classifier a few clocks to publish its last result.
    @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
    repeat (16) begin
      @(posedge clk); #1;
      if (out_valid) begin
        if (out_cls != ((out_x == 4) ? 2'b10 : 2'b00)) $fatal(1, "golden mismatch in flush");
        outputs++;
      end
    end
    if (outputs != 4) $fatal(1, "saw %0d final pixels, expected 4", outputs);
    if (!hist_valid || hist_nnz != 2) $fatal(1, "step-frame histogram bad");
    $display("PASS tb_edge_pipeline");
    $finish;
  end
endmodule

`default_nettype wire
