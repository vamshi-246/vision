`default_nettype none
// 320x240x8 on-chip frame buffer plus a small read-only status block.
//
// Port A is the AXI BRAM-controller side (32-bit words, byte strobes); it is
// driven from the JTAG-to-AXI master.  Port B is the video read side
// (8-bit, 17-bit address, 1-cycle read latency).  Both ports use the same
// clock, so there is no clock-domain crossing.
//
// Byte map seen over AXI (little-endian, pixel (x,y) at byte y*320+x):
//   0x00000..0x12BFF  image bytes (RW)
//   0x14000..0x15FFF  CPU RAM (8 KB; load firmware while cpu_run=0)
//   0x16000..0x163FF  mailbox (CPU results / host commands)
//   0x18000 magic 0x5A420001 | 0x18004 edge_count | 0x18008 flags | 0x1800C frame_count (RO)
//   0x18010 control (RW) bit0 = cpu_run | 0x18014 cpu status (RO) bit0 = trap | 0x18018 thresholds in use {hi[10:0],lo[10:0]} (RO)
module frame_store #(parameter integer IMG_PIXELS=76800)(
 input wire clk,
 // AXI BRAM controller port A (byte address)
 input wire a_en,input wire [3:0] a_we,input wire [16:0] a_addr,input wire [31:0] a_wdata,
 output wire [31:0] a_rdata,
 output wire a_img_write,
 // video read port
 input wire [16:0] b_addr,output wire [7:0] b_data,
 // status inputs (same clock domain)
 input wire [19:0] edge_count,input wire [31:0] flags,input wire [31:0] frame_count,
 input wire cpu_trap,input wire [21:0] thr_used,
 // CPU RAM / mailbox host ports and run control
 output wire h_ram_en,output wire [3:0] h_ram_we,output wire [10:0] h_ram_addr,output wire [31:0] h_ram_wdata,input wire [31:0] h_ram_rdata,
 output wire h_mb_en,output wire [3:0] h_mb_we,output wire [7:0] h_mb_addr,output wire [31:0] h_mb_wdata,input wire [31:0] h_mb_rdata,
 output logic cpu_run,
 // live-video word writes (pixel-clock domain, from rx_downscale's FIFO); taken only in cycles without an AXI access
 input wire live_en,input wire live_valid,input wire [14:0] live_addr,input wire [31:0] live_data,output wire live_pop);
 localparam integer WORDS=IMG_PIXELS/4;
 wire in_image=(a_addr[16:2]<WORDS);
 wire in_ram=(a_addr[16:13]==4'b1010),in_mb=(a_addr[16:13]==4'b1011),in_reg=(a_addr[16:15]==2'b11);
 assign h_ram_en=a_en&&in_ram;assign h_ram_we=in_ram?a_we:4'b0;assign h_ram_addr=a_addr[12:2];assign h_ram_wdata=a_wdata;
 assign h_mb_en=a_en&&in_mb;assign h_mb_we=in_mb?a_we:4'b0;assign h_mb_addr=a_addr[9:2];assign h_mb_wdata=a_wdata;
 initial cpu_run=1'b0;
 always_ff @(posedge clk) if(a_en && in_reg && a_addr[5:2]==4'd4 && |a_we) cpu_run<=a_wdata[0];
 wire [3:0] we_img=(a_en && in_image) ? a_we : 4'b0;
 assign a_img_write=|we_img;
 assign live_pop=live_en && live_valid && !a_en;
 wire pa_en=a_en||live_pop;
 wire [3:0] pa_we=a_en?we_img:{4{live_pop}};
 wire [14:0] pa_addr=a_en?a_addr[16:2]:live_addr;
 wire [31:0] pa_din=a_en?a_wdata:live_data;
 wire [31:0] ram_a;
 xpm_memory_tdpram #(
  .MEMORY_SIZE(IMG_PIXELS*8),.MEMORY_PRIMITIVE("block"),.CLOCKING_MODE("common_clock"),
  .MEMORY_INIT_FILE("none"),.MEMORY_INIT_PARAM("0"),.USE_MEM_INIT(1),
  .WAKEUP_TIME("disable_sleep"),.ECC_MODE("no_ecc"),.AUTO_SLEEP_TIME(0),.MESSAGE_CONTROL(0),
  .WRITE_DATA_WIDTH_A(32),.READ_DATA_WIDTH_A(32),.BYTE_WRITE_WIDTH_A(8),.ADDR_WIDTH_A(15),
  .READ_RESET_VALUE_A("0"),.READ_LATENCY_A(1),.WRITE_MODE_A("read_first"),
  .WRITE_DATA_WIDTH_B(8),.READ_DATA_WIDTH_B(8),.BYTE_WRITE_WIDTH_B(8),.ADDR_WIDTH_B(17),
  .READ_RESET_VALUE_B("0"),.READ_LATENCY_B(1),.WRITE_MODE_B("read_first"))
 ram(
  .clka(clk),.ena(pa_en),.wea(pa_we),.addra(pa_addr),.dina(pa_din),.douta(ram_a),
  .clkb(clk),.enb(1'b1),.web(1'b0),.addrb(b_addr),.dinb(8'd0),.doutb(b_data),
  .rsta(1'b0),.rstb(1'b0),.regcea(1'b1),.regceb(1'b1),.sleep(1'b0),
  .injectsbiterra(1'b0),.injectdbiterra(1'b0),.injectsbiterrb(1'b0),.injectdbiterrb(1'b0),
  .sbiterra(),.dbiterra(),.sbiterrb(),.dbiterrb());
 logic [1:0] rsel=0;logic [31:0] reg_q=0;
 always_ff @(posedge clk) if(a_en) begin
  rsel<=in_reg?2'd1:(in_ram?2'd2:(in_mb?2'd3:2'd0));
  case(a_addr[5:2])
   4'd0: reg_q<=32'h5A420001;
   4'd1: reg_q<={12'b0,edge_count};
   4'd2: reg_q<=flags;
   4'd3: reg_q<=frame_count;
   4'd4: reg_q<={31'b0,cpu_run};
   4'd5: reg_q<={31'b0,cpu_trap};
   4'd6: reg_q<={10'b0,thr_used};
   default: reg_q<=32'd0;
  endcase
 end
 assign a_rdata=(rsel==2'd1)?reg_q:((rsel==2'd2)?h_ram_rdata:((rsel==2'd3)?h_mb_rdata:ram_a));
endmodule
`default_nettype wire
