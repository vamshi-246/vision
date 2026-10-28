`timescale 1ns/1ps
`default_nettype none

module tb_dirnms;
  logic [10:0] magnitude;
  logic [10:0] mag_nw, mag_n, mag_ne, mag_w, mag_e, mag_sw, mag_s, mag_se;
  logic [1:0] direction;
  logic [10:0] nms_mag;
  logic keep;

  dirnms dut (.*);

  task automatic check(input logic [10:0] m, e, l, input logic [1:0] d, input logic wanted);
    begin
      magnitude = m;
      mag_nw = e; mag_n = e; mag_ne = e; mag_w = e;
      mag_e = l; mag_sw = l; mag_s = l; mag_se = l;
      direction = d; #1;
      if (keep !== wanted)
        $fatal(1, "NMS m/e/l/dir=%0d/%0d/%0b got %0b expected %0b", m,e,l,d,keep,wanted);
    end
  endtask

  initial begin
    // Appendix-A asymmetric plateau policy: earlier tie survives, later tie does not.
    check(11'd8, 11'd8, 11'd7, 2'b00, 1'b1);
    check(11'd8, 11'd7, 11'd8, 2'b00, 1'b0);
    check(11'd0, 11'd0, 11'd0, 2'b01, 1'b0);
    check(11'd9, 11'd1, 11'd2, 2'b10, 1'b1);
    $display("PASS tb_dirnms");
    $finish;
  end
endmodule

`default_nettype wire
