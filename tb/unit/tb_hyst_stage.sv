`timescale 1ns/1ps
`default_nettype none

module tb_hyst_stage;
  logic clk = 0, rst = 1, in_valid, in_sof, in_eol;
  logic [1:0] in_cls;
  logic out_valid, out_sof, out_eol, out_edge;
  logic [2:0] out_x, out_y;
  int edges;
  always #5 clk = ~clk;

  hyst_stage #(.IMG_W(5), .IMG_H(5), .X_W(3), .Y_W(3)) dut (.*);

  initial begin : stimulus
    int x, y;
    in_valid = 0; in_sof = 0; in_eol = 0; in_cls = 0;
    repeat (2) @(posedge clk); rst = 0;
    for (y = 0; y < 5; y++) begin
      for (x = 0; x < 5; x++) begin
        @(negedge clk);
        in_valid = 1; in_sof = (x == 0 && y == 0); in_eol = (x == 4);
        // Strong (1,1) should promote the diagonal weak centre (2,2).
        in_cls = (x == 1 && y == 1) ? 2'b10 : ((x == 2 && y == 2) ? 2'b01 : 2'b00);
        @(posedge clk); #1;
        if (out_valid) begin
          if ((out_x == 1 && out_y == 1) || (out_x == 2 && out_y == 2)) begin
            if (!out_edge) $fatal(1, "required edge absent at %0d,%0d", out_x, out_y);
            edges++;
          end else if (out_edge) begin
            $fatal(1, "spurious edge at %0d,%0d", out_x, out_y);
          end
        end
      end
    end
    if (edges != 2) $fatal(1, "edge count=%0d expected 2", edges);
    $display("PASS tb_hyst_stage");
    $finish;
  end
endmodule

`default_nettype wire
