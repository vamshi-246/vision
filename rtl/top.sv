`default_nettype none

// Baseline streaming core.  This is intentionally board-neutral: a board top
// later provides the ROM/FIFO source, display phasing and APB bridge.  Valid
// regions shrink by one pixel at each 3x3 stage, yielding the Appendix-A
// three-pixel margin for GAUSS_N=3.
module edge_pipeline #(
  parameter int unsigned IMG_W = 640,
  parameter int unsigned IMG_H = 480,
  parameter int unsigned X_W = $clog2(IMG_W),
  parameter int unsigned Y_W = $clog2(IMG_H)
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            in_valid,
  input  logic            in_sof,
  input  logic            in_eol,
  input  logic [7:0]      in_gray,
  input  logic [10:0]     thr_lo,
  input  logic [10:0]     thr_hi,
  input  logic            clear_hist,
  input  logic [5:0]      hist_rd_addr,
  output logic [18:0]     hist_rd_data,
  output logic [18:0]     hist_nnz,
  output logic            hist_valid,
  output logic            out_valid,
  output logic            out_sof,
  output logic            out_eol,
  output logic [X_W-1:0]  out_x,
  output logic [Y_W-1:0]  out_y,
  output logic [1:0]      out_cls
);
  localparam int unsigned G_W = IMG_W - 2;
  localparam int unsigned G_H = IMG_H - 2;
  localparam int unsigned S_W = IMG_W - 4;
  localparam int unsigned S_H = IMG_H - 4;

  logic g_win_valid;
  logic [X_W-1:0] g_win_x;
  logic [Y_W-1:0] g_win_y;
  logic [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
  logic gauss_valid;
  logic [7:0] smooth;
  logic gauss_sof, gauss_eol;

  logic s_win_valid;
  logic [X_W-1:0] s_win_x;
  logic [Y_W-1:0] s_win_y;
  logic [7:0] s00,s01,s02,s10,s11,s12,s20,s21,s22;
  logic sobel_valid;
  logic [10:0] sobel_mag;
  logic [1:0] sobel_dir;
  logic [X_W-1:0] sm_x0,sm_x1,sm_x2,sm_x3;
  logic [Y_W-1:0] sm_y0,sm_y1,sm_y2,sm_y3;
  logic sm_sof0,sm_sof1,sm_sof2,sm_sof3;
  logic sm_eol0,sm_eol1,sm_eol2,sm_eol3;

  logic n_win_valid;
  logic [X_W-1:0] n_win_x;
  logic [Y_W-1:0] n_win_y;
  logic [12:0] n00,n01,n02,n10,n11,n12,n20,n21,n22;
  logic [10:0] nms_mag;
  logic nms_keep;
  logic nms_eof;
  logic cls_valid;
  logic [1:0] cls;

  linebuf #(.IMG_W(IMG_W), .IMG_H(IMG_H), .DATA_W(8), .X_W(X_W), .Y_W(Y_W)) u_gauss_lb (
    .clk, .rst, .pix_valid(in_valid), .pix_sof(in_sof), .pix_eol(in_eol), .pix_data(in_gray),
    .win_valid(g_win_valid), .win_x(g_win_x), .win_y(g_win_y),
    .w00(g00), .w01(g01), .w02(g02), .w10(g10), .w11(g11), .w12(g12), .w20(g20), .w21(g21), .w22(g22)
  );
  gauss u_gauss (
    .clk, .in_valid(g_win_valid), .w00(g00), .w01(g01), .w02(g02), .w10(g10), .w11(g11), .w12(g12), .w20(g20), .w21(g21), .w22(g22),
    .out_valid(gauss_valid), .smooth
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      gauss_sof <= 1'b0;
      gauss_eol <= 1'b0;
    end else begin
      gauss_sof <= g_win_valid && (g_win_x == 1) && (g_win_y == 1);
      gauss_eol <= g_win_valid && (g_win_x == IMG_W - 2);
    end
  end

  linebuf #(.IMG_W(G_W), .IMG_H(G_H), .DATA_W(8), .X_W(X_W), .Y_W(Y_W)) u_sobel_lb (
    .clk, .rst, .pix_valid(gauss_valid), .pix_sof(gauss_sof), .pix_eol(gauss_eol), .pix_data(smooth),
    .win_valid(s_win_valid), .win_x(s_win_x), .win_y(s_win_y),
    .w00(s00), .w01(s01), .w02(s02), .w10(s10), .w11(s11), .w12(s12), .w20(s20), .w21(s21), .w22(s22)
  );
  sobel u_sobel (
    .clk, .in_valid(s_win_valid), .w00(s00), .w01(s01), .w02(s02), .w10(s10), .w11(s11), .w12(s12), .w20(s20), .w21(s21), .w22(s22),
    .out_valid(sobel_valid), .magnitude(sobel_mag), .direction(sobel_dir)
  );

  // Sobel has four registered stages from input window to output.
  always_ff @(posedge clk) begin
    if (rst) begin
      sm_x0 <= '0; sm_x1 <= '0; sm_x2 <= '0; sm_x3 <= '0;
      sm_y0 <= '0; sm_y1 <= '0; sm_y2 <= '0; sm_y3 <= '0;
      sm_sof0 <= 0; sm_sof1 <= 0; sm_sof2 <= 0; sm_sof3 <= 0;
      sm_eol0 <= 0; sm_eol1 <= 0; sm_eol2 <= 0; sm_eol3 <= 0;
    end else begin
      sm_x0 <= s_win_x; sm_x1 <= sm_x0; sm_x2 <= sm_x1; sm_x3 <= sm_x2;
      sm_y0 <= s_win_y; sm_y1 <= sm_y0; sm_y2 <= sm_y1; sm_y3 <= sm_y2;
      sm_sof0 <= s_win_valid && (s_win_x == 1) && (s_win_y == 1);
      sm_sof1 <= sm_sof0; sm_sof2 <= sm_sof1; sm_sof3 <= sm_sof2;
      sm_eol0 <= s_win_valid && (s_win_x == G_W - 2);
      sm_eol1 <= sm_eol0; sm_eol2 <= sm_eol1; sm_eol3 <= sm_eol2;
    end
  end

  linebuf #(.IMG_W(S_W), .IMG_H(S_H), .DATA_W(13), .X_W(X_W), .Y_W(Y_W)) u_nms_lb (
    .clk, .rst, .pix_valid(sobel_valid), .pix_sof(sm_sof3), .pix_eol(sm_eol3), .pix_data({sobel_dir,sobel_mag}),
    .win_valid(n_win_valid), .win_x(n_win_x), .win_y(n_win_y),
    .w00(n00), .w01(n01), .w02(n02), .w10(n10), .w11(n11), .w12(n12), .w20(n20), .w21(n21), .w22(n22)
  );
  dirnms u_nms (
    .magnitude(n11[10:0]), .direction(n11[12:11]),
    .mag_nw(n00[10:0]), .mag_n(n01[10:0]), .mag_ne(n02[10:0]), .mag_w(n10[10:0]), .mag_e(n12[10:0]),
    .mag_sw(n20[10:0]), .mag_s(n21[10:0]), .mag_se(n22[10:0]), .nms_mag, .keep(nms_keep)
  );
  assign nms_eof = n_win_valid && (n_win_x == S_W - 2) && (n_win_y == S_H - 2);

  classify_hist u_classify_hist (
    .clk, .rst, .thr_lo, .thr_hi, .nms_valid(n_win_valid), .nms_mag, .frame_end(nms_eof), .clear(clear_hist),
    .hist_rd_addr, .hist_rd_data, .hist_nnz, .hist_valid, .cls_valid, .cls
  );

  // classifier is a single registered stage; NMS-local (1,1) maps to
  // original-image coordinate (3,3).
  always_ff @(posedge clk) begin
    if (rst) begin
      out_x <= '0; out_y <= '0; out_sof <= 0; out_eol <= 0;
    end else begin
      out_x <= n_win_x + 2;
      out_y <= n_win_y + 2;
      out_sof <= n_win_valid && (n_win_x == 1) && (n_win_y == 1);
      out_eol <= n_win_valid && (n_win_x == S_W - 2);
    end
  end
  assign out_valid = cls_valid;
  assign out_cls = cls;
endmodule

`default_nettype wire
