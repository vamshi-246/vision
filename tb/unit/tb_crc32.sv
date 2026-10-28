`timescale 1ns/1ps
`default_nettype none

module tb_crc32;
  logic clk = 0, rst = 1, frame_start, pixel_valid, pixel_edge, frame_end;
  logic [31:0] crc_out;
  logic crc_valid;
  always #5 clk = ~clk;
  crc32 dut (.*);

  task automatic send(input logic is_edge, input logic first, input logic last);
    begin
      @(negedge clk); pixel_valid = 1; pixel_edge = is_edge; frame_start = first; frame_end = last;
      @(posedge clk); #1;
    end
  endtask

  initial begin
    frame_start = 0; pixel_valid = 0; pixel_edge = 0; frame_end = 0;
    repeat (2) @(posedge clk); rst = 0;
    // zlib.crc32(bytes([0x00,0xff,0x00,0xff])) = 0xb2de047c.
    send(0, 1, 0); send(1, 0, 0); send(0, 0, 0); send(1, 0, 1);
    if (!crc_valid || crc_out != 32'hb2de047c) $fatal(1, "CRC got %08x", crc_out);
    $display("PASS tb_crc32");
    $finish;
  end
endmodule

`default_nettype wire
