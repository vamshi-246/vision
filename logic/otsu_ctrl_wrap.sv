`default_nettype none
// Encoding-study wrapper: registered inputs/outputs around otsu_ctrl, state not exported (so the FSM can be re-encoded).
module otsu_ctrl_wrap #(
  parameter logic [2:0] C_INIT = 3'd0, C_ARM = 3'd1, C_COLLECT = 3'd2, C_SWEEP = 3'd3, C_CLEAR = 3'd4, C_PEND = 3'd5
) (input wire clk, input wire rst, input wire [6:0] in, output logic [6:0] out);
  logic [6:0] ri; logic [2:0] st; logic [6:0] o;
  otsu_ctrl #(.C_INIT(C_INIT), .C_ARM(C_ARM), .C_COLLECT(C_COLLECT), .C_SWEEP(C_SWEEP), .C_CLEAR(C_CLEAR), .C_PEND(C_PEND)) u (
    .clk, .rst, .en(ri[0]), .sof(ri[1]), .eof(ri[2]), .odone(ri[3]), .cdone(ri[4]), .px(ri[5]), .ovr(ri[6]),
    .state(st), .count_en(o[0]), .clr_both(o[1]), .clr_one(o[2]), .swap(o[3]), .apply(o[4]), .init_done(o[5]), .sweeping(o[6]));
  always_ff @(posedge clk) begin ri <= in; out <= o; end
endmodule
`default_nettype wire
