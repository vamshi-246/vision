// paper_histogram.sv -- one-pass 256-bin histogram builder (32-bit counters).
// Sequentially reads W*H pixels from paper_frame_buffer (1-cycle read latency) and also
// accumulates total count, total grey-level sum, min and max for the Otsu stage.
// Bins are a flop array here (simple, hazard-free for back-to-back identical hist_bins);
// mapping to BRAM with read-modify-write forwarding is deferred to the implementation phase.
module paper_histogram #(
  parameter int W  = 64,
  parameter int H  = 64,
  parameter int AW = (W*H > 1) ? $clog2(W*H) : 1
) (
  input  logic          clk,
  input  logic          rst,
  input  logic          start,        // 1-cycle pulse
  output logic          busy,
  output logic          done,         // 1-cycle pulse
  // frame buffer read port
  output logic [AW-1:0] fb_raddr,
  input  logic [7:0]    fb_rdata,
  // histogram read port (1-cycle latency)
  input  logic [7:0]    hist_raddr,
  output logic [31:0]   hist_rdata,
  // frame statistics
  output logic [31:0]   tot_cnt,
  output logic [31:0]   tot_sum,
  output logic [7:0]    min_val,
  output logic [7:0]    max_val
);
  localparam logic [AW-1:0] LAST = AW'(W*H - 1);

  logic [31:0] hist_bins [0:255];
  logic [AW-1:0] addr;
  logic issue, v1;

  assign fb_raddr = addr;

  // waveform visibility: bin being incremented and the count being written to it
  logic [7:0]  dbg_bin_idx;
  logic [31:0] dbg_bin_cnt;
  assign dbg_bin_idx = fb_rdata;
  assign dbg_bin_cnt = hist_bins[fb_rdata] + 32'd1;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < 256; i++) hist_bins[i] <= 32'd0;
      addr    <= '0;
      issue   <= 1'b0;
      v1      <= 1'b0;
      busy    <= 1'b0;
      done    <= 1'b0;
      tot_cnt <= 32'd0;
      tot_sum <= 32'd0;
      min_val <= 8'hFF;
      max_val <= 8'h00;
    end else begin
      done <= 1'b0;
      v1   <= 1'b0;
      if (start && !busy) begin
        for (int i = 0; i < 256; i++) hist_bins[i] <= 32'd0;
        addr    <= '0;
        issue   <= 1'b1;
        busy    <= 1'b1;
        tot_cnt <= 32'd0;
        tot_sum <= 32'd0;
        min_val <= 8'hFF;
        max_val <= 8'h00;
      end else begin
        if (issue) begin
          v1 <= 1'b1;
          if (addr == LAST) issue <= 1'b0;
          else              addr  <= addr + 1'b1;
        end
        if (v1) begin
          hist_bins[fb_rdata] <= hist_bins[fb_rdata] + 32'd1;
          tot_cnt <= tot_cnt + 32'd1;
          tot_sum <= tot_sum + {24'd0, fb_rdata};
          if (fb_rdata < min_val) min_val <= fb_rdata;
          if (fb_rdata > max_val) max_val <= fb_rdata;
        end
        if (busy && !issue && !v1) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) hist_rdata <= hist_bins[hist_raddr];
endmodule
