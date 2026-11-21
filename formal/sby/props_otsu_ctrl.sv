// SymbiYosys harness for the adaptive-threshold controller (rtl/otsu_ctrl.sv); inputs are unconstrained.
module props_otsu_ctrl (input wire clk, input wire rst, input wire en, sof, eof, odone, cdone, px, ovr);
  wire [2:0] state; wire count_en, clr_both, clr_one, swap, apply, init_done, sweeping;
  otsu_ctrl dut (.clk, .rst, .en, .sof, .eof, .odone, .cdone, .px, .ovr, .state, .count_en, .clr_both, .clr_one, .swap, .apply, .init_done, .sweeping);
  reg init = 1'b1;
  always @(posedge clk) begin
    init <= 1'b0;
    if (init) assume (rst);
    if (!init) begin
      assert (state <= 3'd5);                                       // only the six legal codes
      assert (!(clr_both && count_en));                             // never count into a bank being cleared
      assert (!(clr_both && clr_one));
      assert (!apply || (state == 3'd5 && eof) || (state == 3'd4 && !px));   // thresholds change only at a frame boundary
      assert (!(swap && clr_one));
      if ($past(swap) && $past(!rst)) assert (state == 3'd3);       // a bank swap always starts a sweep
      if ($past(state) == 3'd4 && $past(!cdone) && $past(!rst)) assert (state == 3'd4);   // CLEAR holds until the pass ends
    end
  end
endmodule
