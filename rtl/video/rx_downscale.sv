`default_nettype none
// Live input, RX clock domain: 800x600 grayscale raster (from rx_timing) -> 320x240 by 2.5:1 nearest-neighbour decimation
// (keep columns/rows n with n mod 5 in {0,2}; destination index = (n/5)*2 + (n mod 5 == 2)) -> 32-bit words of 4 pixels -> async FIFO
// -> frame-store word writes in the pixel-clock domain. Byte layout matches the JTAG upload: pixel (x,y) at byte y*320+x, little-endian.
module rx_downscale #(parameter integer DW=320)(
 input wire rclk,rrst,input wire de,input wire [9:0] x,y,input wire [7:0] gray,
 input wire wclk,input wire pop,output wire valid,output wire [14:0] waddr,output wire [31:0] wdata);
 // stage 1: register inputs
 logic de1=0;logic [9:0] x1=0,y1=0;logic [7:0] g1=0;
 // stage 2: decimation decision
 logic [2:0] xm,ym;logic [8:0] xd;logic [7:0] yd;
 always_comb begin
  xm=3'(x1%5);ym=3'(y1%5);
  xd=9'((x1/5)*2+(xm==2));yd=8'((y1/5)*2+(ym==2));
 end
 wire keep=de1 && (xm==0||xm==2) && (ym==0||ym==2);
 logic [23:0] acc=0;logic push=0;logic [46:0] din=0;
 wire [16:0] pidx=17'(yd)*DW+17'(xd);
 always_ff @(posedge rclk) begin
  de1<=de;x1<=x;y1<=y;g1<=gray;
  push<=0;
  if(rrst) acc<=0;
  else if(keep) begin
   case(xd[1:0])
    2'd0: acc[7:0]<=g1;
    2'd1: acc[15:8]<=g1;
    2'd2: acc[23:16]<=g1;
    2'd3: begin push<=1;din<={pidx[16:2],g1,acc};end
   endcase
  end
 end
 wire [46:0] dout;wire empty;
 xpm_fifo_async #(.FIFO_MEMORY_TYPE("distributed"),.FIFO_WRITE_DEPTH(64),.WRITE_DATA_WIDTH(47),.READ_DATA_WIDTH(47),
  .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.CDC_SYNC_STAGES(2),.USE_ADV_FEATURES("0000"))
 fifo(.rst(rrst),.wr_clk(rclk),.wr_en(push),.din(din),.full(),.wr_rst_busy(),.rd_clk(wclk),.rd_en(pop&&!empty),.dout(dout),.empty(empty),
  .rd_rst_busy(),.sleep(1'b0),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.overflow(),.underflow(),.prog_full(),.prog_empty(),
  .almost_full(),.almost_empty(),.data_valid(),.dbiterr(),.sbiterr(),.wr_ack(),.wr_data_count(),.rd_data_count());
 assign valid=!empty;assign waddr=dout[46:32];assign wdata=dout[31:0];
endmodule
`default_nettype wire
