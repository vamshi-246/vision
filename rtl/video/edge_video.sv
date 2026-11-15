`default_nettype none
// Full raster alignment for the fixed-rate, no-backpressure 3x3 core.
module edge_video #(parameter integer W=640,H=480)(
 input wire clk,rst,input wire [3:0] switches,
 output logic [23:0] rgb,output wire de,hsync,vsync,
 output wire [9:0] x,output wire [9:0] y,
 output logic alignment_error,output logic [19:0] edge_count,
 output logic frame_pulse,
 // Optional stored-image source: (W/2)x(H/2) pixels, nearest-neighbour 2x upscaled.
 // img_addr is registered; img_data must follow it with one cycle of latency.
 input wire use_image,output logic [16:0] img_addr,input wire [7:0] img_data,
 output wire [3:0] settings_o,
 // Thresholds from the APB register bank (CPU) instead of the switch presets; sampled at SOF like the switches.
 input wire ext_thr_en,input wire [10:0] ext_thr_lo,ext_thr_hi,
 // Histogram / statistics path to the APB registers.
 input wire clear_hist,input wire [5:0] hist_rd_addr,output wire [18:0] hist_rd_data,hist_nnz,output wire hist_valid,
 output wire [21:0] thr_used);
 localparam integer HT=W+160;
 localparam integer DELAY=3*HT+14;
 localparam integer GDELAY=HT+3;
 wire [9:0] sx0,sy0;wire sde0,shs0,svs0,sof0,eol0,eof0;
 vga_timing #(.H_ACTIVE(W),.V_ACTIVE(H)) timing(.clk,.rst,.h_count(sx0),.v_count(sy0),
  .de(sde0),.hsync(shs0),.vsync(svs0),.sof(sof0),.eol(eol0),.eof(eof0));
 // Image fetch takes two cycles (registered address + memory read).  Every raster
 // signal that reaches the core is delayed by the same two cycles, so the
 // pattern and image sources share one fixed pixel/raster relationship.
 always_ff @(posedge clk) img_addr<=17'(sy0[9:1]*(W/2))+17'(sx0[9:1]);
 logic [9:0] sx1,sy1,sx,sy;logic sde1,shs1,svs1,sof1,eol1,sde,shs,svs,sof,eol;
 always_ff @(posedge clk) begin
  {sx1,sy1,sde1,shs1,svs1,sof1,eol1}<={sx0,sy0,sde0,shs0,svs0,sof0,eol0};
  {sx,sy,sde,shs,svs,sof,eol}<={sx1,sy1,sde1,shs1,svs1,sof1,eol1};
 end
 logic use_img_q=0;
 always_ff @(posedge clk) if(rst) use_img_q<=0; else if(sof) use_img_q<=use_image;
 wire [7:0] pattern = ((sx>=W/4 && sx<W*3/4 && sy>=H/4 && sy<H*3/4) ? 8'd220 :
                    ((sx[5]^sy[5]) ? 8'd160 : 8'd24));
 wire [7:0] gray = use_img_q ? (sde ? img_data : 8'd0) : pattern;
 (* ASYNC_REG="TRUE" *) logic [3:0] sw_meta,sw_sync;
 logic [3:0] settings=4'b0010;
 logic [10:0] lo,hi;
 assign settings_o=settings;
 always_ff @(posedge clk) begin
  sw_meta<=switches;sw_sync<=sw_meta;
  if(rst) settings<=4'b0010;
  else if(sof) settings<=sw_sync;
 end
 logic ext_q=0;logic [10:0] ext_lo_q=0,ext_hi_q=0;
 always_ff @(posedge clk) if(rst) ext_q<=0; else if(sof) begin ext_q<=ext_thr_en;ext_lo_q<=ext_thr_lo;ext_hi_q<=ext_thr_hi;end
 always_comb begin
  case(settings[3:2])
   0: begin lo=80;hi=200;end
   1: begin lo=20;hi=40;end
   2: begin lo=160;hi=400;end
   3: begin lo=300;hi=700;end
  endcase
  if(ext_q) begin lo=ext_lo_q;hi=ext_hi_q;end
 end
 assign thr_used={hi,lo};
 wire cv,cs,ce,gv;wire [7:0] gray_smooth;wire [1:0] cls;
 wire [$clog2(W)-1:0] cx;wire [$clog2(H)-1:0] cy;
 edge_pipeline #(.IMG_W(W),.IMG_H(H)) core(.clk,.rst,.in_valid(sde),.in_sof(sof),.in_eol(eol),
 .in_gray(gray),.thr_lo(lo),.thr_hi(hi),.clear_hist(clear_hist),.hist_rd_addr(hist_rd_addr),
 .hist_rd_data(hist_rd_data),.hist_nnz(hist_nnz),.hist_valid(hist_valid),.out_valid(cv),.out_sof(cs),.out_eol(ce),
 .out_x(cx),.out_y(cy),.out_cls(cls),.smooth_valid(gv),.smooth_gray(gray_smooth));
 wire [31:0] delayed;
 video_delay #(.WIDTH(32),.DEPTH(DELAY+1)) raster_delay(.clk,
 .din({sde,shs,svs,1'b0,sx,sy,gray}),.dout(delayed));
 wire [8:0] delayed_smooth;
 video_delay #(.WIDTH(9),.DEPTH(DELAY-GDELAY)) smooth_delay(.clk,
 .din({gv,gray_smooth}),.dout(delayed_smooth));
 localparam integer WARM=DELAY+3; // +2: image-fetch pipeline in front of the raster delay
 logic [$clog2(WARM+1)-1:0] warm=0;
 always_ff @(posedge clk) begin
  if(rst) warm<=0;
  else if(warm<WARM) warm<=warm+1'b1;
 end
 wire ready_video=(warm>=WARM);
 assign {x,y}=delayed[27:8];
 assign de=ready_video && delayed[31];
 assign hsync=ready_video ? delayed[30]:1'b1;
 assign vsync=ready_video ? delayed[29]:1'b1;
 wire interior=de && x>=3 && x<W-3 && y>=3 && y<H-3;
 wire smooth_interior=de && x>=1 && x<W-1 && y>=1 && y<H-1;
 logic [19:0] running_edges;
 always_ff @(posedge clk) begin
  if(rst) begin alignment_error<=0;running_edges<=0;edge_count<=0;frame_pulse<=0;end
  else begin
   frame_pulse<=0;
   if(ready_video && ((cv != interior) || (cv && (cx!=x || cy!=y)))) alignment_error<=1;
   if(cv) begin
    if(cs) running_edges<=20'(cls==2);
    else running_edges<=running_edges+20'(cls==2);
    if(ce && cy==H-4) begin
     edge_count<=running_edges+20'(cls==2);frame_pulse<=1;
    end
   end
  end
 end
 always_comb begin
  rgb=0;
  if(de) case(settings[1:0])
   0: rgb={3{delayed[7:0]}};
   1: if(smooth_interior && delayed_smooth[8]) rgb={3{delayed_smooth[7:0]}};
   2: if(interior && cv && cls==2) rgb=24'hffffff;
   3: if(interior && cv) case(cls)
        1:rgb=24'hffbf00;
        2:rgb=24'hffffff;
        default:rgb=0;
       endcase
  endcase
 end
endmodule
`default_nettype wire
