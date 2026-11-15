// apb_regs -- APB3 slave: threshold registers, status, edge/weak counters, frame counter, 16-bin NMS histogram.
// Plain APB3 (PSEL/PENABLE/PWRITE/PADDR/PWDATA/PRDATA/PREADY/PSLVERR): zero wait states, never errors, so a
// standard RV32 core's APB bridge could attach directly (no RV32 is instantiated in this project -- optional per plan).
// Every register bit is documented in doc/register_map.md.
//
// Thresholds: THR_HI/THR_LO are written any time but only take effect at the next frame boundary (latched
// into the active registers at frame_end); while the sync tracker is IDLE the active registers follow the written ones.
// Counters: strong/weak/histogram counters run on the classified pixel stream and are snapshotted at frame_end,
// so EDGE_CNT/WEAK_CNT/HIST_DATA always describe the LAST COMPLETED frame.
module apb_regs (
  input  logic        clk,
  input  logic        rst,
  // APB3 slave
  input  logic        psel,
  input  logic        penable,
  input  logic        pwrite,
  input  logic [7:0]  paddr,
  input  logic [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,
  // core side
  input  logic        locked,        // ctrl_sync in RUN
  input  logic        frame_end,     // input-side end of frame pulse
  input  logic        sync_err,      // resync event pulse
  input  logic [1:0]  cls,           // classified pixel stream
  input  logic [10:0] nms,           // NMS magnitude aligned with cls
  output logic        en,            // CTRL.EN
  output logic [10:0] thr_hi_act,    // thresholds actually applied by classify
  output logic [10:0] thr_lo_act
);
  localparam logic [7:0] A_CTRL = 8'h00, A_THR_HI = 8'h04, A_THR_LO = 8'h08, A_STATUS = 8'h0C, A_EDGE = 8'h10,
                         A_FRAME = 8'h14, A_WEAK = 8'h18, A_HSEL = 8'h1C, A_HDATA = 8'h20, A_ID = 8'h24, A_THRACT = 8'h28;
  localparam logic [31:0] ID_VALUE = 32'h5037_0001;

  assign pready = 1'b1;
  assign pslverr = 1'b0;

  logic [10:0] thr_hi_r, thr_lo_r;
  logic        st_done, st_err;
  logic [3:0]  hsel;
  logic [19:0] strong_live, weak_live, edge_cnt, weak_cnt;
  logic [19:0] hist_live [0:15];
  logic [19:0] hist_snap [0:15];
  logic [31:0] frame_cnt;

  logic wr, clr_req;
  assign wr = psel && penable && pwrite;
  assign clr_req = wr && (paddr == A_CTRL) && pwdata[1];

  always_ff @(posedge clk) begin
    if (rst) begin
      en <= 1'b1; thr_hi_r <= 11'd192; thr_lo_r <= 11'd64; thr_hi_act <= 11'd192; thr_lo_act <= 11'd64;
      st_done <= 1'b0; st_err <= 1'b0; hsel <= 4'd0;
      strong_live <= '0; weak_live <= '0; edge_cnt <= '0; weak_cnt <= '0; frame_cnt <= '0;
      for (int i = 0; i < 16; i++) begin hist_live[i] <= '0; hist_snap[i] <= '0; end
    end else begin
      // ---- APB writes
      if (wr) begin
        case (paddr)
          A_CTRL:   en <= pwdata[0];
          A_THR_HI: thr_hi_r <= pwdata[10:0];
          A_THR_LO: thr_lo_r <= pwdata[10:0];
          A_STATUS: begin if (pwdata[1]) st_done <= 1'b0; if (pwdata[2]) st_err <= 1'b0; end   // W1C
          A_HSEL:   hsel <= pwdata[3:0];
          default: ;
        endcase
      end
      // ---- sticky status events (set wins over W1C in the same cycle)
      if (frame_end) st_done <= 1'b1;
      if (sync_err)  st_err  <= 1'b1;
      // ---- live counters on the classified stream
      if (cls == 2'd2) strong_live <= strong_live + 1'b1;
      if (cls == 2'd1) weak_live   <= weak_live + 1'b1;
      if (nms != 11'd0) hist_live[nms[10:7]] <= hist_live[nms[10:7]] + 1'b1;
      // ---- frame boundary: snapshot, clear live counters, latch thresholds
      if (frame_end) begin
        edge_cnt <= strong_live; weak_cnt <= weak_live;
        for (int i = 0; i < 16; i++) hist_snap[i] <= hist_live[i];
        strong_live <= '0; weak_live <= '0;
        for (int i = 0; i < 16; i++) hist_live[i] <= '0;
        frame_cnt <= frame_cnt + 1'b1;
        thr_hi_act <= thr_hi_r; thr_lo_act <= thr_lo_r;
      end else if (!locked) begin
        thr_hi_act <= thr_hi_r; thr_lo_act <= thr_lo_r;      // idle: active follows written values
      end
      // ---- CTRL.CLR: clear all counters / snapshots (wins over frame_end)
      if (clr_req) begin
        strong_live <= '0; weak_live <= '0; edge_cnt <= '0; weak_cnt <= '0; frame_cnt <= '0;
        for (int i = 0; i < 16; i++) begin hist_live[i] <= '0; hist_snap[i] <= '0; end
      end
    end
  end

  always_comb begin
    prdata = 32'd0;
    case (paddr)
      A_CTRL:   prdata = {31'd0, en};
      A_THR_HI: prdata = {21'd0, thr_hi_r};
      A_THR_LO: prdata = {21'd0, thr_lo_r};
      A_STATUS: prdata = {28'd0, ((thr_hi_r != thr_hi_act) || (thr_lo_r != thr_lo_act)), st_err, st_done, locked};
      A_EDGE:   prdata = {12'd0, edge_cnt};
      A_FRAME:  prdata = frame_cnt;
      A_WEAK:   prdata = {12'd0, weak_cnt};
      A_HSEL:   prdata = {28'd0, hsel};
      A_HDATA:  prdata = {12'd0, hist_snap[hsel]};
      A_ID:     prdata = ID_VALUE;
      A_THRACT: prdata = {5'd0, thr_lo_act, 5'd0, thr_hi_act};
      default:  prdata = 32'd0;
    endcase
  end
endmodule
