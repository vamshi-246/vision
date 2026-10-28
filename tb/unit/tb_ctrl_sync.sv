`timescale 1ns/1ps
`default_nettype none

module tb_ctrl_sync;
  logic clk = 0, rst = 1, in_valid, in_sof, in_eol;
  logic [1:0] x, y;
  logic out_valid, out_sof, out_eol, out_eof, sync_error;
  always #5 clk = ~clk;
  ctrl_sync #(.IMG_W(4), .IMG_H(3), .X_W(2), .Y_W(2)) dut (.*);

  initial begin : stimulus
    int i;
    in_valid=0; in_sof=0; in_eol=0;
    repeat (2) @(posedge clk); rst=0;
    for (i=0; i<12; i++) begin
      @(negedge clk); in_valid=1; in_sof=(i==0); in_eol=((i%4)==3);
      #1;
      if (x != (i%4) || y != (i/4)) $fatal(1, "coordinate mismatch %0d: %0d,%0d", i,x,y);
      if (out_eof != (i==11)) $fatal(1, "eof mismatch");
      @(posedge clk);
    end
    @(negedge clk); in_valid=0;
    if (sync_error) $fatal(1, "unexpected sync error");
    // An EOL on x=0 must be latched as an error.
    @(negedge clk); in_valid=1; in_eol=1; in_sof=0;
    @(posedge clk); #1;
    if (!sync_error) $fatal(1, "missing malformed-EOL error");
    $display("PASS tb_ctrl_sync");
    $finish;
  end
endmodule

`default_nettype wire
