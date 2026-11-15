`default_nettype none

// CPU-independent APB3-compatible control/status register bank, Section 7.6.
// PREADY is permanently high: setup and access phases still follow APB.
module apb_regs #(
  parameter logic [31:0] VERSION = 32'h5037_0300
) (
  input  wire         pclk,
  input  wire         rst,
  input  wire         psel,
  input  wire         penable,
  input  wire         pwrite,
  input  wire  [7:0]  paddr,
  input  wire  [31:0] pwdata,
  output logic [31:0] prdata,
  output logic        pready,
  output logic        pslverr,
  output logic        enable,
  output logic        auto_threshold,
  output logic [1:0]  view_mode,
  output logic        hyst_enable,
  output logic        threshold_cpu,
  output logic        clear_hist_sticky,
  output logic [10:0] thr_hi,
  output logic [10:0] thr_lo,
  output logic [31:0] crc_gold,
  output logic [31:0] auto_cfg,
  output logic [5:0]  hist_idx,
  input  wire         frame_done_i,
  input  wire         fifo_underflow_i,
  input  wire         fifo_overflow_i,
  input  wire         sync_error_i,
  input  wire         hist_valid_i,
  input  wire  [19:0] edge_cnt_i,
  input  wire  [31:0] frame_cnt_i,
  input  wire  [31:0] crc_out_i,
  input  wire  [10:0] thr_hi_auto_i,
  input  wire  [10:0] thr_lo_auto_i,
  input  wire  [18:0] hist_data_i
);
  localparam logic [7:0] CTRL = 8'h00, THR_HI = 8'h04, THR_LO = 8'h08;
  localparam logic [7:0] STATUS = 8'h0c, EDGE_CNT = 8'h10, FRAME_CNT = 8'h14;
  localparam logic [7:0] CRC_OUT = 8'h18, CRC_GOLD = 8'h1c, THR_HI_AUTO = 8'h20;
  localparam logic [7:0] THR_LO_AUTO = 8'h24, AUTO_CFG = 8'h28, HIST_IDX = 8'h2c;
  localparam logic [7:0] HIST_DATA = 8'h30, VERSION_ADDR = 8'h34;
  logic [5:0] ctrl;
  logic [5:0] sticky;
  logic transfer, write_transfer;
  logic mapped, writable;
  logic [5:0] sticky_next;

  assign transfer = psel && penable;
  assign write_transfer = transfer && pwrite;
  assign pready = 1'b1;
  assign {threshold_cpu, hyst_enable, view_mode, auto_threshold, enable} = ctrl;
  assign clear_hist_sticky = write_transfer && !pslverr && (paddr == CTRL) && pwdata[6];

  always_comb begin
    mapped = (paddr == CTRL) || (paddr == THR_HI) || (paddr == THR_LO) ||
             (paddr == STATUS) || (paddr == EDGE_CNT) || (paddr == FRAME_CNT) ||
             (paddr == CRC_OUT) || (paddr == CRC_GOLD) || (paddr == THR_HI_AUTO) ||
             (paddr == THR_LO_AUTO) || (paddr == AUTO_CFG) || (paddr == HIST_IDX) ||
             (paddr == HIST_DATA) || (paddr == VERSION_ADDR);
    writable = (paddr == CTRL) || (paddr == THR_HI) || (paddr == THR_LO) ||
               (paddr == STATUS) || (paddr == CRC_GOLD) || (paddr == AUTO_CFG) ||
               (paddr == HIST_IDX);
    pslverr = transfer && (!mapped || (pwrite && !writable));
    prdata = '0;
    unique case (paddr)
      CTRL:         prdata = {26'b0, ctrl};
      THR_HI:       prdata = {21'b0, thr_hi};
      THR_LO:       prdata = {21'b0, thr_lo};
      STATUS:       prdata = {26'b0, sticky};
      EDGE_CNT:     prdata = {12'b0, edge_cnt_i};
      FRAME_CNT:    prdata = frame_cnt_i;
      CRC_OUT:      prdata = crc_out_i;
      CRC_GOLD:     prdata = crc_gold;
      THR_HI_AUTO:  prdata = {21'b0, thr_hi_auto_i};
      THR_LO_AUTO:  prdata = {21'b0, thr_lo_auto_i};
      AUTO_CFG:     prdata = auto_cfg;
      HIST_IDX:     prdata = {26'b0, hist_idx};
      HIST_DATA:    prdata = {13'b0, hist_data_i};
      VERSION_ADDR: prdata = VERSION;
      default:       prdata = '0;
    endcase
  end

  always_ff @(posedge pclk) begin
    if (rst) begin
      ctrl <= '0;
      thr_hi <= 11'd200;
      thr_lo <= 11'd80;
      crc_gold <= '0;
      auto_cfg <= 32'h0404_3210;
      hist_idx <= '0;
      sticky <= '0;
    end else begin
      sticky <= sticky_next;

      if (write_transfer && !pslverr) begin
        unique case (paddr)
          CTRL: begin
            ctrl <= pwdata[5:0];
          end
          THR_HI:   thr_hi <= pwdata[10:0];
          THR_LO:   thr_lo <= pwdata[10:0];
          STATUS:   ; // handled by the set-dominant sticky next-state logic
          CRC_GOLD: crc_gold <= pwdata;
          AUTO_CFG: auto_cfg <= pwdata;
          HIST_IDX: hist_idx <= pwdata[5:0];
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    sticky_next = sticky;
    if (write_transfer && !pslverr) begin
      if (paddr == CTRL && pwdata[6]) sticky_next = '0;
      if (paddr == STATUS) sticky_next = sticky_next & ~pwdata[5:0];
    end
    // Events win over simultaneous software clears, so none can be lost.
    if (frame_done_i) sticky_next[0] = 1'b1;
    if (fifo_underflow_i) sticky_next[1] = 1'b1;
    if (fifo_overflow_i) sticky_next[2] = 1'b1;
    if (sync_error_i) sticky_next[3] = 1'b1;
    if (hist_valid_i) sticky_next[4] = 1'b1;
    if (frame_done_i) sticky_next[5] = (crc_out_i == crc_gold);
  end
endmodule

`default_nettype wire
