`timescale 1ns/1ps
module tb_edge_video;
 parameter W=64,H=48;
 logic clk=0,rst=1;logic[3:0] switches=0;
 wire[23:0] rgb;wire de,hsync,vsync;wire[9:0] x,y;wire alignment_error,frame_pulse;wire[19:0] edge_count;
 reg[7:0] gray[0:W*H-1],smooth[0:W*H-1];reg[1:0] cls[0:W*H-1];
 integer mode=0,preset=0,seen=0,frames=0,idx,expected,expected_edges=0;string base;
 always #5 clk=~clk;
 // Stored-image source: (W/2)x(H/2) bytes, 1-cycle read latency like the BRAM.
 wire ext_thr_en=0;wire[10:0] ext_thr_lo=0,ext_thr_hi=0;wire clear_hist=0;wire[5:0] hist_rd_addr=0;wire[18:0] hist_rd_data,hist_nnz;wire hist_valid;wire[21:0] thr_used;
 logic use_image=0;logic[16:0] img_addr;logic[7:0] img_data;wire[3:0] settings_o;
 reg[7:0] half[0:W*H/4-1];integer img_mode=0;
 always @(posedge clk) img_data<=half[img_addr<W*H/4 ? img_addr : 0];
 edge_video #(.W(W),.H(H)) dut(.*);
 initial begin
  if(!$value$plusargs("BASE=%s",base)) $fatal;
  if(!$value$plusargs("MODE=%d",mode)) mode=0;
  if(!$value$plusargs("PRESET=%d",preset)) preset=0;
  switches=4'(mode | (preset<<2));
  if($value$plusargs("IMG=%d",img_mode) && img_mode) begin $readmemh({base,"/half.hex"},half);use_image=1;end
  $readmemh({base,"/gray.hex"},gray);$readmemh({base,"/smooth.hex"},smooth);$readmemh({base,"/cls.hex"},cls);
  for(integer k=0;k<W*H;k++) if(cls[k]==2) expected_edges++;
  repeat(8) @(negedge clk);rst=0;
 end
 always @(posedge clk) begin
  #1;
  if(!rst && dut.ready_video) begin
   if(de !== (x<W && y<H) || hsync !== !(x>=W+16 && x<W+112) || vsync !== !(y>=H+10 && y<H+12)) $fatal(1,"display timing");
   if(frame_pulse && edge_count!=expected_edges) $fatal(1,"edge count got=%0d expected=%0d",edge_count,expected_edges);
   if(alignment_error) $fatal(1,"alignment mode=%0d at %0d,%0d cv=%b",mode,x,y,dut.cv);
   if(de) begin
    idx=y*W+x;
    case(mode)
     0:expected={3{gray[idx]}};
     1:expected={3{smooth[idx]}};
     2:expected=(cls[idx]==2)?24'hffffff:0;
     3:expected=(cls[idx]==2)?24'hffffff:((cls[idx]==1)?24'hffbf00:0);
    endcase
    if(rgb!==24'(expected)) $fatal(1,"view %0d at %0d,%0d RGB=%h expected=%h",mode,x,y,rgb,expected);
    if(x!=seen%W || y!=seen/W) $fatal(1,"raster %0d got %0d,%0d",seen,x,y);
    seen++;
    if(seen==W*H) begin
     seen=0;frames++;
     if(frames==3) begin $display("PASS video mode=%0d img=%0d 3 frames full raster, border, RGB, core alignment",mode,img_mode);$finish;end
    end
   end else if(rgb!==0) $fatal(1,"RGB in blanking");
  end
 end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
