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
  input  wire                clk,
  input  wire                rst,
  input  wire  [MAG_W-1:0]   thr_lo,
  input  wire  [MAG_W-1:0]   thr_hi,
  input  wire                nms_valid,
  input  wire  [MAG_W-1:0]   nms_mag,
  input  wire                frame_end,
  input  wire                clear,
  input  wire  [5:0]         hist_rd_addr,
  output logic [COUNT_W-1:0] hist_rd_data,
  output logic [COUNT_W-1:0] hist_nnz,
  output logic               hist_valid,
  output logic               cls_valid,
  output logic [1:0]         cls
);
  localparam logic [COUNT_W-1:0] COUNT_MAX = {COUNT_W{1'b1}};

  logic [COUNT_W-1:0] hist_0 [0:63];
  logic [COUNT_W-1:0] hist_1 [0:63];
  logic [COUNT_W-1:0] nnz_0, nnz_1;
  logic active_bank;
  logic [5:0] bin;
  integer i;

  initial begin
    if (MAG_W < 6 || COUNT_W < 1) $fatal(1, "invalid histogram widths");
  end

  always_comb begin
    bin = nms_mag[MAG_W-1 -: 6];
    // The just-completed bank is never written until the next frame_end, so it IS the snapshot
    // (the separate snapshot copy used to cost 64 x COUNT_W flip-flops).
    hist_rd_data = active_bank ? hist_0[hist_rd_addr] : hist_1[hist_rd_addr];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      cls_valid <= 1'b0;
      cls <= '0;
    end else begin
      // Histogram maintenance must never remove a pixel from the stream.
      cls_valid <= nms_valid;
      if ((nms_mag != '0) && (nms_mag >= thr_hi)) begin
        cls <= 2'b10;
      end else if ((nms_mag != '0) && (nms_mag >= thr_lo)) begin
        cls <= 2'b01;
      end else begin
        cls <= 2'b00;
      end
    end

    if (rst || clear) begin
      active_bank <= 1'b0;
      nnz_0 <= '0;
      nnz_1 <= '0;
      hist_nnz <= '0;
      hist_valid <= 1'b0;
      for (i = 0; i < 64; i = i + 1) begin
        hist_0[i] <= '0;
        hist_1[i] <= '0;
      end
    end else begin
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
        // A final valid NMS survivor is counted by the normal increment above in this same cycle;
        // the finished bank then holds the complete frame.
        for (i = 0; i < 64; i = i + 1) begin
          if (!active_bank) begin
            hist_1[i] <= '0;
          end else begin
            hist_0[i] <= '0;
          end
        end
        if (!active_bank) begin
          hist_nnz <= nnz_0 + COUNT_W'(nms_valid && (nms_mag != '0) && (nnz_0 != COUNT_MAX));
          nnz_1 <= '0;
        end else begin
          hist_nnz <= nnz_1 + COUNT_W'(nms_valid && (nms_mag != '0) && (nnz_1 != COUNT_MAX));
          nnz_0 <= '0;
        end
        active_bank <= ~active_bank;
        hist_valid <= 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
