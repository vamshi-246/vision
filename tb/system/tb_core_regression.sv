`timescale 1ns/1ps
`default_nettype none

// Compares every spatial stage, including every class (not only strong edges).
// Sequential expected positions also detect missing/duplicate/reordered pixels.
module tb_core_regression;
  parameter integer W = 31, H = 23, FRAMES = 12;
  localparam integer N = W*H*FRAMES, XW = $clog2(W), YW = $clog2(H);
  logic clk=0, rst=1, in_valid=0, in_sof=0, in_eol=0, clear_hist=0;
  logic [7:0] in_gray=0;
  logic [10:0] thr_lo=80, thr_hi=200;
  logic [5:0] hist_rd_addr=0;
  wire [18:0] hist_rd_data, hist_nnz;
  wire hist_valid, out_valid, out_sof, out_eol;
  wire [XW-1:0] out_x;
  wire [YW-1:0] out_y;
  wire [1:0] out_cls;
  logic [7:0] pixels[0:N-1], smooth[0:N-1];
  logic [10:0] mag[0:N-1], nms[0:N-1];
  logic [1:0] dirn[0:N-1], cls[0:N-1];
  logic [18:0] hist[0:FRAMES*64-1], nnz[0:FRAMES-1];
  logic [10:0] lows[0:FRAMES-1], highs[0:FRAMES-1];
  integer gc=0, sc=0, nc=0, oc=0, mode=0, f, x, y, j, dummy;
  integer ex, ey, ef, idx;
  integer cycles=0, first_input=-1, first_output=-1;
  reg [31:0] rng=32'h76543210;
  string base;
  always #5 clk=~clk;
  edge_pipeline #(.IMG_W(W), .IMG_H(H)) dut (.smooth_valid(), .smooth_gray(), .*);

  // Map an ordered valid sample back into its full-frame reference array.
  task automatic position(input integer count, margin,
                          output integer xx, yy, ff, ii);
    integer per_frame, local_idx;
    begin
      per_frame=(W-2*margin)*(H-2*margin);
      ff=count/per_frame; local_idx=count%per_frame;
      xx=margin+local_idx%(W-2*margin);
      yy=margin+local_idx/(W-2*margin);
      ii=ff*W*H+yy*W+xx;
      if(ff>=FRAMES) $fatal(1,"extra sample margin=%0d count=%0d",margin,count);
    end
  endtask

  always @(posedge clk) begin
    cycles=cycles+1;
    if (in_valid && first_input<0) first_input=cycles;
    #1;
    if (!rst) begin
      if (dut.gauss_valid === 1'b1) begin
        position(gc,1,ex,ey,ef,idx);
        if(dut.smooth !== smooth[idx]) $fatal(1,"Gaussian f=%0d (%0d,%0d) got=%0d exp=%0d",ef,ex,ey,dut.smooth,smooth[idx]);
        if(dut.gauss_sof !== (ex==1 && ey==1) || dut.gauss_eol !== (ex==W-2)) $fatal(1,"Gaussian markers");
        gc++;
      end
      if (dut.sobel_valid === 1'b1) begin
        position(sc,2,ex,ey,ef,idx);
        if(dut.sobel_mag !== mag[idx] || dut.sobel_dir !== dirn[idx])
          $fatal(1,"Sobel f=%0d (%0d,%0d) mag=%0d/%0d dir=%0d/%0d",ef,ex,ey,dut.sobel_mag,mag[idx],dut.sobel_dir,dirn[idx]);
        if(dut.sm_sof3 !== (ex==2 && ey==2) || dut.sm_eol3 !== (ex==W-3)) $fatal(1,"Sobel markers");
        sc++;
      end
      if (dut.n_win_valid === 1'b1) begin
        position(nc,3,ex,ey,ef,idx);
        if(dut.nms_mag !== nms[idx]) $fatal(1,"NMS f=%0d (%0d,%0d) got=%0d exp=%0d",ef,ex,ey,dut.nms_mag,nms[idx]);
        nc++;
      end
      if (out_valid === 1'b1) begin
        if(first_output<0) first_output=cycles;
        position(oc,3,ex,ey,ef,idx);
        if(out_x != ex || out_y != ey || out_cls !== cls[idx])
          $fatal(1,"Output f=%0d got=(%0d,%0d) class=%0d expected=(%0d,%0d) class=%0d",ef,out_x,out_y,out_cls,ex,ey,cls[idx]);
        if(out_sof !== (ex==3 && ey==3) || out_eol !== (ex==W-4)) $fatal(1,"Output markers");
        oc++;
        if(ex==W-4 && ey==H-4) begin
          if(!hist_valid || hist_nnz !== nnz[ef]) $fatal(1,"hist nnz f=%0d got=%0d exp=%0d",ef,hist_nnz,nnz[ef]);
          for(integer b=0;b<64;b++) begin
            hist_rd_addr=6'(b); #0.001;
            if(hist_rd_data !== hist[ef*64+b]) $fatal(1,"hist bin f=%0d b=%0d got=%0d exp=%0d",ef,b,hist_rd_data,hist[ef*64+b]);
          end
        end
      end
    end
  end

  task automatic idle(input integer count);
    for(integer b=0;b<count;b++) begin
      @(negedge clk); in_valid=0; in_sof=0; in_eol=0; in_gray=8'hd3;
    end
  endtask

  initial begin
    if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE required");
    if(!$value$plusargs("MODE=%d",mode)) mode=0;
    $display("RUN mode=%0d",mode);
    $readmemh({base,"/gray.hex"},pixels); $readmemh({base,"/smooth.hex"},smooth);
    $readmemh({base,"/mag.hex"},mag); $readmemh({base,"/dir.hex"},dirn);
    $readmemh({base,"/nms.hex"},nms); $readmemh({base,"/cls.hex"},cls);
    $readmemh({base,"/hist.hex"},hist); $readmemh({base,"/nnz.hex"},nnz);
    $readmemh({base,"/lo.hex"},lows); $readmemh({base,"/hi.hex"},highs);
    repeat(6) @(negedge clk); rst=0;
    for(f=0;f<FRAMES;f++) begin
      // Thresholds change only after the preceding frame has drained.
      if(f>0 && (lows[f]!=lows[f-1] || highs[f]!=highs[f-1])) idle(20);
      thr_lo=lows[f]; thr_hi=highs[f];
      for(y=0;y<H;y++) begin
        for(x=0;x<W;x++) begin
          rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
          if(mode==1 && rng[2:0]==0) idle(1+integer'(rng[4:3]));
          @(negedge clk);
          in_valid=1; in_sof=(x==0 && y==0); in_eol=(x==W-1);
          in_gray=pixels[f*W*H+y*W+x];
        end
        if(mode==2) idle(160);
      end
      if(mode==2) idle(45*(W+160));
    end
    idle(32);
    #2;
    if(gc!=FRAMES*(W-2)*(H-2) || sc!=FRAMES*(W-4)*(H-4) || nc!=FRAMES*(W-6)*(H-6) || oc!=FRAMES*(W-6)*(H-6))
      $fatal(1,"sample counts g=%0d s=%0d n=%0d o=%0d",gc,sc,nc,oc);
    $display("PASS core W=%0d H=%0d frames=%0d mode=%0d g=%0d s=%0d n=%0d out=%0d first_latency=%0d",W,H,FRAMES,mode,gc,sc,nc,oc,first_output-first_input);
    $finish;
  end
  initial begin #2000000000; $fatal(1,"watchdog"); end
endmodule
`default_nettype wire
