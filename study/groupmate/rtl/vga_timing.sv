// vga_timing -- 640x480@60 raster generator (800x525 total).  Numbers + sources: doc/vga_timing.md
//   horizontal: 640 active | 16 front porch | 96 sync | 48 back porch   = 800
//   vertical  : 480 active | 10 front porch |  2 sync | 33 back porch   = 525      (both syncs active LOW)
// hc/vc are the RASTER coordinates used by the edge-detection core: (0,0) is the first active pixel, so they are
// directly the tags of core_top / ctrl_sync.  INIT_H/INIT_V give the counter value after reset: the demo runs one
// instance for the pixel SOURCE started K+latency cycles "ahead" of the display instance, see doc/latency.md.
module vga_timing #(
  parameter int HA = 640, HFP = 16, HS = 96, HBP = 48,
  parameter int VA = 480, VFP = 10, VS = 2,  VBP = 33,
  parameter int INIT_H = 0, INIT_V = 0
) (
  input  logic        clk,
  input  logic        rst,          // synchronous, active high
  output logic [9:0]  hc, vc,
  output logic        de, hsync, vsync,
  output logic        frame_origin  // (hc,vc)==(0,0)
);
  localparam int WT = HA + HFP + HS + HBP;   // 800
  localparam int HT = VA + VFP + VS + VBP;   // 525
  always_ff @(posedge clk) begin
    if (rst) begin hc <= 10'(INIT_H); vc <= 10'(INIT_V); end
    else if (hc == WT - 1) begin hc <= 0; vc <= (vc == HT - 1) ? 10'd0 : vc + 10'd1; end
    else hc <= hc + 10'd1;
  end
  assign de           = (hc < HA) && (vc < VA);
  assign hsync        = ~((hc >= HA + HFP) && (hc < HA + HFP + HS));
  assign vsync        = ~((vc >= VA + VFP) && (vc < VA + VFP + VS));
  assign frame_origin = (hc == 0) && (vc == 0);
endmodule
