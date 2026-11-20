`timescale 1ns/1ps
`default_nettype none
// Live-input path check: 800x600@60 raster (1056x628 total, DE-only timing, reset released mid-frame) -> rx_timing -> rx_downscale
// -> async FIFO -> word writes into a 320x240 byte array on a 25 MHz clock (pop only on some cycles, like the frame store).
// Expected: byte (xd,yd) = gray of source pixel (sx,sy), sx = (xd/2)*5 + (xd%2)*2, same for y; gray = (77R+150G+29B)>>8.
module tb_rx_live;
 localparam int W=800,H=600,HT=1056,VT=628,DW=320,DH=240;
 logic rclk=0,wclk=0,rrst=1;
 always #12.5 rclk=~rclk;   // 40 MHz
 always #19.86 wclk=~wclk;  // 25.175 MHz
 logic [23:0] rgb;logic de,hs,vs;
 wire [9:0] lx,ly;wire lde,lhs,lvs,lsof,leol,tbad;wire [7:0] lgray;
 rx_timing #(.W(W),.H(H),.HT(HT)) front(.clk(rclk),.rst(rrst),.rgb,.de,.hs,.vs,.x(lx),.y(ly),.o_de(lde),.o_hs(lhs),.o_vs(lvs),
  .o_sof(lsof),.o_eol(leol),.gray(lgray),.timing_bad(tbad));
 logic pop;wire valid;wire [14:0] waddr;wire [31:0] wdata;
 rx_downscale dut(.rclk,.rrst,.de(lde),.x(lx),.y(ly),.gray(lgray),.wclk,.pop,.valid,.waddr,.wdata);
 function automatic [23:0] src(input int x,input int y,input int f);
  return {8'(x*3+y+f*7),8'(x^y),8'(y*5+x/3+f)};
 endfunction
 function automatic [7:0] g(input [23:0] c);
  return 8'((77*c[23:16]+150*c[15:8]+29*c[7:0])>>8);
 endfunction
 // raster source; frame counter f changes the content every frame
 int hc=0,vc=0,f=0;
 always_ff @(posedge rclk) begin
  if(hc==HT-1) begin hc<=0; if(vc==VT-1) begin vc<=0;f<=f+1;end else vc<=vc+1;end else hc<=hc+1;
 end
 always_comb begin
  de=(hc<W)&&(vc<H);hs=(hc>=W+40)&&(hc<W+40+128);vs=(vc>=H+1)&&(vc<H+1+4);
  rgb=de?src(hc,vc,f):24'h0;
 end
 // frame-store model with a busy pattern (no pop on 1 cycle in 3)
 logic [7:0] mem[DW*DH];int cyc=0;int writes=0;
 always_ff @(posedge wclk) begin
  cyc<=cyc+1;
  if(pop && valid) begin for(int b=0;b<4;b++) mem[waddr*4+b]<=wdata[8*b+:8];writes<=writes+1;end
 end
 assign pop=(cyc%3)!=0;
 initial begin
  int errs,fchk,sx,sy;
  // release the reset in the middle of frame 0 (line 200)
  wait(vc==200 && hc==300); @(posedge rclk) rrst<=0;
  // frame 1 is the first complete frame; check right after it has been written (end of its active area + drain time)
  wait(f==1 && vc==H+10); repeat(200) @(posedge wclk);
  fchk=1;errs=0;
  for(int yd=0;yd<DH;yd++) for(int xd=0;xd<DW;xd++) begin
   sx=(xd/2)*5+(xd%2)*2;sy=(yd/2)*5+(yd%2)*2;
   if(mem[yd*DW+xd]!==g(src(sx,sy,fchk))) begin
    if(errs<10) $display("MISMATCH (%0d,%0d): got %0d exp %0d",xd,yd,mem[yd*DW+xd],g(src(sx,sy,fchk)));
    errs++;
   end
  end
  $display("frame %0d: %0d word writes so far, %0d byte mismatches, timing_bad=%0d",fchk,writes,errs,tbad);
  if(errs==0 && !tbad) $display("TB_RX_LIVE PASS"); else $display("TB_RX_LIVE FAIL");
  $finish;
 end
 initial begin #60ms; $display("TB_RX_LIVE FAIL timeout"); $finish; end
endmodule
`default_nettype wire
