`timescale 1ns/1ps
`default_nettype none

module tb_classify_hist;
  logic clk = 0, rst = 1, nms_valid, frame_end, clear;
  logic [10:0] thr_lo = 100, thr_hi = 200, nms_mag;
  logic [5:0] hist_rd_addr;
  logic [18:0] hist_rd_data, hist_nnz;
  logic hist_valid, cls_valid;
  logic [1:0] cls;
  always #5 clk = ~clk;

  classify_hist dut (.*);

  task automatic send(input logic [10:0] mag, input logic [1:0] expected_cls, input logic ending);
    begin
      @(negedge clk); nms_valid = 1; nms_mag = mag; frame_end = ending;
      @(posedge clk); #1;
      if (!cls_valid || cls != expected_cls)
        $fatal(1, "class mag=%0d got %0b expected %0b", mag, cls, expected_cls);
    end
  endtask

  initial begin
    nms_valid = 0; frame_end = 0; clear = 0; nms_mag = 0; hist_rd_addr = 0;
    repeat (2) @(posedge clk); rst = 0;
    send(11'd99,  2'b00, 0);
    send(11'd100, 2'b01, 0);
    send(11'd200, 2'b10, 0);
    send(11'd2047,2'b10, 1);
    @(negedge clk); nms_valid = 0; frame_end = 0;
    if (!hist_valid || hist_nnz != 4) $fatal(1, "hist snapshot invalid or Nnz=%0d", hist_nnz);
    hist_rd_addr = 6'd3; #1;
    if (hist_rd_data != 2) $fatal(1, "bin 3=%0d expected 2", hist_rd_data);
    hist_rd_addr = 6'd6; #1;
    if (hist_rd_data != 1) $fatal(1, "bin 6=%0d expected 1", hist_rd_data);
    hist_rd_addr = 6'd63; #1;
    if (hist_rd_data != 1) $fatal(1, "bin 63=%0d expected 1", hist_rd_data);
    // A second frame uses the other bank and must not retain its predecessor.
    send(11'd32, 2'b00, 1);
    @(negedge clk); nms_valid = 0; frame_end = 0;
    hist_rd_addr = 6'd1; #1;
    if (hist_nnz != 1 || hist_rd_data != 1) $fatal(1, "ping-pong snapshot failed");
    $display("PASS tb_classify_hist");
    $finish;
  end
endmodule

`default_nettype wire
