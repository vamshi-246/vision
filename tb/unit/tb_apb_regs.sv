`timescale 1ns/1ps
`default_nettype none

module tb_apb_regs;
  logic pclk = 0, rst = 1, psel, penable, pwrite;
  logic [7:0] paddr;
  logic [31:0] pwdata, prdata;
  logic pready, pslverr, enable, auto_threshold, hyst_enable, threshold_cpu, clear_hist_sticky;
  logic [1:0] view_mode;
  logic [10:0] thr_hi, thr_lo;
  logic [31:0] crc_gold, auto_cfg;
  logic [5:0] hist_idx;
  logic frame_done_i, fifo_underflow_i, fifo_overflow_i, sync_error_i, hist_valid_i;
  logic [19:0] edge_cnt_i = 20'd17;
  logic [31:0] frame_cnt_i = 32'd9, crc_out_i = 32'h12345678;
  logic [10:0] thr_hi_auto_i = 11'd300, thr_lo_auto_i = 11'd120;
  logic [18:0] hist_data_i = 19'd42;
  always #5 pclk = ~pclk;

  apb_regs dut (.*);

  task automatic write_reg(input logic [7:0] addr, input logic [31:0] data, input logic wanted_error);
    begin
      @(negedge pclk); psel=1; penable=0; pwrite=1; paddr=addr; pwdata=data;
      @(negedge pclk); penable=1; #1;
      if (pslverr !== wanted_error) $fatal(1, "write error mismatch at %02x", addr);
      @(negedge pclk); psel=0; penable=0; pwrite=0;
    end
  endtask

  task automatic read_reg(input logic [7:0] addr, input logic [31:0] wanted, input logic wanted_error);
    begin
      @(negedge pclk); psel=1; penable=0; pwrite=0; paddr=addr;
      @(negedge pclk); penable=1; #1;
      if (pslverr !== wanted_error || (!wanted_error && prdata !== wanted))
        $fatal(1, "read %02x got %08x", addr, prdata);
      @(negedge pclk); psel=0; penable=0;
    end
  endtask

  initial begin
    psel=0; penable=0; pwrite=0; paddr=0; pwdata=0;
    frame_done_i=0; fifo_underflow_i=0; fifo_overflow_i=0; sync_error_i=0; hist_valid_i=0;
    repeat (2) @(posedge pclk); rst=0;
    write_reg(8'h00, 32'h0000003b, 0); // enable, auto, view=2, hyst, CPU threshold source
    if (!enable || !auto_threshold || view_mode != 2 || !hyst_enable || !threshold_cpu) $fatal(1, "CTRL decode failed");
    write_reg(8'h04, 32'd333, 0); write_reg(8'h08, 32'd111, 0);
    read_reg(8'h04, 32'd333, 0); read_reg(8'h08, 32'd111, 0);
    write_reg(8'h10, 0, 1); read_reg(8'h10, 32'd17, 0); read_reg(8'h30, 32'd42, 0);
    @(negedge pclk); frame_done_i=1; fifo_underflow_i=1; hist_valid_i=1;
    @(posedge pclk); #1; frame_done_i=0; fifo_underflow_i=0; hist_valid_i=0;
    read_reg(8'h0c, 32'h00000013, 0);
    write_reg(8'h0c, 32'h00000003, 0); read_reg(8'h0c, 32'h00000010, 0);
    write_reg(8'h3c, 0, 1);
    // Exhaustive address decode, including all misaligned addresses.
    for(integer a=0;a<256;a++) begin
      @(negedge pclk); psel=1; penable=1; pwrite=0; paddr=8'(a); #1;
      if(pslverr !== !((a%4==0) && a<=8'h34)) $fatal(1,"read decode %02x",a);
    end
    @(negedge pclk); psel=0;penable=0;
    // W1C must not lose a newly arriving event in the same access cycle.
    @(negedge pclk); psel=1;penable=0;pwrite=1;paddr=8'h0c;pwdata=32'h3f;
    @(negedge pclk); penable=1; fifo_overflow_i=1;
    @(negedge pclk); psel=0;penable=0;pwrite=0;fifo_overflow_i=0;
    read_reg(8'h0c,32'h4,0);
    $display("PASS tb_apb_regs");
    $finish;
  end
endmodule

`default_nettype wire
