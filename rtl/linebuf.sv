`default_nettype none

// Two-row, one-pixel-per-clock line buffer.  It emits only complete 3x3
// windows: the output centre is (input_col-1,input_row-1).  Border insertion
// and V-blank flushing belong to ctrl_sync, not this reusable storage block.
module linebuf #(
  parameter int unsigned IMG_W = 640,
  parameter int unsigned IMG_H = 480,
  parameter int unsigned DATA_W = 8,
  parameter int unsigned X_W = $clog2(IMG_W),
  parameter int unsigned Y_W = $clog2(IMG_H)
) (
  input  wire               clk,
  input  wire               rst,
  input  wire               pix_valid,
  input  wire               pix_sof,
  input  wire               pix_eol,
  input  wire  [DATA_W-1:0] pix_data,
  output logic              win_valid,
  output logic [X_W-1:0]    win_x,
  output logic [Y_W-1:0]    win_y,
  output logic [DATA_W-1:0] w00,
  output logic [DATA_W-1:0] w01,
  output logic [DATA_W-1:0] w02,
  output logic [DATA_W-1:0] w10,
  output logic [DATA_W-1:0] w11,
  output logic [DATA_W-1:0] w12,
  output logic [DATA_W-1:0] w20,
  output logic [DATA_W-1:0] w21,
  output logic [DATA_W-1:0] w22
);

  // Alternating row banks: the bank being overwritten contains row y-2.
  // Both reads are synchronous read-first, including the write/read collision.
  // No RAM reset is needed: validity suppresses the first two rows of a frame.
  (* ram_style = "block" *) logic [DATA_W-1:0] rows_even [0:IMG_W-1];
  (* ram_style = "block" *) logic [DATA_W-1:0] rows_odd  [0:IMG_W-1];
  logic [DATA_W-1:0] even_q, odd_q, data_q;
  logic [X_W-1:0] col, sample_x, read_x;
  logic [Y_W-1:0] row, sample_y, read_y;
  logic sample_valid;
  logic [DATA_W-1:0] top_sample, mid_sample;
  logic [DATA_W-1:0] top_d1, top_d2, mid_d1, mid_d2, bot_d1, bot_d2;

  initial begin
    if (IMG_W < 3 || IMG_H < 3 || X_W < $clog2(IMG_W) || Y_W < $clog2(IMG_H))
      $fatal(1, "linebuf requires dimensions >= 3 and sufficient coordinate widths");
  end

  assign read_x = pix_sof ? '0 : col;
  assign read_y = pix_sof ? '0 : row;
  assign top_sample = sample_y[0] ? odd_q : even_q;
  assign mid_sample = sample_y[0] ? even_q : odd_q;

  // Keep these memory ports free of reset muxes for RAMB18 inference.
  always_ff @(posedge clk) begin
    if (pix_valid && !rst) begin
      even_q <= rows_even[read_x];
      odd_q <= rows_odd[read_x];
      if (read_y[0]) rows_odd[read_x] <= pix_data;
      else rows_even[read_x] <= pix_data;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      col <= '0; row <= '0;
      sample_valid <= 0; sample_x <= '0; sample_y <= '0; data_q <= '0;
      win_valid <= 0; win_x <= '0; win_y <= '0;
      top_d1 <= '0; top_d2 <= '0; mid_d1 <= '0; mid_d2 <= '0;
      bot_d1 <= '0; bot_d2 <= '0;
      w00 <= '0; w01 <= '0; w02 <= '0;
      w10 <= '0; w11 <= '0; w12 <= '0;
      w20 <= '0; w21 <= '0; w22 <= '0;
    end else begin
      sample_valid <= pix_valid;
      if (pix_valid) begin
        sample_x <= read_x; sample_y <= read_y; data_q <= pix_data;
        if (pix_eol) begin
          col <= '0;
          row <= (read_y == Y_W'(IMG_H-1)) ? '0 : read_y + 1'b1;
        end else begin
          col <= read_x + 1'b1;
          row <= read_y;
        end
      end
      win_valid <= sample_valid && (sample_y >= 2) && (sample_x >= 2);
      if (sample_valid) begin
        win_x <= sample_x - 1'b1; win_y <= sample_y - 1'b1;
        w00 <= top_d2; w01 <= top_d1; w02 <= top_sample;
        w10 <= mid_d2; w11 <= mid_d1; w12 <= mid_sample;
        w20 <= bot_d2; w21 <= bot_d1; w22 <= data_q;
        top_d2 <= top_d1; top_d1 <= top_sample;
        mid_d2 <= mid_d1; mid_d1 <= mid_sample;
        bot_d2 <= bot_d1; bot_d1 <= data_q;
      end
    end
  end

endmodule

`default_nettype wire

