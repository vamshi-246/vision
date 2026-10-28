`timescale 1ns/1ps
`default_nettype none

module tb_linebuf;
  logic clk = 1'b0;
  logic rst = 1'b1;
  logic pix_valid, pix_sof, pix_eol;
  logic [7:0] pix_data;
  logic win_valid;
  logic [1:0] win_x, win_y;
  logic [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
  int windows_seen;

  always #5 clk = ~clk;

  linebuf #(.IMG_W(4), .IMG_H(4), .X_W(2), .Y_W(2)) dut (.*);

  task automatic check_window;
    logic [7:0] base;
    begin
      if (win_valid) begin
        base = (win_y - 1) * 16 + (win_x - 1);
        if ({w00,w01,w02,w10,w11,w12,w20,w21,w22} !==
            {base,base+8'd1,base+8'd2,
             base+8'd16,base+8'd17,base+8'd18,
             base+8'd32,base+8'd33,base+8'd34})
          $fatal(1, "bad window at (%0d,%0d)", win_x, win_y);
        windows_seen++;
      end
    end
  endtask

  initial begin : stimulus
    int x, y;
    pix_valid = 0; pix_sof = 0; pix_eol = 0; pix_data = 0;
    repeat (2) @(posedge clk);
    rst = 0;
    for (y = 0; y < 4; y++) begin
      for (x = 0; x < 4; x++) begin
        @(negedge clk);
        pix_valid = 1;
        pix_sof = (x == 0 && y == 0);
        pix_eol = (x == 3);
        pix_data = y * 16 + x;
        @(posedge clk); #1;
        check_window();
      end
    end
    @(negedge clk); pix_valid = 0; pix_sof = 0; pix_eol = 0;
    if (windows_seen != 4) $fatal(1, "saw %0d windows, expected 4", windows_seen);
    $display("PASS tb_linebuf");
    $finish;
  end
endmodule

`default_nettype wire
