// paper_top.sv -- adaptive-threshold engine of Guo & Wu (Appl. Sci. 13(2):870, 2023), sim-only today.
// FSM: IDLE -> LOAD -> HIST -> OTSU -> CLASSIFY -> DONE.
//   LOAD     : accepts W*H magnitude samples (pix_valid/pix_data, IN_W bits), saturates each to 8 bits
//              and writes them to paper_frame_buffer.  pix_ready is high in this state.
//   HIST     : 256-bin histogram of the whole frame.
//   OTSU     : log-domain, division-free Otsu sweep -> t_hi; t_lo = t_hi >> 1.
//   CLASSIFY : re-reads the frame, emits a 2-bit class per pixel and counts strong edges.
// `done` is a level that stays high in DONE until the next `start`.
module paper_top #(
  parameter int W    = 64,
  parameter int H    = 64,
  parameter int IN_W = 11,                        // width of the incoming NMS magnitude
  parameter int AW   = (W*H > 1) ? $clog2(W*H) : 1
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            start,
  output logic            busy,
  output logic            done,
  output logic            pix_ready,
  input  logic            pix_valid,
  input  logic [IN_W-1:0] pix_data,
  output logic [7:0]      t_hi,
  output logic [7:0]      t_lo,
  output logic            class_valid,
  output logic [1:0]      class_out,
  output logic [31:0]     edge_count
);
  typedef enum logic [2:0] {S_IDLE, S_LOAD, S_HIST, S_OTSU, S_CLASS, S_DONE} state_t;
  state_t state;

  localparam logic [AW-1:0] LAST = AW'(W*H - 1);

  // ---- 8-bit saturating quantizer ----
  logic [7:0] pix_sat;
  always_comb begin
    if (pix_data > IN_W'(255)) pix_sat = 8'hFF;
    else                       pix_sat = pix_data[7:0];
  end

  logic [AW-1:0] load_addr;
  logic          sub_start;               // 1-cycle pulse on state entry

  // ---- frame buffer ----
  logic          fb_we;
  logic [AW-1:0] fb_raddr, hist_fb_raddr, cls_fb_raddr;
  logic [7:0]    fb_rdata;

  assign fb_we     = (state == S_LOAD) && pix_valid;
  assign fb_raddr  = (state == S_CLASS) ? cls_fb_raddr : hist_fb_raddr;
  assign pix_ready = (state == S_LOAD);
  assign busy      = (state != S_IDLE) && (state != S_DONE);
  assign done      = (state == S_DONE);

  paper_frame_buffer #(.W(W), .H(H)) u_fb (
    .clk(clk), .we(fb_we), .waddr(load_addr), .wdata(pix_sat),
    .raddr(fb_raddr), .rdata(fb_rdata)
  );

  // ---- histogram ----
  logic        hist_busy, hist_done;
  logic [7:0]  hist_raddr;
  logic [31:0] hist_rdata, tot_cnt, tot_sum;
  logic [7:0]  min_val, max_val;

  paper_histogram #(.W(W), .H(H)) u_hist (
    .clk(clk), .rst(rst), .start(sub_start && (state == S_HIST)),
    .busy(hist_busy), .done(hist_done),
    .fb_raddr(hist_fb_raddr), .fb_rdata(fb_rdata),
    .hist_raddr(hist_raddr), .hist_rdata(hist_rdata),
    .tot_cnt(tot_cnt), .tot_sum(tot_sum), .min_val(min_val), .max_val(max_val)
  );

  // ---- Otsu log unit ----
  logic        otsu_busy, otsu_done;
  logic [7:0]  dbg_k, dbg_best_k;
  logic [31:0] dbg_w0, dbg_s0;
  logic signed [19:0] dbg_score;

  paper_otsu_logunit u_otsu (
    .clk(clk), .rst(rst), .start(sub_start && (state == S_OTSU)),
    .busy(otsu_busy), .done(otsu_done),
    .hist_raddr(hist_raddr), .hist_rdata(hist_rdata),
    .tot_cnt(tot_cnt), .tot_sum(tot_sum), .min_val(min_val),
    .t_hi(t_hi), .t_lo(t_lo),
    .dbg_k(dbg_k), .dbg_w0(dbg_w0), .dbg_s0(dbg_s0), .dbg_score(dbg_score), .dbg_best_k(dbg_best_k)
  );

  // ---- classify ----
  logic        cls_busy, cls_done;
  logic [31:0] weak_count;

  paper_classify #(.W(W), .H(H)) u_cls (
    .clk(clk), .rst(rst), .start(sub_start && (state == S_CLASS)),
    .busy(cls_busy), .done(cls_done),
    .t_hi(t_hi), .t_lo(t_lo),
    .fb_raddr(cls_fb_raddr), .fb_rdata(fb_rdata),
    .class_valid(class_valid), .class_out(class_out),
    .edge_count(edge_count), .weak_count(weak_count)
  );

  // ---- control FSM ----
  always_ff @(posedge clk) begin
    if (rst) begin
      state     <= S_IDLE;
      load_addr <= '0;
      sub_start <= 1'b0;
    end else begin
      sub_start <= 1'b0;
      case (state)
        S_IDLE, S_DONE: begin
          if (start) begin
            load_addr <= '0;
            state     <= S_LOAD;
          end
        end
        S_LOAD: begin
          if (pix_valid) begin
            if (load_addr == LAST) begin
              load_addr <= '0;
              state     <= S_HIST;
              sub_start <= 1'b1;
            end else begin
              load_addr <= load_addr + 1'b1;
            end
          end
        end
        S_HIST: if (hist_done) begin
          state     <= S_OTSU;
          sub_start <= 1'b1;
        end
        S_OTSU: if (otsu_done) begin
          state     <= S_CLASS;
          sub_start <= 1'b1;
        end
        S_CLASS: if (cls_done) state <= S_DONE;
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
