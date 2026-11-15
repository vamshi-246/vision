`timescale 1ns/1ps
module tb_lat #(parameter W=64,H=48);
 logic clk=0,rst=1;always #5 clk=~clk;
 wire[23:0] rgb;wire de,hs,vs,ae,fp;wire[9:0] x,y;wire[19:0] ec;logic[16:0] ia;wire[3:0] so;wire[21:0] tu;wire[18:0] hr,hn;wire hv;
 edge_video #(.W(W),.H(H)) d(.clk,.rst,.switches(4'd0),.rgb,.de,.hsync(hs),.vsync(vs),.x,.y,.alignment_error(ae),.edge_count(ec),.frame_pulse(fp),
  .use_image(1'b0),.img_addr(ia),.img_data(8'd0),.settings_o(so),.ext_thr_en(1'b0),.ext_thr_lo(11'd0),.ext_thr_hi(11'd0),.clear_hist(1'b0),.hist_rd_addr(6'd0),.hist_rd_data(hr),.hist_nnz(hn),.hist_valid(hv),.thr_used(tu));
 integer t=0,t_sde=-1,t_cv=-1,t_sof_core=-1;
 always @(posedge clk) begin t<=t+1;
  if(!rst && t_sde<0 && d.sde && d.sx==3 && d.sy==3) t_sde=t;      // pixel (3,3) enters the core (first pixel of the final valid region)
  if(!rst && t_cv<0 && d.cv) t_cv=t;                                // first classified pixel leaves the core
 end
 initial begin repeat(8)@(negedge clk);rst=0;repeat(3*(W+160)*(H+45))@(posedge clk);
  $display("LAT pixel(3,3) enters at %0d, first class valid at %0d, difference %0d clocks; formula 3*HT+14 = %0d",t_sde,t_cv,t_cv-t_sde,3*(W+160)+14);$finish;end
endmodule
