`default_nettype none

// Streaming adaptive double threshold (research-paper technique, Guo & Wu, Appl. Sci. 13(2):870, 2023).
//
// The paper buffers a whole NMS frame, builds a 256-bin histogram of the 8-bit-saturated NMS magnitude,
// runs a division-free log-domain Otsu sweep (T_hi), sets T_lo = T_hi/2 and only then classifies the
// same frame.  That needs a frame buffer (80 RAMB36 at 640x480, more than the device has).
// Here the histogram of frame N is built on the fly, in a ping-pong pair of 256-bin BRAM histograms, and
// the paper's own Otsu unit (paper_otsu_logunit, unchanged) runs during vertical blanking; its thresholds
// are applied from frame N+1 on (video frames are temporally coherent).  For a still image every frame from
// the second on is classified with exactly the threshold the whole-frame engine computes.
//
// The classified frame of edge_pipeline has a 3-pixel zero border; the whole-frame engine counts those
// pixels in bin 0, so BORDER zeros are added to bin 0 / the pixel count when the sweep reads the histogram.
//
// Control FSM (minimised STG, see logic/fsm_otsu.py):
//   INIT    clear both histogram banks (256 clocks); counting off            -> ARM
//   ARM     wait for the first pixel of a frame (a histogram must start with a frame) -> COLLECT on sof
//   COLLECT histogram of the current frame                                   -> SWEEP on eof (swap banks)
//   SWEEP   Otsu over the finished bank while the next frame is counted       -> CLEAR when Otsu is done
//   CLEAR   zero the finished bank (256 clocks)                              -> COLLECT (apply now) if no pixel of the
//           new frame has been classified yet, PEND (apply at next eof) otherwise, INIT on overrun or !en
//   PEND    result waits for the next frame boundary                         -> SWEEP on eof (apply + swap)
module otsu_stream #(
  parameter int unsigned IMG_W  = 640,
  parameter int unsigned IMG_H  = 480,
  parameter int unsigned BORDER = IMG_W*IMG_H - (IMG_W-6)*(IMG_H-6),
  parameter int unsigned CW     = $clog2(IMG_W*IMG_H + 1)
) (
  input  wire         clk,
  input  wire         rst,
  input  wire         en,
  input  wire  [10:0] thr_lo_def,
  input  wire  [10:0] thr_hi_def,
  input  wire         nms_valid,
  input  wire  [10:0] nms_mag,
  input  wire         nms_sof,         // first NMS pixel of a frame
  input  wire         nms_eof,         // last NMS pixel of a frame
  output logic [10:0] thr_lo,
  output logic [10:0] thr_hi,
  output logic        adapt_valid,
  output logic        overrun,
  output logic [2:0]  state_o
);
  typedef enum logic [2:0] {S_INIT = 3'd0, S_ARM = 3'd1, S_COLLECT = 3'd2, S_SWEEP = 3'd3, S_CLEAR = 3'd4, S_PEND = 3'd5} state_t;
  (* fsm_encoding = "auto" *) state_t state;
  assign state_o = state;

  // ---------------- histogram banks (simple dual port BRAM each) ----------------
  (* ram_style = "block" *) logic [CW-1:0] hist0 [0:255];
  (* ram_style = "block" *) logic [CW-1:0] hist1 [0:255];
  logic [CW-1:0] rd0, rd1;
  logic [7:0] ra0, ra1, wa0, wa1;
  logic we0, we1;
  logic [CW-1:0] wd0, wd1;
  always_ff @(posedge clk) begin
    if (we0) hist0[wa0] <= wd0;
    rd0 <= hist0[ra0];
  end
  always_ff @(posedge clk) begin
    if (we1) hist1[wa1] <= wd1;
    rd1 <= hist1[ra1];
  end

  logic acc_bank;                       // bank being accumulated; the other one is swept / cleared
  logic [7:0] sat;
  assign sat = (nms_mag > 11'd255) ? 8'hFF : nms_mag[7:0];
  wire count_en = (state == S_COLLECT) || (state == S_SWEEP) || (state == S_CLEAR) || (state == S_PEND) ||
                  ((state == S_ARM) && en && nms_sof);

  // accumulate pipeline: stage 1 = BRAM read, stage 2 = +1 and write back, with one forwarding register
  logic v1, bank1; logic [7:0] b1, s1;
  logic wv_valid, wbank; logic [7:0] wb; logic [CW-1:0] wv;
  logic [CW-1:0] inc;
  always_comb inc = ((wv_valid && (wbank == bank1) && (wb == b1)) ? wv : (bank1 ? rd1 : rd0)) + 1'b1;

  // per-bank pixel count and grey-level sum (inputs of the Otsu unit)
  logic [CW-1:0] cnt0, cnt1;
  logic [31:0] sum0, sum1;

  // sweep (Otsu) and clear
  logic otsu_start, otsu_busy, otsu_done;
  logic [7:0] o_raddr, o_raddr_q;
  logic [31:0] o_rdata, tot_cnt, tot_sum;
  logic [7:0] t_hi_o, t_lo_o;
  logic [8:0] clr_k;
  wire clr_done = clr_k[8];
  logic px_seen;                        // a pixel of the frame after the swept one has been classified

  always_comb begin
    // bank 0 ports
    ra0 = acc_bank ? o_raddr : sat;
    ra1 = acc_bank ? sat : o_raddr;
    we0 = 1'b0; wa0 = '0; wd0 = '0;
    we1 = 1'b0; wa1 = '0; wd1 = '0;
    if (state == S_INIT) begin                         // clear both banks
      we0 = 1'b1; wa0 = clr_k[7:0];
      we1 = 1'b1; wa1 = clr_k[7:0];
    end else begin
      if (v1) begin                                    // accumulate write (bank of the pixel)
        if (bank1) begin we1 = 1'b1; wa1 = b1; wd1 = inc; end
        else       begin we0 = 1'b1; wa0 = b1; wd0 = inc; end
      end
      if (state == S_CLEAR) begin                      // clear the swept bank (never the accumulate bank)
        if (acc_bank) begin we0 = 1'b1; wa0 = clr_k[7:0]; wd0 = '0; end
        else          begin we1 = 1'b1; wa1 = clr_k[7:0]; wd1 = '0; end
      end
    end
    o_rdata = (acc_bank ? 32'(rd0) : 32'(rd1)) + ((o_raddr_q == 8'd0) ? 32'(BORDER) : 32'd0);
    tot_cnt = (acc_bank ? 32'(cnt0) : 32'(cnt1)) + 32'(BORDER);
    tot_sum = acc_bank ? sum0 : sum1;
  end

  paper_otsu_logunit u_otsu (
    .clk, .rst, .start(otsu_start), .busy(otsu_busy), .done(otsu_done),
    .hist_raddr(o_raddr), .hist_rdata(o_rdata), .tot_cnt, .tot_sum, .min_val(8'd0),
    .t_hi(t_hi_o), .t_lo(t_lo_o),
    .dbg_k(), .dbg_w0(), .dbg_s0(), .dbg_score(), .dbg_best_k()
  );

  logic [10:0] thr_lo_a, thr_hi_a;
  assign thr_hi = (en && adapt_valid) ? thr_hi_a : thr_hi_def;
  assign thr_lo = (en && adapt_valid) ? thr_lo_a : thr_lo_def;

  always_ff @(posedge clk) begin
    o_raddr_q <= o_raddr;
    if (rst) begin
      state <= S_INIT; clr_k <= '0; acc_bank <= 1'b0;
      v1 <= 1'b0; wv_valid <= 1'b0; otsu_start <= 1'b0;
      cnt0 <= '0; cnt1 <= '0; sum0 <= '0; sum1 <= '0;
      px_seen <= 1'b0; overrun <= 1'b0; adapt_valid <= 1'b0;
      thr_lo_a <= '0; thr_hi_a <= '0;
      b1 <= '0; bank1 <= 1'b0; wb <= '0; wv <= '0; wbank <= 1'b0; s1 <= '0;
    end else begin
      otsu_start <= 1'b0;
      // stage 1
      v1 <= nms_valid && count_en; b1 <= sat; s1 <= sat; bank1 <= acc_bank;
      // stage 2: write-back is combinational above; remember it for forwarding and update the bank totals
      wv_valid <= v1; wb <= b1; wv <= inc; wbank <= bank1;
      if (v1) begin
        if (bank1) begin cnt1 <= cnt1 + 1'b1; sum1 <= sum1 + 32'(s1); end
        else       begin cnt0 <= cnt0 + 1'b1; sum0 <= sum0 + 32'(s1); end
      end
      if (nms_valid && (state == S_SWEEP || state == S_CLEAR)) px_seen <= 1'b1;
      if ((state == S_SWEEP || state == S_CLEAR) && nms_eof) overrun <= 1'b1;

      unique case (state)
        S_INIT: begin
          clr_k <= clr_k + 1'b1;
          if (clr_done) begin
            clr_k <= '0; cnt0 <= '0; cnt1 <= '0; sum0 <= '0; sum1 <= '0; overrun <= 1'b0; adapt_valid <= 1'b0;
            state <= S_ARM;
          end
        end
        S_ARM: if (en && nms_sof) state <= S_COLLECT;
        S_COLLECT: begin
          if (!en) state <= S_INIT;
          else if (nms_eof) begin
            acc_bank <= ~acc_bank; otsu_start <= 1'b1; px_seen <= 1'b0; state <= S_SWEEP;
          end
        end
        S_SWEEP: if (otsu_done) begin clr_k <= '0; state <= S_CLEAR; end
        S_CLEAR: begin
          clr_k <= clr_k + 1'b1;
          if (clr_done) begin
            clr_k <= '0;
            if (acc_bank) begin cnt0 <= '0; sum0 <= '0; end else begin cnt1 <= '0; sum1 <= '0; end
            if (overrun || !en) state <= S_INIT;
            else if (!px_seen && !nms_valid) begin         // still in blanking: apply to the coming frame
              thr_hi_a <= 11'(t_hi_o); thr_lo_a <= 11'(t_lo_o); adapt_valid <= 1'b1; state <= S_COLLECT;
            end else state <= S_PEND;
          end
        end
        S_PEND: begin
          if (!en) state <= S_INIT;
          else if (nms_eof) begin                          // frame boundary: apply, then sweep the frame just ended
            thr_hi_a <= 11'(t_hi_o); thr_lo_a <= 11'(t_lo_o); adapt_valid <= 1'b1;
            acc_bank <= ~acc_bank; otsu_start <= 1'b1; px_seen <= 1'b0; state <= S_SWEEP;
          end
        end
        default: state <= S_INIT;
      endcase
    end
  end

  initial begin
    if (IMG_W*IMG_H >= (1 << CW)) $fatal(1, "otsu_stream: counter width too small");
  end
endmodule

`default_nettype wire
