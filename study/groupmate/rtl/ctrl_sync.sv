// ctrl_sync -- frame / line synchronisation tracker for the streaming pipeline.
//
// The core sees a free-running raster of WT x HT cycles per frame (active area W x H in the
// top-left corner, the rest is blanking).  The producer marks the origin cell (0,0) with a
// one-cycle `sof` pulse.  ctrl_sync keeps the (x,y) coordinate of the pixel that is on the bus in
// the CURRENT cycle; every downstream stage carries that coordinate with its data (the "tag"),
// so no stage needs its own counters and line buffers are addressed by tag-x.
//
// FSM (2 states, see doc/FINAL_MAIN_PIPELINE_REPORT.md for the diagram):
//   IDLE : x=y=0 held.  sof && run_en            -> RUN   (this cycle is cell (0,0))
//   RUN  : x/y count the raster, wrap at (WT-1,HT-1).
//            run_en==0                            -> IDLE  (abort, counters cleared)
//            at the last cell: next frame follows only if run_en (free-running), the producer is
//            expected to give `sof` exactly at (0,0); if sof arrives anywhere else sync_err pulses
//            and the counters are re-aligned (this cycle becomes cell (0,0)).
// No full-frame storage anywhere: only counters.
module ctrl_sync #(
  parameter int W  = 640,
  parameter int H  = 480,
  parameter int WT = 800,
  parameter int HT = 525,
  parameter int XW = 10
) (
  input  logic          clk,
  input  logic          rst,          // synchronous, active high
  input  logic          run_en,       // CTRL.EN
  input  logic          sof,          // 1 cycle: current pixel is raster origin
  output logic          locked,       // state == RUN
  output logic [XW-1:0] x,            // coordinate of the pixel on the bus this cycle
  output logic [XW-1:0] y,
  output logic          pix_ok,       // coordinates are meaningful this cycle (RUN, or the sof cycle)
  output logic          in_act,       // pix_ok && x<W && y<H
  output logic          frame_start,  // pix_ok && (x,y)==(0,0)
  output logic          frame_end,    // pix_ok && (x,y)==(WT-1,HT-1)
  output logic          sync_err      // sof seen at a cell other than (0,0) while RUN
);
  typedef enum logic {S_IDLE = 1'b0, S_RUN = 1'b1} state_t;
  state_t st;
  logic [XW-1:0] xq, yq;
  logic          last_x, last_y, at_origin;

  assign last_x    = (xq == XW'(WT - 1));
  assign last_y    = (yq == XW'(HT - 1));
  assign at_origin = (xq == '0) && (yq == '0);
  assign locked    = (st == S_RUN);
  assign pix_ok    = locked || (sof && run_en);
  assign x         = xq;
  assign y         = yq;
  assign in_act    = pix_ok && (xq < XW'(W)) && (yq < XW'(H));
  assign frame_start = pix_ok && at_origin;
  assign frame_end   = pix_ok && last_x && last_y;
  assign sync_err    = locked && sof && !at_origin;

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= S_IDLE; xq <= '0; yq <= '0;
    end else begin
      case (st)
        S_IDLE: begin
          xq <= '0; yq <= '0;
          if (sof && run_en) begin
            st <= S_RUN;
            xq <= XW'(1);                       // this cycle was (0,0); next is (1,0)
            if (WT == 1) xq <= '0;
          end
        end
        S_RUN: begin
          if (!run_en) begin
            st <= S_IDLE; xq <= '0; yq <= '0;
          end else if (sof && !at_origin) begin  // resync: current cycle is the origin
            xq <= XW'(1); yq <= '0;
          end else begin
            if (last_x) begin
              xq <= '0;
              yq <= last_y ? '0 : yq + 1'b1;
            end else begin
              xq <= xq + 1'b1;
            end
          end
        end
        default: begin st <= S_IDLE; xq <= '0; yq <= '0; end
      endcase
    end
  end
endmodule
