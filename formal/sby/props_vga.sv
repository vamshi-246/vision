// SymbiYosys harness: the shipped vga_timing at the REAL 640x480 VESA parameters (NuSMV used a reduced instance).
module props_vga (input wire clk, input wire rst);
  wire [9:0] h; wire [9:0] v; wire de, hs, vs, sof, eol, eof;
  vga_timing dut (.clk, .rst, .h_count(h), .v_count(v), .de, .hsync(hs), .vsync(vs), .sof, .eol, .eof);
  reg init = 1'b1;
  always @(posedge clk) begin
    init <= 1'b0;
    if (init) assume (rst);
    if (!init) begin
      assert (h < 10'd800);                                   // horizontal counter bounded
      assert (v < 10'd525);                                   // vertical counter bounded
      assert (!sof || (h == 0 && v == 0));                    // SOF only at the raster origin
      assert (!eol || (de && h == 10'd639));                  // EOL only on the last active column
      assert (!eof || eol);                                   // EOF implies EOL
      assert (!de || (h < 10'd640 && v < 10'd480));           // DE only in the active area
      assert (hs == !(h >= 10'd656 && h < 10'd752));          // HSYNC pulse 96 clocks after 16-clock front porch
      if ($past(!rst) && $past(h) == 10'd799) assert (h == 0); // line wraps
    end
  end
endmodule
