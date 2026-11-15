`timescale 1ns/1ps
`default_nettype none
// No hierarchical DUT references: usable with Vivado's synthesized netlist.
module tb_core_netlist;
  localparam W=640,H=480,F=2,N=W*H*F;
  logic clk=0,rst=1,in_valid=0,in_sof=0,in_eol=0,clear_hist=0;
  logic [7:0] in_gray=0;
  logic [10:0] thr_lo=80,thr_hi=200;
  logic [5:0] hist_rd_addr=0;
  wire [18:0] hist_rd_data,hist_nnz;
  wire hist_valid,out_valid,out_sof,out_eol;
  wire [9:0] out_x;
  wire [8:0] out_y;
  wire [1:0] out_cls;
  logic [7:0] pixels[0:N-1];
  logic [1:0] expected[0:N-1];
  logic [18:0] hist[0:F*64-1],nnz[0:F-1];
  integer p,f,x,y,oc=0,ex,ey,ef;
  string base;
  always #5 clk=~clk;
  edge_pipeline dut(.smooth_valid(), .smooth_gray(), .*);
  always @(posedge clk) begin
    #1;
    if(!rst && out_valid) begin
      ef=oc/((W-6)*(H-6));
      ex=3+oc%(W-6); ey=3+(oc%((W-6)*(H-6)))/(W-6);
      if(ef>=F || out_x!=ex || out_y!=ey || out_cls !== expected[ef*W*H+ey*W+ex])
        $fatal(1,"netlist output index=%0d got=(%0d,%0d) cls=%0d expected=(%0d,%0d)",oc,out_x,out_y,out_cls,ex,ey);
      if(out_sof !== (ex==3 && ey==3) || out_eol !== (ex==W-4)) $fatal(1,"netlist markers");
      oc++;
      if(ex==W-4 && ey==H-4) begin
        if(!hist_valid || hist_nnz !== nnz[ef]) $fatal(1,"netlist nnz");
        for(integer b=0;b<64;b++) begin hist_rd_addr=6'(b); #0.001; if(hist_rd_data !== hist[ef*64+b]) $fatal(1,"netlist hist"); end
      end
    end
  end
  initial begin
    if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE required");
    $readmemh({base,"/gray.hex"},pixels); $readmemh({base,"/cls.hex"},expected);
    $readmemh({base,"/hist.hex"},hist); $readmemh({base,"/nnz.hex"},nnz);
    // Xilinx glbl holds GSR active for the first 100 ns.
    repeat(20) @(negedge clk); rst=0;
    for(f=0;f<F;f++) for(y=0;y<H;y++) for(x=0;x<W;x++) begin
      @(negedge clk); in_valid=1; in_sof=(x==0 && y==0); in_eol=(x==W-1);
      in_gray=pixels[f*W*H+y*W+x];
    end
    @(negedge clk); in_valid=0;in_sof=0;in_eol=0;
    repeat(32) @(negedge clk);
    if(oc!=F*(W-6)*(H-6)) $fatal(1,"netlist count=%0d",oc);
    $display("PASS synthesized netlist: 2 consecutive VGA frames, %0d classes, markers and histograms",oc); $finish;
  end
  initial begin #10000000; $fatal(1,"netlist watchdog"); end
endmodule
`default_nettype wire
