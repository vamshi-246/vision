`default_nettype none
// Edge-detection video pipeline + RV32 control subsystem.  Everything runs on the pixel clock (no clock crossings).
//   edge_video (pipeline, 3 views, switch threshold presets)  <->  apb_regs  <->  cpu_subsys (PicoRV32, firmware in RAM)
// With cpu_run=0 the CPU is held in reset and the hardware switch presets drive the thresholds (fallback).  With cpu_run=1 the
// firmware sets ctrl.threshold_cpu and the thresholds then come from the APB register bank.
module video_soc #(parameter integer W=640,H=480)(
 input wire clk,rst,input wire [3:0] switches,
 output logic [23:0] rgb,output wire de,hsync,vsync,
 output logic alignment_error,output logic [19:0] edge_count,output logic frame_pulse,
 // stored-image source
 input wire use_image,output logic [16:0] img_addr,input wire [7:0] img_data,
 // CPU control + host (JTAG-AXI) access
 input wire cpu_run,
 input wire h_ram_en,input wire [3:0] h_ram_we,input wire [10:0] h_ram_addr,input wire [31:0] h_ram_wdata,output wire [31:0] h_ram_rdata,
 input wire h_mb_en,input wire [3:0] h_mb_we,input wire [7:0] h_mb_addr,input wire [31:0] h_mb_wdata,output wire [31:0] h_mb_rdata,
 output wire [3:0] settings,output wire [21:0] thr_used,output wire cpu_trap,output logic [31:0] frames);
 wire psel,penable,pwrite,pready,pslverr;wire [7:0] paddr;wire [31:0] pwdata,prdata;
 wire threshold_cpu,clear_hist_pulse;wire [10:0] apb_thr_hi,apb_thr_lo;wire [5:0] hist_idx;
 wire [18:0] hist_rd_data,hist_nnz;wire hist_valid;
 wire [31:0] unused_crc_gold,unused_auto_cfg;wire en_unused,auto_unused,hyst_unused;wire [1:0] view_unused;
 always_ff @(posedge clk) if(rst) frames<=0; else if(frame_pulse) frames<=frames+1'b1;
 edge_video #(.W(W),.H(H)) video(.clk,.rst,.switches,.rgb,.de,.hsync,.vsync,.x(),.y(),.alignment_error,.edge_count,.frame_pulse,
  .use_image,.img_addr,.img_data,.settings_o(settings),
  .ext_thr_en(cpu_run && threshold_cpu),.ext_thr_lo(apb_thr_lo),.ext_thr_hi(apb_thr_hi),
  .clear_hist(clear_hist_pulse),.hist_rd_addr(hist_idx),.hist_rd_data,.hist_nnz,.hist_valid,.thr_used);
 apb_regs regs(.pclk(clk),.rst,.psel,.penable,.pwrite,.paddr,.pwdata,.prdata,.pready,.pslverr,
  .enable(en_unused),.auto_threshold(auto_unused),.view_mode(view_unused),.hyst_enable(hyst_unused),.threshold_cpu,
  .clear_hist_sticky(clear_hist_pulse),.thr_hi(apb_thr_hi),.thr_lo(apb_thr_lo),.crc_gold(unused_crc_gold),.auto_cfg(unused_auto_cfg),
  .hist_idx,.frame_done_i(frame_pulse),.fifo_underflow_i(1'b0),.fifo_overflow_i(1'b0),.sync_error_i(alignment_error),
  .hist_valid_i(hist_valid),.edge_cnt_i(edge_count),.frame_cnt_i(frames),.crc_out_i(32'd0),
  .thr_hi_auto_i(11'd0),.thr_lo_auto_i(11'd0),.hist_data_i(hist_rd_data));
 (* ASYNC_REG="TRUE" *) logic [3:0] sw_m=0,sw_s=0;
 always_ff @(posedge clk) begin sw_m<=switches;sw_s<=sw_m;end
 wire [31:0] gpio_in={28'd0,sw_s};
 cpu_subsys cpu(.clk,.run(cpu_run),.psel,.penable,.pwrite,.paddr,.pwdata,.prdata,.pready,.gpio_in,
  .h_ram_en,.h_ram_we,.h_ram_addr,.h_ram_wdata,.h_ram_rdata,.h_mb_en,.h_mb_we,.h_mb_addr,.h_mb_wdata,.h_mb_rdata,.trap(cpu_trap));
endmodule
`default_nettype wire
