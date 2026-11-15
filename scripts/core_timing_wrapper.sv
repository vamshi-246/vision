`default_nettype none
// Timing experiment only: register every core boundary in the same clock
// domain. This is not a board top or a replacement for a video/bus wrapper.
module core_timing_wrapper(
  input wire clk,rst,in_valid,in_sof,in_eol,clear_hist,
  input wire [7:0] in_gray,
  input wire [10:0] thr_lo,thr_hi,
  input wire [5:0] hist_rd_addr,
  output logic [18:0] hist_rd_data,hist_nnz,
  output logic hist_valid,out_valid,out_sof,out_eol,
  output logic [9:0] out_x,
  output logic [8:0] out_y,
  output logic [1:0] out_cls
);
  logic rst_q,in_valid_q,in_sof_q,in_eol_q,clear_hist_q;
  logic [7:0] in_gray_q;
  logic [10:0] thr_lo_q,thr_hi_q;
  logic [5:0] hist_rd_addr_q;
  wire [18:0] hist_rd_data_d,hist_nnz_d;
  wire hist_valid_d,out_valid_d,out_sof_d,out_eol_d;
  wire [9:0] out_x_d;
  wire [8:0] out_y_d;
  wire [1:0] out_cls_d;
  always_ff @(posedge clk) begin
    {rst_q,in_valid_q,in_sof_q,in_eol_q,clear_hist_q,in_gray_q,thr_lo_q,thr_hi_q,hist_rd_addr_q}
      <= {rst,in_valid,in_sof,in_eol,clear_hist,in_gray,thr_lo,thr_hi,hist_rd_addr};
    {hist_rd_data,hist_nnz,hist_valid,out_valid,out_sof,out_eol,out_x,out_y,out_cls}
      <= {hist_rd_data_d,hist_nnz_d,hist_valid_d,out_valid_d,out_sof_d,out_eol_d,out_x_d,out_y_d,out_cls_d};
  end
  edge_pipeline core(
    .clk,.rst(rst_q),.in_valid(in_valid_q),.in_sof(in_sof_q),.in_eol(in_eol_q),
    .in_gray(in_gray_q),.thr_lo(thr_lo_q),.thr_hi(thr_hi_q),.clear_hist(clear_hist_q),
    .hist_rd_addr(hist_rd_addr_q),.hist_rd_data(hist_rd_data_d),.hist_nnz(hist_nnz_d),
    .hist_valid(hist_valid_d),.out_valid(out_valid_d),.out_sof(out_sof_d),.out_eol(out_eol_d),
    .out_x(out_x_d),.out_y(out_y_d),.out_cls(out_cls_d)
  );
endmodule
`default_nettype wire
