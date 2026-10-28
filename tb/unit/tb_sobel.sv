`timescale 1ns/1ps
`default_nettype none

module tb_sobel;
  logic clk = 1'b0;
  logic in_valid;
  logic [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
  logic out_valid;
  logic [10:0] magnitude;
  logic [1:0] direction;

  always #5 clk = ~clk;
  sobel dut (.*);

  task automatic drive_window(input logic [7:0] a00, a01, a02, a10, a11, a12, a20, a21, a22);
    begin
      @(negedge clk);
      {w00,w01,w02,w10,w11,w12,w20,w21,w22} = {a00,a01,a02,a10,a11,a12,a20,a21,a22};
      in_valid = 1'b1;
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic expect_result(input logic [10:0] expected_mag, input logic [1:0] expected_dir);
    begin
      // Three registered stages from accepted input to valid output.
      repeat (3) @(posedge clk);
      #1;
      if (!out_valid || magnitude != expected_mag || direction != expected_dir)
        $fatal(1, "Sobel got valid=%0b mag=%0d dir=%0b; expected %0d/%0b",
               out_valid, magnitude, direction, expected_mag, expected_dir);
      @(posedge clk); #1;
      if (out_valid) $fatal(1, "Sobel valid pipeline did not drain");
    end
  endtask

  initial begin
    in_valid = 0;
    {w00,w01,w02,w10,w11,w12,w20,w21,w22} = '0;
    // Dark-to-bright step across x: Gx=1020, Gy=0, horizontal direction.
    drive_window(0,0,255, 0,0,255, 0,0,255);
    expect_result(11'd1020, 2'b00);
    // Dark-to-bright step across y: Gx=0, Gy=1020, vertical direction.
    drive_window(0,0,0, 0,0,0, 255,255,255);
    expect_result(11'd1020, 2'b10);
    $display("PASS tb_sobel");
    $finish;
  end
endmodule

`default_nettype wire
