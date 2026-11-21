// SymbiYosys harness for the APB3 register bank (rtl/apb_regs.sv); bus inputs and events unconstrained.
module props_apb (input wire clk, input wire rst, input wire psel, penable, pwrite, input wire [7:0] paddr, input wire [31:0] pwdata,
                  input wire fd, uf, of, se, hv, input wire [19:0] ec, input wire [31:0] fc, crc, input wire [10:0] tha, tla, input wire [18:0] hd);
  wire [31:0] prdata, crc_gold, auto_cfg; wire pready, pslverr, enable, auto_threshold, hyst_enable, threshold_cpu, clr;
  wire [1:0] view_mode; wire [10:0] thr_hi, thr_lo; wire [5:0] hist_idx;
  apb_regs dut (.pclk(clk), .rst, .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr, .enable, .auto_threshold,
    .view_mode, .hyst_enable, .threshold_cpu, .clear_hist_sticky(clr), .thr_hi, .thr_lo, .crc_gold, .auto_cfg, .hist_idx,
    .frame_done_i(fd), .fifo_underflow_i(uf), .fifo_overflow_i(of), .sync_error_i(se), .hist_valid_i(hv), .edge_cnt_i(ec),
    .frame_cnt_i(fc), .crc_out_i(crc), .thr_hi_auto_i(tha), .thr_lo_auto_i(tla), .hist_data_i(hd));
  reg init = 1'b1;
  always @(posedge clk) begin
    init <= 1'b0;
    if (init) assume (rst);
    if (!init) begin
      assert (pready);                                              // zero-wait-state slave
      assert (!pslverr || (psel && penable));                       // errors only in the ACCESS phase
      if ($past(!rst) && $past(psel && penable && pwrite && paddr == 8'h10))   // write to read-only EDGE_CNT ...
        assert ($past(pslverr) && thr_hi == $past(thr_hi) && thr_lo == $past(thr_lo));  // ... is rejected, nothing changes
      if ($past(!rst) && $past(!(psel && penable && pwrite))) assert (thr_hi == $past(thr_hi) && thr_lo == $past(thr_lo));   // no spurious writes
      if ($past(!rst) && $past(fd) && paddr == 8'h0c) assert (prdata[0]);   // a frame-done event is never lost (set wins over a clear), read via STATUS
      if ($past(!rst) && $past(psel && penable && pwrite && paddr == 8'h04 && !pslverr)) assert (thr_hi == $past(pwdata[10:0]));
    end
  end
endmodule
