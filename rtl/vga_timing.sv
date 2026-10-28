`default_nettype none

module vga_timing #(
  parameter int unsigned H_ACTIVE = 640,
  parameter int unsigned H_FP     = 16,
  parameter int unsigned H_SYNC   = 96,
  parameter int unsigned H_BP     = 48,
  parameter int unsigned V_ACTIVE = 480,
  parameter int unsigned V_FP     = 10,
  parameter int unsigned V_SYNC   = 2,
  parameter int unsigned V_BP     = 33,
  parameter int unsigned H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP,
  parameter int unsigned V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP,
  parameter int unsigned HC_W     = $clog2(H_TOTAL),
  parameter int unsigned VC_W     = $clog2(V_TOTAL)
) (
  input  logic            clk,
  input  logic            rst,
  output logic [HC_W-1:0] h_count,
  output logic [VC_W-1:0] v_count,
  output logic            de,
  output logic            hsync,
  output logic            vsync,
  output logic            sof,
  output logic            eol,
  output logic            eof
);

  always_ff @(posedge clk) begin
    if (rst) begin
      h_count <= '0;
      v_count <= '0;
    end else if (h_count == H_TOTAL - 1) begin
      h_count <= '0;
      if (v_count == V_TOTAL - 1) begin
        v_count <= '0;
      end else begin
        v_count <= v_count + 1'b1;
      end
    end else begin
      h_count <= h_count + 1'b1;
    end
  end

  always_comb begin
    de    = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    sof   = de && (h_count == '0) && (v_count == '0);
    eol   = de && (h_count == H_ACTIVE - 1);
    eof   = eol && (v_count == V_ACTIVE - 1);
    hsync = !((h_count >= H_ACTIVE + H_FP) &&
              (h_count <  H_ACTIVE + H_FP + H_SYNC));
    vsync = !((v_count >= V_ACTIVE + V_FP) &&
              (v_count <  V_ACTIVE + V_FP + V_SYNC));
  end

endmodule

`default_nettype wire

