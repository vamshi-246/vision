// linebuf -- two line buffers (RAM, one WT-deep column-addressed RAM per row) + 3x3 window.
// Never a frame buffer: only 2 rows are stored.
//
// Timing (input sample at cycle t, tag (xi,yi)):
//   t   : RAMs read at address xi (rows y-1, y-2 of column xi); din written to row buffer 1
//   t+1 : {row y-2, row y-1, row y} of column xi are in registers
//   t+2 : 3-column window registers valid:  win[r][c], r = row (0=top), c = column (0=oldest, 2=newest)
//         newest column = xi, window CENTRE = (xi-1, yi-1); tag is delayed 2 cycles to match.
// `win` is packed:  win[(r*3+c)*DW +: DW].
module linebuf #(
  parameter int DW = 8,
  parameter int WT = 800,
  parameter int XW = 10
) (
  input  logic              clk,
  input  logic [XW-1:0]     xi,
  input  logic [XW-1:0]     yi,
  input  logic [DW-1:0]     din,
  output logic [9*DW-1:0]   win,
  output logic [XW-1:0]     xo,       // tag of the newest column, aligned with win
  output logic [XW-1:0]     yo
);
  (* ram_style = "block" *) logic [DW-1:0] lb1 [0:WT-1];   // row y-1
  (* ram_style = "block" *) logic [DW-1:0] lb2 [0:WT-1];   // row y-2
  logic [DW-1:0] r1, r2, pd;
  logic [XW-1:0] xd, x1, y1;
  logic [DW-1:0] n0 [0:2];   // newest column {top, mid, bot}
  logic [DW-1:0] n1 [0:2];
  logic [DW-1:0] n2 [0:2];
  logic [XW-1:0] x2, y2;

  // synthesis translate_off
  initial begin
    for (int i = 0; i < WT; i++) begin lb1[i] = '0; lb2[i] = '0; end
    r1 = '0; r2 = '0; pd = '0; xd = '0; x1 = '0; y1 = '0; x2 = '0; y2 = '0;
    for (int i = 0; i < 3; i++) begin n0[i] = '0; n1[i] = '0; n2[i] = '0; end
  end
  // synthesis translate_on

  always_ff @(posedge clk) begin
    // stage 0 -> 1: read old rows, write new ones
    r1 <= lb1[xi];
    r2 <= lb2[xi];
    lb1[xi] <= din;
    pd <= din;
    x1 <= xi; y1 <= yi;
    // row-2 buffer takes the previous cycle's row-1 read (column x1)
    lb2[x1] <= r1;
    // stage 1 -> 2: column registers
    n0[0] <= r2; n0[1] <= r1; n0[2] <= pd;
    for (int i = 0; i < 3; i++) begin n1[i] <= n0[i]; n2[i] <= n1[i]; end
    x2 <= x1; y2 <= y1;
  end

  always_comb begin
    for (int r = 0; r < 3; r++) begin
      win[(r*3+0)*DW +: DW] = n2[r];
      win[(r*3+1)*DW +: DW] = n1[r];
      win[(r*3+2)*DW +: DW] = n0[r];
    end
    xo = x2; yo = y2;
  end
endmodule
