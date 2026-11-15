// zybo_top -- board top for the Digilent Zybo Z7-10 (xc7z010clg400-1).  Wraps demo_core (all logic) with
//   * Vivado Clocking Wizard IP `clk_wiz_0` : 125 MHz sysclk -> 25.175 MHz pixel clock + 125.875 MHz (5x) serial clock
//   * Digilent rgb2dvi (hdmi/*.vhd, MIT licence): TMDS encoder + serialiser -> HDMI TX pins   (TMDS NOT hand written)
//   * the switch / LED / HDMI pins of constraints/zybo.xdc
// HDMI only: the Zybo Z7 has no VGA connector.
//   sw_view[1:0] (SW0,SW1): 00 original | 01 smoothed | 10 edges | 11 edge overlay on original
//   sw_thr       (SW2)    : threshold preset 0 = THR_HI/LO 192/64, 1 = 300/120, written through an APB master FSM
//   led[0] heartbeat (frame counter) | led[1] core locked | led[2] sync error seen | led[3] preset B applied
//   reset: derived from the clocking-wizard `locked` output (no reset switch is needed; SW3 stays unused)
module zybo_top (
  input  logic        clk,                 // 125 MHz, pin K17
  input  logic [1:0]  sw_view,             // SW0 (G15), SW1 (P15)
  input  logic        sw_thr,              // SW2 (W13)
  output logic [3:0]  led,                 // LD0..LD3
  input  logic        hdmi_tx_hpd,         // hot-plug detect from the monitor (read only, status not used by the demo)
  inout  tri          hdmi_tx_scl,         // DDC, not used (released)
  inout  tri          hdmi_tx_sda,
  output logic        hdmi_tx_clk_n, hdmi_tx_clk_p,
  output logic [2:0]  hdmi_tx_n, hdmi_tx_p
);
  assign hdmi_tx_scl = 1'bz;
  assign hdmi_tx_sda = 1'bz;

  // ---------------- clocks
  logic pclk, sclk, mmcm_locked;
  clk_wiz_0 u_clkwiz (.clk_in1(clk), .reset(1'b0), .clk_out1(pclk), .clk_out2(sclk), .locked(mmcm_locked));

  // reset for the pixel domain: asserted while the MMCM is unlocked, released synchronously
  logic [1:0] rst_sr = 2'b11; logic rst_pix;
  always_ff @(posedge pclk or negedge mmcm_locked)
    if (!mmcm_locked) rst_sr <= 2'b11; else rst_sr <= {rst_sr[0], 1'b0};
  assign rst_pix = rst_sr[1];

  // ---------------- demo
  logic [23:0] vid_data; logic vid_de, vid_hs, vid_vs;
  demo_core #(.MEMFILE("tpg_images.mem")) u_demo (
    .clk(pclk), .rst(rst_pix), .sw_view, .sw_thr, .vid_data, .vid_de, .vid_hs, .vid_vs, .led,
    .dbg_gray(), .dbg_blur(), .dbg_cls(), .dbg_x(), .dbg_y(), .dbg_img());

  // ---------------- HDMI / DVI transmitter (Digilent rgb2dvi): serial clock supplied externally, active-high reset
  rgb2dvi #(.kGenerateSerialClk(1'b0), .kClkPrimitive("MMCM"), .kClkRange(5), .kRstActiveHigh(1'b1)) u_rgb2dvi (
    .TMDS_Clk_p(hdmi_tx_clk_p), .TMDS_Clk_n(hdmi_tx_clk_n), .TMDS_Data_p(hdmi_tx_p), .TMDS_Data_n(hdmi_tx_n),
    .aRst(~mmcm_locked), .aRst_n(1'b1),
    .vid_pData({vid_data[23:16], vid_data[7:0], vid_data[15:8]}),   // rgb2dvi vid_pData = {R, B, G}: see doc/bringup_steps.md note
    .vid_pVDE(vid_de), .vid_pHSync(vid_hs), .vid_pVSync(vid_vs),
    .PixelClk(pclk), .SerialClk(sclk));
endmodule
