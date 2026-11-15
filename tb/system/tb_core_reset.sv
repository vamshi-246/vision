`timescale 1ns/1ps
`default_nettype none
module tb_core_reset;
  localparam W=17, H=13;
  logic clk=0, rst=1, in_valid=0, in_sof=0, in_eol=0, clear_hist=0;
  logic [7:0] in_gray=0;
  logic [10:0] thr_lo=80, thr_hi=200;
  logic [5:0] hist_rd_addr=0;
  wire [18:0] hist_rd_data, hist_nnz;
  wire hist_valid, out_valid, out_sof, out_eol;
  wire [4:0] out_x;
  wire [3:0] out_y;
  wire [1:0] out_cls;
  integer outputs=0, trial, p, watch=0;
  always #5 clk=~clk;
  edge_pipeline #(.IMG_W(W),.IMG_H(H)) dut(.smooth_valid(), .smooth_gray(), .*);
  always @(posedge clk) begin
    #1;
    if(watch && !rst && out_valid) begin
      if(out_cls !== 0 || out_x != 3+outputs%(W-6) || out_y != 3+outputs/(W-6))
        $fatal(1,"reset recovery trial=%0d pixel=%0d got (%0d,%0d) class=%0d",trial,outputs,out_x,out_y,out_cls);
      outputs++;
    end
  end
  task automatic pixel(input integer pos, input logic [7:0] value);
    @(negedge clk); in_valid=1; in_sof=(pos==0); in_eol=(pos%W==W-1); in_gray=value;
  endtask
  initial begin
    repeat(6) @(negedge clk); rst=0;
    for(trial=0;trial<40;trial++) begin
      watch=0;
      for(p=0;p<80+trial*3;p++) pixel(p,8'(p*137));
      @(negedge clk); rst=1; in_valid=0; in_sof=0; in_eol=0;
      @(negedge clk); rst=0; watch=1; outputs=0;
      for(p=0;p<W*H;p++) pixel(p,0);
      @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
      repeat(24) @(negedge clk);
      if(outputs!=(W-6)*(H-6) || !hist_valid || hist_nnz!=0)
        $fatal(1,"reset trial=%0d count=%0d nnz=%0d",trial,outputs,hist_nnz);
    end
    $display("PASS core reset: 40 abort positions, one-cycle reset, immediate restart"); $finish;
  end
endmodule
`default_nettype wire
