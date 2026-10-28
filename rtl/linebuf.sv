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
  input  logic              clk,
  input  logic              rst,
  input  logic              pix_valid,
  input  logic              pix_sof,
  input  logic              pix_eol,
  input  logic [DATA_W-1:0] pix_data,
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

  (* ram_style = "block" *) logic [DATA_W-1:0] row_1 [0:IMG_W-1];
  (* ram_style = "block" *) logic [DATA_W-1:0] row_2 [0:IMG_W-1];
  logic [X_W-1:0] col;
  logic [Y_W-1:0] row;
  logic [DATA_W-1:0] top_sample;
  logic [DATA_W-1:0] mid_sample;
  logic [DATA_W-1:0] top_d1, top_d2;
  logic [DATA_W-1:0] mid_d1, mid_d2;
  logic [DATA_W-1:0] bot_d1, bot_d2;

  // Reads are deliberately expressed outside the clocked block: at a valid
  // edge they observe the pre-write values for the current column.
  always_comb begin
    top_sample = row_2[col];
    mid_sample = row_1[col];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      col       <= '0;
      row       <= '0;
      win_valid <= 1'b0;
      win_x     <= '0;
      win_y     <= '0;
      top_d1    <= '0;
      top_d2    <= '0;
      mid_d1    <= '0;
      mid_d2    <= '0;
      bot_d1    <= '0;
      bot_d2    <= '0;
      w00 <= '0; w01 <= '0; w02 <= '0;
      w10 <= '0; w11 <= '0; w12 <= '0;
      w20 <= '0; w21 <= '0; w22 <= '0;
    end else begin
      win_valid <= 1'b0;
      if (pix_valid) begin
        row_2[col] <= mid_sample;
        row_1[col] <= pix_data;

        w00 <= top_d2;    w01 <= top_d1;    w02 <= top_sample;
        w10 <= mid_d2;    w11 <= mid_d1;    w12 <= mid_sample;
        w20 <= bot_d2;    w21 <= bot_d1;    w22 <= pix_data;
        top_d2 <= top_d1; top_d1 <= top_sample;
        mid_d2 <= mid_d1; mid_d1 <= mid_sample;
        bot_d2 <= bot_d1; bot_d1 <= pix_data;

        win_valid <= (row >= 2) && (col >= 2);
        win_x <= col - 1'b1;
        win_y <= row - 1'b1;

        if (pix_sof) begin
          col <= pix_eol ? '0 : {{(X_W-1){1'b0}}, 1'b1};
          row <= pix_eol ? {{(Y_W-1){1'b0}}, 1'b1} : '0;
        end else if (pix_eol) begin
          col <= '0;
          row <= (row == IMG_H - 1) ? '0 : row + 1'b1;
        end else begin
          col <= col + 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire

