`default_nettype none
// PicoRV32 (RV32I) with 8 KB RAM, a 1 KB host-visible mailbox, a GPIO input word and an APB3 master.
//
// CPU address map                          Host (AXI) side
//   0x0000_0000  RAM 8 KB (code+data)      port B of the same RAM (load firmware while run=0)
//   0x1000_0000  APB3 master (256 B)       -> apb_regs
//   0x2000_0000  mailbox 1 KB              port B of the mailbox RAM (host reads results / writes commands)
//   0x3000_0000  GPIO input word           read-only
// `run`=0 holds the CPU in reset so the host can load firmware; the video pipeline keeps working without the CPU.
module cpu_subsys(
 input wire clk,input wire run,
 output wire psel,penable,pwrite,output wire [7:0] paddr,output wire [31:0] pwdata,input wire [31:0] prdata,input wire pready,
 input wire [31:0] gpio_in,
 input wire h_ram_en,input wire [3:0] h_ram_we,input wire [10:0] h_ram_addr,input wire [31:0] h_ram_wdata,output wire [31:0] h_ram_rdata,
 input wire h_mb_en,input wire [3:0] h_mb_we,input wire [7:0] h_mb_addr,input wire [31:0] h_mb_wdata,output wire [31:0] h_mb_rdata,
 output wire trap);
 (* ASYNC_REG="TRUE" *) logic [1:0] run_sync=0;
 always_ff @(posedge clk) run_sync<={run_sync[0],run};
 wire resetn=run_sync[1];
 wire mem_valid,mem_instr;logic mem_ready;wire [31:0] mem_addr,mem_wdata;wire [3:0] mem_wstrb;logic [31:0] mem_rdata;
 picorv32 #(.ENABLE_COUNTERS(0),.ENABLE_COUNTERS64(0),.ENABLE_REGS_16_31(1),.ENABLE_REGS_DUALPORT(1),.BARREL_SHIFTER(0),
  .TWO_STAGE_SHIFT(1),.COMPRESSED_ISA(0),.ENABLE_MUL(0),.ENABLE_DIV(0),.ENABLE_IRQ(0),.CATCH_MISALIGN(1),.CATCH_ILLINSN(1),
  .PROGADDR_RESET(32'h0000_0000),.STACKADDR(32'h0000_2000)) cpu(
  .clk,.resetn,.trap,.mem_valid,.mem_instr,.mem_ready,.mem_addr,.mem_wdata,.mem_wstrb,.mem_rdata,
  .mem_la_read(),.mem_la_write(),.mem_la_addr(),.mem_la_wdata(),.mem_la_wstrb(),.pcpi_valid(),.pcpi_insn(),.pcpi_rs1(),.pcpi_rs2(),
  .pcpi_wr(1'b0),.pcpi_rd(32'd0),.pcpi_wait(1'b0),.pcpi_ready(1'b0),.irq(32'd0),.eoi(),.trace_valid(),.trace_data());
 wire sel_ram=mem_valid && mem_addr[31:28]==4'h0;
 wire sel_apb=mem_valid && mem_addr[31:28]==4'h1;
 wire sel_mb =mem_valid && mem_addr[31:28]==4'h2;
 wire sel_gpio=mem_valid && mem_addr[31:28]==4'h3;
 logic ready_q=0;
 wire fast_issue=(sel_ram||sel_mb||sel_gpio) && !ready_q;
 always_ff @(posedge clk) ready_q<=resetn && fast_issue;
 wire [31:0] ram_rdata,mb_rdata;
 soc_ram #(.DEPTH(2048),.AW(11)) ram(.clk,
  .a_en(sel_ram && !ready_q),.a_we(mem_wstrb),.a_addr(mem_addr[12:2]),.a_wdata(mem_wdata),.a_rdata(ram_rdata),
  .b_en(h_ram_en),.b_we(h_ram_we),.b_addr(h_ram_addr),.b_wdata(h_ram_wdata),.b_rdata(h_ram_rdata));
 soc_ram #(.DEPTH(256),.AW(8)) mbox(.clk,
  .a_en(sel_mb && !ready_q),.a_we(mem_wstrb),.a_addr(mem_addr[9:2]),.a_wdata(mem_wdata),.a_rdata(mb_rdata),
  .b_en(h_mb_en),.b_we(h_mb_we),.b_addr(h_mb_addr),.b_wdata(h_mb_wdata),.b_rdata(h_mb_rdata));
 // APB3 master: SETUP -> ACCESS, one transfer at a time.
 typedef enum logic [1:0] {A_IDLE,A_SETUP,A_ACCESS} astate_t;
 astate_t ast=A_IDLE;
 always_ff @(posedge clk) begin
  if(!resetn) ast<=A_IDLE;
  else case(ast)
   A_IDLE: if(sel_apb) ast<=A_SETUP;
   A_SETUP: ast<=A_ACCESS;
   A_ACCESS: if(pready) ast<=A_IDLE;
   default: ast<=A_IDLE;
  endcase
 end
 assign psel=(ast!=A_IDLE);assign penable=(ast==A_ACCESS);assign pwrite=|mem_wstrb;
 assign paddr=mem_addr[7:0];assign pwdata=mem_wdata;
 wire apb_done=(ast==A_ACCESS)&&pready;
 logic [1:0] dsel_q=0;
 always_ff @(posedge clk) if(fast_issue) dsel_q<={sel_gpio,sel_mb};
 always_comb begin
  mem_ready=ready_q||apb_done;
  if(apb_done) mem_rdata=prdata;
  else if(dsel_q[1]) mem_rdata=gpio_in;
  else if(dsel_q[0]) mem_rdata=mb_rdata;
  else mem_rdata=ram_rdata;
 end
endmodule
`default_nettype wire
