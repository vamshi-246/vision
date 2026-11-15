// paper_otsu_logunit.sv -- division-free Otsu threshold search (see doc/change_notes/DEV-1).
//
//   paper_log2          : combinational log unit.  Integer part from a leading-zero count (CLZ),
//                         fractional part from a 16-segment piecewise-linear table (index = 4 bits
//                         below the leading one, interpolated with the next 4 bits).  Q6.8 output.
//   paper_otsu_logunit  : pass-2 sweep over k = 0..255 with running prefix weight w0 and prefix sum
//                         s0, log-domain between-class score, and a running-max comparator.
//
// Score(k) = 2*L(|s0*N - S*w0|) - L(w0) - L(w1)  ==  log of w0*w1*(mu0-mu1)^2 up to a constant,
// because mu0-mu1 = (s0*N - S*w0)/(w0*w1).  The class means are therefore never divided; they are
// compared in the log domain by subtraction.  Strict '>' keeps the first maximum.
// If no k has both classes non-empty (single grey level) T_hi falls back to the frame minimum.

module paper_log2 #(
  parameter int WIDTH = 48
) (
  input  logic [WIDTH-1:0] x,
  output logic [13:0]      log2_q8,   // {integer[5:0], fraction[7:0]}; 0 when x == 0
  output logic             nz         // x != 0
);
  localparam int CW = $clog2(WIDTH + 1);

  logic [CW-1:0]    clz;
  logic             found;
  logic [WIDTH-1:0] norm;
  logic [3:0]       idx, rem;
  logic [8:0]       base, nxt;
  logic [8:0]       delta;
  logic [12:0]      prod;
  logic [7:0]       frac;
  logic [5:0]       ipart;

  function automatic logic [8:0] lut_f(input logic [4:0] i);
    case (i)
      5'd0:    lut_f = 9'd0;
      5'd1:    lut_f = 9'd22;
      5'd2:    lut_f = 9'd44;
      5'd3:    lut_f = 9'd63;
      5'd4:    lut_f = 9'd82;
      5'd5:    lut_f = 9'd100;
      5'd6:    lut_f = 9'd118;
      5'd7:    lut_f = 9'd134;
      5'd8:    lut_f = 9'd150;
      5'd9:    lut_f = 9'd165;
      5'd10:   lut_f = 9'd179;
      5'd11:   lut_f = 9'd193;
      5'd12:   lut_f = 9'd207;
      5'd13:   lut_f = 9'd220;
      5'd14:   lut_f = 9'd232;
      5'd15:   lut_f = 9'd244;
      default: lut_f = 9'd256;   // entry 16, only used to form the last delta
    endcase
  endfunction

  // leading-zero count (first set bit scanning from the MSB)
  always_comb begin
    clz   = '0;
    found = 1'b0;
    for (int i = WIDTH - 1; i >= 0; i--) begin
      if (!found) begin
        if (x[i]) found = 1'b1;
        else      clz   = clz + 1'b1;
      end
    end
  end

  assign nz    = found;
  assign norm  = x << clz;                          // leading one at bit WIDTH-1
  assign idx   = norm[WIDTH-2 -: 4];
  assign rem   = norm[WIDTH-6 -: 4];
  assign base  = lut_f({1'b0, idx});
  assign nxt   = lut_f({1'b0, idx} + 5'd1);
  assign delta = nxt - base;
  assign prod  = delta * rem;                       // 9b x 4b -> 13b
  assign frac  = base[7:0] + prod[11:4];            // base<256 for idx<=15; sum < 256
  assign ipart = 6'(WIDTH - 1) - 6'(clz);
  assign log2_q8 = found ? {ipart, frac} : 14'd0;
endmodule


module paper_otsu_logunit #(
  parameter int WIDTH = 48
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        start,          // 1-cycle pulse
  output logic        busy,
  output logic        done,           // 1-cycle pulse
  // histogram read port (1-cycle latency)
  output logic [7:0]  hist_raddr,
  input  logic [31:0] hist_rdata,
  // frame statistics from paper_histogram
  input  logic [31:0] tot_cnt,
  input  logic [31:0] tot_sum,
  input  logic [7:0]  min_val,
  // result
  output logic [7:0]  t_hi,
  output logic [7:0]  t_lo,
  // visibility for waveform / debug
  output logic [7:0]  dbg_k,
  output logic [31:0] dbg_w0,
  output logic [31:0] dbg_s0,
  output logic signed [19:0] dbg_score,
  output logic [7:0]  dbg_best_k
);
  // ---------------- stage 0: issue bin reads ----------------
  logic [8:0] k_cnt;
  logic       issuing;
  assign hist_raddr = k_cnt[7:0];

  // ---------------- stage 1: running prefix sums ----------------
  logic        pv1;
  logic [7:0]  k1;
  logic [31:0] w0, s0;

  // ---------------- stage 2: class weights and |s0*N - S*w0| ----------------
  logic              pv2;
  logic [7:0]        k2;
  logic [31:0]       w0_2, w1_2;
  logic [WIDTH-1:0]  d_2;
  logic              cand2;

  // D = s0*N - S*w0 (signed, 64-bit), then |D| truncated to WIDTH bits for the log unit
  logic signed [63:0] d_full2;
  logic signed [63:0] d_abs;
  assign d_full2 = $signed({32'd0, s0}) * $signed({32'd0, tot_cnt})
                 - $signed({32'd0, tot_sum}) * $signed({32'd0, w0});
  assign d_abs = d_full2[63] ? -d_full2 : d_full2;

  // ---------------- stage 3: log unit and score ----------------
  logic        pv3;
  logic [7:0]  k3;
  logic        cand3;
  logic [13:0] ld, l0, l1;
  logic signed [19:0] score_c;

  paper_log2 #(.WIDTH(WIDTH)) u_ld (.x(d_2),                       .log2_q8(ld), .nz());
  paper_log2 #(.WIDTH(WIDTH)) u_l0 (.x(WIDTH'(w0_2)),              .log2_q8(l0), .nz());
  paper_log2 #(.WIDTH(WIDTH)) u_l1 (.x(WIDTH'(w1_2)),              .log2_q8(l1), .nz());

  assign score_c = $signed({6'd0, ld, 1'b0}) - $signed({6'd0, l0}) - $signed({6'd0, l1});

  // ---------------- stage 4: running max ----------------
  logic               pv4;
  logic [7:0]         k4;
  logic               cand4;
  logic signed [19:0] score4;
  logic               best_valid;
  logic signed [19:0] best_score;
  logic [7:0]         best_k;

  assign dbg_k      = k1;
  assign dbg_w0     = w0;
  assign dbg_s0     = s0;
  assign dbg_score  = score4;
  assign dbg_best_k = best_k;
  assign t_lo       = t_hi >> 1;

  always_ff @(posedge clk) begin
    if (rst) begin
      k_cnt <= '0;  issuing <= 1'b0;  busy <= 1'b0;  done <= 1'b0;
      pv1 <= 1'b0;  pv2 <= 1'b0;  pv3 <= 1'b0;  pv4 <= 1'b0;
      k1 <= '0; k2 <= '0; k3 <= '0; k4 <= '0;
      w0 <= '0; s0 <= '0;
      w0_2 <= '0; w1_2 <= '0; d_2 <= '0; cand2 <= 1'b0; cand3 <= 1'b0; cand4 <= 1'b0;
      score4 <= '0;
      best_valid <= 1'b0; best_score <= '0; best_k <= '0;
      t_hi <= '0;
    end else begin
      done <= 1'b0;

      if (start && !busy) begin
        k_cnt <= '0;  issuing <= 1'b1;  busy <= 1'b1;
        pv1 <= 1'b0;  pv2 <= 1'b0;  pv3 <= 1'b0;  pv4 <= 1'b0;
        w0 <= '0;     s0 <= '0;
        best_valid <= 1'b0;  best_score <= '0;  best_k <= '0;
      end else begin
        // stage 0 -> 1
        pv1 <= issuing;
        k1  <= k_cnt[7:0];
        if (issuing) begin
          if (k_cnt == 9'd255) issuing <= 1'b0;
          else                 k_cnt   <= k_cnt + 9'd1;
        end

        // stage 1: prefix sums (hist_rdata holds bin k1 when pv1)
        if (pv1) begin
          w0 <= w0 + hist_rdata;
          s0 <= s0 + ({24'd0, k1} * hist_rdata);
        end
        pv2 <= pv1;
        k2  <= k1;

        // stage 2: register class weights and |D| (w0/s0 now cover hist_bins 0..k2)
        pv3   <= pv2;
        k3    <= k2;
        w0_2  <= w0;
        w1_2  <= tot_cnt - w0;
        d_2   <= d_abs[WIDTH-1:0];
        cand3 <= (w0 != 32'd0) && (w0 != tot_cnt);

        // stage 3: score register
        pv4    <= pv3;
        k4     <= k3;
        cand4  <= cand3;
        score4 <= score_c;

        // stage 4: running-max comparator
        if (pv4 && cand4 && (!best_valid || (score4 > best_score))) begin
          best_valid <= 1'b1;
          best_score <= score4;
          best_k     <= k4;
        end

        // finish when the pipeline has drained
        if (busy && !issuing && !pv1 && !pv2 && !pv3 && !pv4) begin
          busy <= 1'b0;
          done <= 1'b1;
          t_hi <= best_valid ? best_k : min_val;
        end
      end
    end
  end
endmodule
