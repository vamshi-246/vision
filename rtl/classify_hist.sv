`default_nettype none

// One-pixel-per-clock double threshold classifier and 64-bin NMS histogram.
// Counters are registers in this portable baseline.  Consequently each
// increment sees the committed value from the preceding clock and consecutive
// hits to the same bin cannot be lost (the BRAM implementation must preserve
// this behaviour with an explicit forwarding path).
module classify_hist #(
  parameter int unsigned MAG_W = 11,
  parameter int unsigned COUNT_W = 19
) (
  input  logic               clk,
  input  logic               rst,
  input  logic [MAG_W-1:0]   thr_lo,
  input  logic [MAG_W-1:0]   thr_hi,
  input  logic               nms_valid,
  input  logic [MAG_W-1:0]   nms_mag,
  input  logic               frame_end,
  input  logic               clear,
  input  logic [5:0]         hist_rd_addr,
  output logic [COUNT_W-1:0] hist_rd_data,
  output logic [COUNT_W-1:0] hist_nnz,
  output logic               hist_valid,
  output logic               cls_valid,
  output logic [1:0]         cls
);
  localparam logic [COUNT_W-1:0] COUNT_MAX = {COUNT_W{1'b1}};

  logic [COUNT_W-1:0] hist_0 [0:63];
  logic [COUNT_W-1:0] hist_1 [0:63];
  logic [COUNT_W-1:0] snapshot [0:63];
  logic [COUNT_W-1:0] nnz_0, nnz_1;
  logic active_bank;
  logic [5:0] bin;
  integer i;

  always_comb begin
    bin = nms_mag[MAG_W-1 -: 6];
    hist_rd_data = snapshot[hist_rd_addr];
  end

  always_ff @(posedge clk) begin
    if (rst || clear) begin
      active_bank <= 1'b0;
      nnz_0 <= '0;
      nnz_1 <= '0;
      hist_nnz <= '0;
      hist_valid <= 1'b0;
      cls_valid <= 1'b0;
      cls <= '0;
      for (i = 0; i < 64; i = i + 1) begin
        hist_0[i] <= '0;
        hist_1[i] <= '0;
        snapshot[i] <= '0;
      end
    end else begin
      cls_valid <= nms_valid;
      if (nms_mag >= thr_hi) begin
        cls <= 2'b10;
      end else if ((nms_mag != '0) && (nms_mag >= thr_lo)) begin
        cls <= 2'b01;
      end else begin
        cls <= 2'b00;
      end

      if (nms_valid && (nms_mag != '0)) begin
        if (!active_bank) begin
          if (hist_0[bin] != COUNT_MAX) hist_0[bin] <= hist_0[bin] + 1'b1;
          if (nnz_0 != COUNT_MAX) nnz_0 <= nnz_0 + 1'b1;
        end else begin
          if (hist_1[bin] != COUNT_MAX) hist_1[bin] <= hist_1[bin] + 1'b1;
          if (nnz_1 != COUNT_MAX) nnz_1 <= nnz_1 + 1'b1;
        end
      end

      if (frame_end) begin
        // Include a final valid NMS survivor in the coherent snapshot.
        for (i = 0; i < 64; i = i + 1) begin
          if (!active_bank) begin
            snapshot[i] <= hist_0[i] + ((nms_valid && (nms_mag != '0) && (bin == i) && (hist_0[i] != COUNT_MAX)) ? 1'b1 : 1'b0);
            hist_1[i] <= '0;
          end else begin
            snapshot[i] <= hist_1[i] + ((nms_valid && (nms_mag != '0) && (bin == i) && (hist_1[i] != COUNT_MAX)) ? 1'b1 : 1'b0);
            hist_0[i] <= '0;
          end
        end
        if (!active_bank) begin
          hist_nnz <= nnz_0 + ((nms_valid && (nms_mag != '0) && (nnz_0 != COUNT_MAX)) ? 1'b1 : 1'b0);
          nnz_1 <= '0;
        end else begin
          hist_nnz <= nnz_1 + ((nms_valid && (nms_mag != '0) && (nnz_1 != COUNT_MAX)) ? 1'b1 : 1'b0);
          nnz_0 <= '0;
        end
        active_bank <= ~active_bank;
        hist_valid <= 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
