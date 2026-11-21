`timescale 1ns/1ps
// Hardware/software comparison: the software edge pipeline (fw/swedge/swedge.c) on PicoRV32 with the SAME core
// parameters and the same 1-wait-state memory timing as rtl/soc/cpu_subsys.sv.  Counts clocks between the firmware's
// start and done markers and checks every class against the golden model.
module tb_swedge;
  localparam W = 32, H = 24;
  logic clk = 0, resetn = 0; always #5 clk = ~clk;
  wire mem_valid, mem_instr; logic mem_ready = 0; wire [31:0] mem_addr, mem_wdata; wire [3:0] mem_wstrb; logic [31:0] mem_rdata;
  wire trap;
  picorv32 #(.ENABLE_COUNTERS(0),.ENABLE_COUNTERS64(0),.ENABLE_REGS_16_31(1),.ENABLE_REGS_DUALPORT(1),.BARREL_SHIFTER(0),
    .TWO_STAGE_SHIFT(1),.COMPRESSED_ISA(0),.ENABLE_MUL(0),.ENABLE_DIV(0),.ENABLE_IRQ(0),.CATCH_MISALIGN(1),.CATCH_ILLINSN(1),
    .PROGADDR_RESET(32'h0),.STACKADDR(32'h2000)) cpu (.clk, .resetn, .trap, .mem_valid, .mem_instr, .mem_ready, .mem_addr, .mem_wdata,
    .mem_wstrb, .mem_rdata, .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(), .pcpi_valid(),
    .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(), .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0), .irq(32'd0), .eoi(),
    .trace_valid(), .trace_data());
  logic [31:0] mem [0:4095];
  logic [7:0] img [0:W*H-1]; logic [7:0] expc [0:W*H-1];
  longint cyc = 0, t_start = -1, t_done = -1, instr = 0;
  string fw, base;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin            // one wait state, like cpu_subsys (ready one clock after the request)
      mem_ready <= 1;
      if (mem_instr) instr <= instr + 1;
      if (mem_addr == 32'h3000_0000) begin
        if (|mem_wstrb && mem_wdata == 1) t_start <= cyc;
        if (|mem_wstrb && mem_wdata == 2) t_done <= cyc;
      end else begin
        mem_rdata <= mem[mem_addr[13:2]];
        for (int b = 0; b < 4; b++) if (mem_wstrb[b]) mem[mem_addr[13:2]][8*b +: 8] <= mem_wdata[8*b +: 8];
      end
    end
  end
  initial begin
    int bad = 0;
    if (!$value$plusargs("FW=%s", fw)) $fatal(1, "FW");
    if (!$value$plusargs("BASE=%s", base)) $fatal(1, "BASE");
    for (int i = 0; i < 4096; i++) mem[i] = 0;
    $readmemh(fw, mem);
    $readmemh({base, "/img.hex"}, img); $readmemh({base, "/cls.hex"}, expc);
    for (int i = 0; i < W*H; i++) mem[(32'h2000 + i) >> 2][8*(i%4) +: 8] = img[i];
    repeat (5) @(posedge clk); resetn <= 1;
    wait (t_done >= 0 || trap); repeat (3) @(posedge clk);
    for (int i = 0; i < W*H; i++) if (mem[(32'h2400 + i) >> 2][8*(i%4) +: 8] !== expc[i]) bad++;
    if (!trap && bad == 0)
      $display("PASS swedge %0dx%0d cycles=%0d instr_fetches=%0d cycles_per_pixel=%0.1f classes_checked=%0d", W, H, t_done - t_start, instr,
               real'(t_done - t_start) / (W*H), W*H);
    else $display("FAIL swedge trap=%0d mismatches=%0d", trap, bad);
    $finish;
  end
  initial begin #2_000_000_000; $display("FAIL swedge watchdog"); $finish; end
endmodule
