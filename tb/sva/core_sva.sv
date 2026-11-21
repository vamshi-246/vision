`default_nettype none
// SystemVerilog assertions for the streaming core, attached with `bind` (the RTL itself is not modified).
// Each assertion names the design rule it protects; cover properties show the interesting cases are exercised.

module linebuf_sva #(parameter int unsigned IMG_W = 640, IMG_H = 480, X_W = 10, Y_W = 9) (
  input wire clk, rst, pix_valid, pix_eol, win_valid, input wire [X_W-1:0] win_x, col, input wire [Y_W-1:0] win_y, row);
  // A1: every emitted 3x3 window is centred inside the image (no window straddles a border)
  a_win_inside: assert property (@(posedge clk) disable iff (rst) win_valid |-> (win_x >= 1 && win_x <= X_W'(IMG_W-2) && win_y >= 1 && win_y <= Y_W'(IMG_H-2)));
  // A2: write pointers stay inside the line memory
  a_ptr_range:  assert property (@(posedge clk) disable iff (rst) (col < X_W'(IMG_W)) && (row < Y_W'(IMG_H)));
  // A3: an end-of-line pixel returns the column pointer to 0
  a_eol_wrap:   assert property (@(posedge clk) disable iff (rst) (pix_valid && pix_eol) |=> (col == '0));
endmodule

module sobel_sva (input wire clk, in_valid, out_valid, input wire [10:0] magnitude, input wire [1:0] direction);
  // A4: |Gx|+|Gy| of 8-bit pixels never exceeds 4*255 + 4*255 = 2040
  a_mag_bound: assert property (@(posedge clk) out_valid |-> magnitude <= 11'd2040);
  // A5: initiation interval 1, fixed 4-clock latency (every input window produces exactly one result 4 clocks later)
  a_latency4:  assert property (@(posedge clk) out_valid == $past(in_valid, 4));
  c_diag:      cover property (@(posedge clk) out_valid && direction[0]);
endmodule

module classify_sva (input wire clk, rst, nms_valid, frame_end, cls_valid, hist_valid, active_bank, input wire [1:0] cls,
                     input wire [10:0] nms_mag, thr_lo, thr_hi);
  // A6: the class code is one of none/weak/strong (2'b11 is illegal)
  a_cls_legal:  assert property (@(posedge clk) disable iff (rst) cls_valid |-> cls != 2'b11);
  // A7: classification is a single registered stage: exactly one class per NMS pixel, one clock later
  a_cls_stage:  assert property (@(posedge clk) disable iff (rst) cls_valid == $past(nms_valid));
  // A8: a strong class implies the magnitude reached the high threshold (and was non-zero)
  a_strong:     assert property (@(posedge clk) disable iff (rst) (nms_valid && nms_mag != 0 && nms_mag >= thr_hi) |=> cls == 2'b10);
  // A9: a frame end swaps the histogram banks and publishes a valid snapshot
  a_bank_swap:  assert property (@(posedge clk) disable iff (rst) frame_end |=> (active_bank != $past(active_bank)) && hist_valid);
  c_weak:       cover property (@(posedge clk) disable iff (rst) cls_valid && cls == 2'b01);
  c_strong:     cover property (@(posedge clk) disable iff (rst) cls_valid && cls == 2'b10);
endmodule

module pipeline_sva #(parameter int unsigned IMG_W = 640, IMG_H = 480, X_W = 10, Y_W = 9) (
  input wire clk, rst, out_valid, out_sof, out_eol, n_win_valid, input wire [X_W-1:0] out_x, input wire [Y_W-1:0] out_y,
  input wire [10:0] nms_mag, input wire [12:0] n11);
  // A10: output coordinates lie in the valid region [3, W-4] x [3, H-4] (three 3x3 stages, three-pixel border)
  a_out_region: assert property (@(posedge clk) disable iff (rst) out_valid |-> (out_x >= 3 && out_x <= X_W'(IMG_W-4) && out_y >= 3 && out_y <= Y_W'(IMG_H-4)));
  // A11: start-of-frame marker only on the first valid output pixel (3,3)
  a_out_sof:    assert property (@(posedge clk) disable iff (rst) out_sof |-> (out_valid && out_x == 3 && out_y == 3));
  // A12: end-of-line marker only on the last valid column
  a_out_eol:    assert property (@(posedge clk) disable iff (rst) out_eol |-> (out_valid && out_x == X_W'(IMG_W-4)));
  // A13: NMS never invents a magnitude: a surviving pixel keeps the centre magnitude of its window
  a_nms_keep:   assert property (@(posedge clk) disable iff (rst) (n_win_valid && nms_mag != 0) |-> nms_mag == n11[10:0]);
  c_frame:      cover property (@(posedge clk) disable iff (rst) out_valid && out_x == X_W'(IMG_W-4) && out_y == Y_W'(IMG_H-4));
endmodule

bind linebuf linebuf_sva #(.IMG_W(IMG_W), .IMG_H(IMG_H), .X_W(X_W), .Y_W(Y_W)) u_sva (.*);
bind sobel sobel_sva u_sva (.*);
bind classify_hist classify_sva u_sva (.*);
bind edge_pipeline pipeline_sva #(.IMG_W(IMG_W), .IMG_H(IMG_H), .X_W(X_W), .Y_W(Y_W)) u_sva (.*);
`default_nettype wire
