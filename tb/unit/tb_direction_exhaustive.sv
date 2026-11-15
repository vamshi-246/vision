`timescale 1ns/1ps
`default_nettype none
// Exhaustively tests the direction comparator's entire Sobel-range domain.
// Pipeline arithmetic is tested separately by tb_arithmetic_stress.
module tb_direction_exhaustive;
  logic clk=0,in_valid=0;
  wire out_valid;
  wire [10:0] magnitude;
  wire [1:0] direction;
  logic [10:0] ax_drive=0,ay_drive=0;
  logic sx_drive=0,sy_drive=0;
  integer ax,ay,signs,expected,checked=0;
  always #5 clk=~clk;
  sobel dut(.clk,.in_valid,.w00(8'd0),.w01(8'd0),.w02(8'd0),.w10(8'd0),.w11(8'd0),.w12(8'd0),.w20(8'd0),.w21(8'd0),.w22(8'd0),.out_valid,.magnitude,.direction);
  initial begin
    force dut.ax_2=ax_drive;force dut.ay_2=ay_drive;
    force dut.sx_2=sx_drive;force dut.sy_2=sy_drive;
    for(ax=0;ax<=1020;ax++) for(ay=0;ay<=1020;ay++) for(signs=0;signs<4;signs++) begin
      @(negedge clk); ax_drive=11'(ax);ay_drive=11'(ay);sx_drive=signs[0];sy_drive=signs[1];
      expected=(ay*32<=ax*13)?0:((ax*32<=ay*13)?2:((signs[0]==signs[1])?1:3));
      @(posedge clk);#1;
      if(direction !== 2'(expected)) $fatal(1,"direction ax=%0d ay=%0d signs=%0d got=%0d exp=%0d",ax,ay,signs,direction,expected);
      checked++;
    end
    release dut.ax_2;release dut.ay_2;release dut.sx_2;release dut.sy_2;
    $display("PASS direction exhaustive: %0d magnitude/sign combinations, axes, zero and exact 13/32 ties",checked);$finish;
  end
endmodule
`default_nettype wire
