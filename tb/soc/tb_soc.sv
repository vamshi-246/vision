`timescale 1ns/1ps
// Acceptance test: real firmware on PicoRV32 inside video_soc.  The firmware-published mailbox (edge count, thresholds in
// effect, 64 histogram bins) must equal the Python model for the stored image, for switch presets, the no-CPU fallback and
// a host-written threshold override.
module tb_soc #(parameter W=64,H=48);
 logic clk=0,rst=1;logic[3:0] switches=0;logic cpu_run=0;
 wire[23:0] rgb;wire de,hsync,vsync,alignment_error,frame_pulse,cpu_trap;wire[19:0] edge_count;
 logic use_image=1;wire[16:0] img_addr;logic[7:0] img_data;wire[3:0] settings;wire[21:0] thr_used;wire[31:0] frames;
 logic h_ram_en=0;logic[3:0] h_ram_we=0;logic[10:0] h_ram_addr=0;logic[31:0] h_ram_wdata=0;wire[31:0] h_ram_rdata;
 logic h_mb_en=0;logic[3:0] h_mb_we=0;logic[7:0] h_mb_addr=0;logic[31:0] h_mb_wdata=0;wire[31:0] h_mb_rdata;
 always #20 clk=~clk;
 video_soc #(.W(W),.H(H)) dut(.*);
 reg[7:0] half[0:W*H/4-1];
 always @(posedge clk) img_data<=half[img_addr<W*H/4?img_addr:0];
 // expected values from the model: 4 presets + override pair; one 64-bin histogram
 integer exp_edges[0:4];reg[31:0] exp_hist[0:63];integer exp_lo[0:4],exp_hi[0:4];
 integer errors=0,phase_frames,pub0,fd,r,seen;string base;
 function automatic [31:0] mb(input integer i);return dut.cpu.mbox.mem[i];endfunction
 task automatic wait_published(input integer n);
  integer start;start=mb(2);
  while(mb(2)<start+n) @(posedge clk);
 endtask
 task automatic check(input string name,input integer idx);
  integer i,bad;
  wait_published(6);
  // consecutive stable records
  while(dut.cpu.mbox.mem[1][0]) @(posedge clk);
  bad=0;
  if(mb(0)!==32'h5037C0DE) begin bad++;$display("  magic %h",mb(0));end
  if(mb(5)!==exp_lo[idx]||mb(6)!==exp_hi[idx]) begin bad++;$display("  thr used %0d/%0d expected %0d/%0d",mb(5),mb(6),exp_lo[idx],exp_hi[idx]);end
  if(mb(4)!==exp_edges[idx]) begin bad++;$display("  edges %0d expected %0d",mb(4),exp_edges[idx]);end
  for(i=0;i<64;i++) if(mb(16+i)!==exp_hist[i]) begin bad++;if(bad<6)$display("  hist[%0d]=%0d expected %0d",i,mb(16+i),exp_hist[i]);end
  if(alignment_error) begin bad++;$display("  alignment error");end
  if(cpu_trap) begin bad++;$display("  CPU TRAP");end
  if(bad) begin errors++;$display("FAIL %s (%0d mismatches)",name,bad);end
  else $display("ok   %s: edges=%0d thr=%0d/%0d, 64 hist bins match model, frames published=%0d",name,mb(4),mb(5),mb(6),mb(2));
 endtask
 initial begin
  if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE");
  $readmemh({base,"/half.hex"},half);
  $readmemh({base,"/exp.hex"},exp_hist);   // 64 hist bins
  fd=$fopen({base,"/exp.txt"},"r");
  for(int k=0;k<5;k++) begin r=$fscanf(fd,"%d %d %d\n",exp_lo[k],exp_hi[k],exp_edges[k]);end
  $fclose(fd);
  repeat(8) @(negedge clk);rst=0;
  // ---- phase A: CPU held in reset -> hardware preset fallback, preset 0
  repeat(3*(W+160)*(H+45)) @(posedge clk);
  begin
   seen=0;
   repeat(2*(W+160)*(H+45)) begin @(posedge clk);if(frame_pulse) begin seen++;
    if(edge_count!==exp_edges[0]) begin errors++;$display("FAIL fallback edge_count=%0d expected %0d",edge_count,exp_edges[0]);end end end
   if(seen<1) begin errors++;$display("FAIL fallback saw no frame");end else $display("ok   hardware fallback (CPU in reset): edge_count=%0d for preset 0",edge_count);
  end
  // ---- load firmware over the host port while the CPU is in reset, then run
  $readmemh({base,"/fw.hex"},dut.cpu.ram.mem);
  cpu_run=1;
  check("CPU run, switches=0 (preset 0)",0);
  switches=4'b1000;check("switches SW3:2=2 (preset 2)",2);
  switches=4'b0100;check("switches SW3:2=1 (preset 1)",1);
  switches=4'b1100;check("switches SW3:2=3 (preset 3)",3);
  // ---- host override through the mailbox (host port B)
  @(negedge clk);h_mb_en=1;h_mb_we=4'hf;h_mb_addr=8'd129;h_mb_wdata=exp_lo[4];@(negedge clk);
  h_mb_addr=8'd130;h_mb_wdata=exp_hi[4];@(negedge clk);h_mb_addr=8'd128;h_mb_wdata=1;@(negedge clk);h_mb_en=0;h_mb_we=0;
  check("host override",4);
  if(errors==0) $display("PASS soc: firmware on PicoRV32 matches the model (edge count, thresholds, 64-bin histogram) in 6 scenarios");
  else $display("FAIL soc: %0d scenario(s) failed",errors);
  $finish;
 end
 initial begin #400_000_000;$display("FAIL soc: watchdog");$finish;end
endmodule
