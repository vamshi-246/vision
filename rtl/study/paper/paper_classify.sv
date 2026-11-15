// paper_classify.sv -- per-pixel strong/weak/none classification against T_hi / T_lo.
// Encoding matches the project's classify_hist.sv (not present in this sandbox): 00 none, 01 weak, 10 strong.
//   strong : mag >= t_hi      weak : t_lo <= mag < t_hi      none : mag < t_lo
// Streams W*H class codes (one per cycle, class_valid) while re-reading the frame buffer, and keeps
// a running strong-edge count.
module paper_classify #(
  parameter int W  = 64,
  parameter int H  = 64,
  parameter int AW = (W*H > 1) ? $clog2(W*H) : 1
) (
  input  logic          clk,
  input  logic          rst,
  input  logic          start,        // 1-cycle pulse
  output logic          busy,
  output logic          done,         // 1-cycle pulse
  input  logic [7:0]    t_hi,
  input  logic [7:0]    t_lo,
  output logic [AW-1:0] fb_raddr,
  input  logic [7:0]    fb_rdata,
  output logic          class_valid,
  output logic [1:0]    class_out,
  output logic [31:0]   edge_count,   // strong pixels
  output logic [31:0]   weak_count
);
  localparam logic [AW-1:0] LAST = AW'(W*H - 1);

  logic [AW-1:0] addr;
  logic issue, v1;

  assign fb_raddr = addr;

  logic [1:0] cls_c;
  always_comb begin
    if (fb_rdata >= t_hi)      cls_c = 2'b10;
    else if (fb_rdata >= t_lo) cls_c = 2'b01;
    else                       cls_c = 2'b00;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      addr <= '0; issue <= 1'b0; v1 <= 1'b0; busy <= 1'b0; done <= 1'b0;
      class_valid <= 1'b0; class_out <= 2'b00; edge_count <= 32'd0; weak_count <= 32'd0;
    end else begin
      done        <= 1'b0;
      v1          <= 1'b0;
      class_valid <= 1'b0;
      if (start && !busy) begin
        addr <= '0; issue <= 1'b1; busy <= 1'b1;
        edge_count <= 32'd0; weak_count <= 32'd0;
      end else begin
        if (issue) begin
          v1 <= 1'b1;
          if (addr == LAST) issue <= 1'b0;
          else              addr  <= addr + 1'b1;
        end
        if (v1) begin
          class_valid <= 1'b1;
          class_out   <= cls_c;
          if (cls_c == 2'b10) edge_count <= edge_count + 32'd1;
          if (cls_c == 2'b01) weak_count <= weak_count + 32'd1;
        end
        if (busy && !issue && !v1) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end
    end
  end
endmodule
