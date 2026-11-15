// Drive the paper RTL with the NMS magnitudes of one 640x480 frame and dump its real class stream.
`timescale 1ns/1ps
module tb_paper_quality #(parameter string IMG = "x");
  localparam int W = 640, H = 480;
  logic clk = 0, rst = 1; always #5 clk = ~clk;
  logic start = 0, busy, done, pix_ready, pix_valid = 0, class_valid; logic [10:0] pix_data = 0;
  logic [7:0] t_hi, t_lo; logic [1:0] class_out; logic [31:0] edge_count;
  paper_top #(.W(W), .H(H), .IN_W(11)) dut (.clk, .rst, .start, .busy, .done, .pix_ready, .pix_valid, .pix_data, .t_hi, .t_lo, .class_valid, .class_out, .edge_count);
  reg [10:0] mem [0:W*H-1];
  integer fd, ncls = 0;
  always @(posedge clk) if (class_valid) begin $fwrite(fd, "%0d\n", class_out); ncls++; end
  initial begin
    fd = $fopen({"build/paper/", IMG, "_cls.txt"}, "w");
    $readmemh({"build/paper/", IMG, "_nms.hex"}, mem);
    repeat (4) @(posedge clk); rst <= 0; repeat (2) @(posedge clk);
    start <= 1; @(posedge clk); start <= 0;
    wait (pix_ready);
    for (int i = 0; i < W*H; i++) begin pix_valid <= 1; pix_data <= mem[i]; @(posedge clk); while (!pix_ready) @(posedge clk); end
    pix_valid <= 0;
    wait (done);
    @(posedge clk); $fclose(fd);
    $display("PAPER_RESULT %s t_hi=%0d t_lo=%0d edge_count=%0d class_px=%0d", IMG, t_hi, t_lo, edge_count, ncls);
    $finish;
  end
  initial begin #(600_000_000); $display("PAPER_RESULT %s TIMEOUT", IMG); $finish; end
endmodule
