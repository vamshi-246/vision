`timescale 1ns/1ps
// Compares a generated FSMD Sobel design point (hls/sobel_hls.py) against the shipped pipelined sobel.sv,
// which is itself verified against the golden model.  DUT is selected with +define+DUT=<module>.
module tb_sobel_fsmd;
  logic clk = 0, rst = 1, start = 0;
  logic [7:0] w [0:8];
  logic busy, ovalid, rvalid;
  logic [10:0] mag, rmag; logic [1:0] dir, rdir;
  logic [12:0] q [$];
  int n = 0, errors = 0, N = 100000;
  always #5 clk = ~clk;
  `DUT dut(.clk, .rst, .start, .w00(w[0]), .w01(w[1]), .w02(w[2]), .w10(w[3]), .w11(w[4]), .w12(w[5]), .w20(w[6]), .w21(w[7]), .w22(w[8]),
           .busy, .out_valid(ovalid), .magnitude(mag), .direction(dir));
  sobel ref_s(.clk, .in_valid(start && !busy), .w00(w[0]), .w01(w[1]), .w02(w[2]), .w10(w[3]), .w11(w[4]), .w12(w[5]), .w20(w[6]), .w21(w[7]), .w22(w[8]),
              .out_valid(rvalid), .magnitude(rmag), .direction(rdir));
  always @(posedge clk) begin
    if (rvalid) q.push_back({rdir, rmag});
    if (ovalid) begin
      logic [12:0] e; e = q.pop_front();
      if ({dir, mag} !== e) begin errors++; if (errors < 5) $display("MISMATCH dut mag=%0d dir=%0d ref mag=%0d dir=%0d", mag, dir, e[10:0], e[12:11]); end
      n++;
    end
  end
  initial begin
    if ($value$plusargs("N=%d", N)) ;
    repeat (3) @(posedge clk); rst <= 0;
    for (int k = 0; k < N; k++) begin
      @(negedge clk);
      while (busy) @(negedge clk);
      for (int i = 0; i < 9; i++) begin
        case (k % 5)
          0: w[i] = (($urandom % 2) ? 8'd255 : 8'd0);            // extremes (max |G| = 1020)
          default: w[i] = $urandom;
        endcase
      end
      if (k < 9) for (int i = 0; i < 9; i++) w[i] = (k == 0) ? 8'd0 : ((i == k-1) ? 8'd255 : 8'd0);  // single-tap impulses
      start = 1; @(negedge clk); start = 0;
    end
    while (busy || ovalid) @(posedge clk);
    repeat (8) @(posedge clk);
    if (errors == 0 && n == N) $display("PASS sobel FSMD windows=%0d", n);
    else $display("FAIL sobel FSMD errors=%0d compared=%0d", errors, n);
    $finish;
  end
endmodule
