`timescale 1ns/1ps
`default_nettype none
module tb_crc_stress;
  logic clk=0,rst=1,frame_start=0,pixel_valid=0,pixel_edge=0,frame_end=0;
  wire [31:0] crc_out;
  wire crc_valid;
  reg [7:0] words[0:400000];
  reg [31:0] expected[0:255];
  integer count,frames,dummy,i,frame=0;
  string base;
  always #5 clk=~clk;
  crc32 dut(.*);
  initial begin
    if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE required");
    if(!$value$plusargs("COUNT=%d",count)) $fatal(1,"COUNT required");
    if(!$value$plusargs("FRAMES=%d",frames)) $fatal(1,"FRAMES required");
    $readmemh({base,"/crc_pixels.hex"},words,0,count-1);
    $readmemh({base,"/crc_expected.hex"},expected,0,frames-1);
    repeat(3) @(negedge clk); rst=0;
    for(i=0;i<count;i++) begin
      if(i%13==0) begin
        @(negedge clk);pixel_valid=0;frame_start=0;frame_end=0;
        @(posedge clk);#1;if(crc_valid) $fatal(1,"CRC valid during gap");
      end
      @(negedge clk);pixel_valid=1;pixel_edge=words[i][0];frame_start=words[i][1];frame_end=words[i][2];
      @(posedge clk);#1;
      if(crc_valid !== frame_end) $fatal(1,"CRC marker");
      if(frame_end) begin
        if(crc_out !== expected[frame]) $fatal(1,"CRC frame=%0d got=%08x exp=%08x",frame,crc_out,expected[frame]);
        frame++;
      end
    end
    if(frame!=frames) $fatal(1,"CRC frame count");
    $display("PASS CRC: %0d frames, %0d bytes, zlib oracle, bubbles and adjacent frame boundaries",frames,count);$finish;
  end
endmodule
`default_nettype wire
