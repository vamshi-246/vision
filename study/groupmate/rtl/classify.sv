// classify -- double threshold.  cls = 2 (strong) if nms >= thr_hi, 1 (weak) if nms >= thr_lo, else 0.
// A pixel with nms == 0 is always class 0 (so thr_lo == 0 cannot flag background).  One register stage.
// thr_hi / thr_lo come from apb_regs, already latched at the frame boundary (never change mid-frame).
module classify #(parameter int XW = 10) (
  input  logic          clk,
  input  logic [10:0]   nms,
  input  logic [10:0]   thr_hi, thr_lo,
  input  logic [XW-1:0] xi, yi,
  output logic [1:0]    cls,
  output logic [10:0]   nms_o,
  output logic [XW-1:0] xo, yo
);
  // synthesis translate_off
  initial begin
    cls = '0; nms_o = '0; xo = '0; yo = '0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    cls   <= (nms != 11'd0 && nms >= thr_hi) ? 2'd2 : (nms != 11'd0 && nms >= thr_lo) ? 2'd1 : 2'd0;
    nms_o <= nms;
    xo <= xi; yo <= yi;
  end
endmodule
