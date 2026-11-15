`timescale 1ns/1ps
`default_nettype none
module tb_hist_stress;
  logic clk=0, rst=1, nms_valid=0, frame_end=0, clear=0;
  logic [10:0] thr_lo=80,thr_hi=200,nms_mag=0;
  logic [5:0] hist_rd_addr=0;
  wire [3:0] hist_rd_data,hist_nnz;
  wire hist_valid,cls_valid;
  wire [1:0] cls;
  integer counts[0:63],nnz=0, expected, i,f,b,value;
  always #5 clk=~clk;
  classify_hist #(.COUNT_W(4)) dut(.*);
  initial begin
    repeat(3) @(negedge clk); rst=0;
    for(f=0;f<8;f++) begin
      for(b=0;b<64;b++) counts[b]=0;
      nnz=0;
      thr_lo=(f==0)?0:11'(f*31); thr_hi=(f==0)?0:11'(f*100);
      for(i=0;i<2048;i++) begin
        @(negedge clk);
        nms_valid=(i%7!=1); nms_mag=11'(i); frame_end=(i==2047);
        clear=0;
        if(nms_valid && i>0) begin
          b=i/32; if(counts[b]<15) counts[b]++;
          if(nnz<15) nnz++;
        end
        expected=(i==0)?0:((i>=thr_hi)?2:((i>=thr_lo)?1:0));
        @(posedge clk); #1;
        if(cls_valid !== nms_valid || (nms_valid && cls !== 2'(expected))) $fatal(1,"class f=%0d mag=%0d got=%0d exp=%0d",f,i,cls,expected);
      end
      @(negedge clk); nms_valid=0; frame_end=0;
      if(!hist_valid || hist_nnz!=nnz) $fatal(1,"nnz saturation");
      for(b=0;b<64;b++) begin hist_rd_addr=6'(b); #0.01; if(hist_rd_data!=counts[b]) $fatal(1,"hist f=%0d b=%0d got=%0d exp=%0d",f,b,hist_rd_data,counts[b]); end
    end
    // A histogram clear must not discard an otherwise valid class output.
    @(negedge clk); nms_valid=1; nms_mag=1000; clear=1;
    @(posedge clk); #1;
    if(!cls_valid || cls!=2 || hist_valid || hist_nnz!=0) $fatal(1,"clear discarded pixel or failed to clear statistics");
    for(b=0;b<64;b++) begin hist_rd_addr=6'(b); #0.01; if(hist_rd_data!=0) $fatal(1,"clear bin"); end
    $display("PASS classifier/histogram: 16384 values, bubbles, 8 snapshots, saturation, clear during valid"); $finish;
  end
endmodule
`default_nettype wire
