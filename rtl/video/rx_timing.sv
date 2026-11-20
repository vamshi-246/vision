`default_nettype none
// Live-video front end: turns the recovered RX video (RGB + DE/HS/VS on the RX pixel clock) into what edge_video expects from its own
// vga_timing: x/y raster counters, sof/eol, and an 8-bit grayscale pixel aligned with them.
// Gray = (77R+150G+29B)>>8, the same formula as model/golden.py. The raster is derived from DE only (sync polarity independent):
//   x counts active pixels; a line that starts more than 2 lines after the previous active pixel opens a new frame (y=0).
// All outputs are registered once, so gray/de/x/y/sof/eol/hs/vs stay aligned (1 cycle after the input).
// timing_bad (sticky until rst) = line period != HT, frame height != H, or a line longer than W: input is not 800x600@60 (1056 x 628).
module rx_timing #(parameter integer W=800,H=600,HT=1056)(
 input wire clk,rst,
 input wire [23:0] rgb,input wire de,hs,vs,
 output logic [9:0] x=0,y=0,output logic o_de=0,o_hs=0,o_vs=0,o_sof=0,o_eol=0,
 output logic [7:0] gray=0,output logic timing_bad=0);
 logic de_q=0;logic [9:0] xc=0,yc=0;logic [11:0] gap=0;logic [11:0] since=12'hFFF;logic started=0,armed=0;
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 wire line_start=de && !de_q;
 wire new_frame=line_start && gap>12'd1600;
 wire run=armed||new_frame; // after reset, ignore the partial frame in progress until a real frame boundary (vertical blank) is seen
 wire [9:0] x_cur=line_start?10'd0:xc;
 wire [9:0] y_cur=new_frame?10'd0:(line_start?yc+1'b1:yc);
 wire [16:0] gsum=17'd77*r+17'd150*g+17'd29*b;
 always_ff @(posedge clk) begin
  de_q<=de;o_hs<=hs;o_vs<=vs;
  gray<=gsum[15:8];
  if(rst) begin xc<=0;yc<=0;gap<=0;since<=12'hFFF;started<=0;armed<=0;timing_bad<=0;o_sof<=0;o_eol<=0;x<=0;y<=0;end
  else begin
   // cycles since the last active pixel / since the last line start (both saturating)
   if(de) gap<=0; else if(gap!=12'hFFF) gap<=gap+1'b1;
   if(line_start) since<=1; else if(since!=12'hFFF) since<=since+1'b1;
   if(line_start) begin
    yc<=y_cur;
    if(run && since!=12'hFFF && !new_frame && since!=HT) timing_bad<=1;     // line period
    if(new_frame && started && yc!=H-1) timing_bad<=1;                // frame height
    if(new_frame) begin started<=1;armed<=1;end
   end
   xc<=x_cur+1'b1;
   if(de && run && x_cur>=W) timing_bad<=1;                                  // line too long
   o_de<=de&&run;
   x<=(de&&run)?x_cur:10'd0;y<=(de&&run)?y_cur:10'd0;
   o_sof<=de && new_frame;
   o_eol<=de && run && x_cur==W-1;
  end
 end
endmodule
`default_nettype wire
