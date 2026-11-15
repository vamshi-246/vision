// delay_ram -- pure delay of exactly DELAY cycles (DELAY >= 2) built from a circular RAM of depth DELAY-1
// (write address == read address, read-before-write, registered output).  Used to align the three display views.
module delay_ram #(parameter int DW = 8, parameter int DELAY = 16) (
  input  logic          clk,
  input  logic [DW-1:0] din,
  output logic [DW-1:0] dout
);
  localparam int DEPTH = DELAY - 1;
  localparam int AW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  (* ram_style = "block" *) logic [DW-1:0] mem [0:DEPTH-1];
  logic [AW-1:0] a;
  // synthesis translate_off
  initial begin for (int i = 0; i < DEPTH; i++) mem[i] = '0; a = '0; dout = '0; end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    dout   <= mem[a];
    mem[a] <= din;
    a      <= (a == AW'(DEPTH - 1)) ? '0 : a + 1'b1;
  end
endmodule
