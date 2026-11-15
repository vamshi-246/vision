`default_nettype none
module zybo_hdmi_top(input wire clk,input wire [3:0] sw,input wire [3:0] btn,
`ifdef BOARD_ZYBO
 output wire hdmi_out_en, // original Zybo only: HDMI source-buffer enable (F17)
`endif
 output wire eth_rst_b,output wire [3:0] led,output wire hdmi_tx_clk_p,hdmi_tx_clk_n,
 output wire [2:0] hdmi_tx_p,hdmi_tx_n);
 assign eth_rst_b=1'b1; // PHY supplies the 125 MHz reference; never hold it reset.
`ifdef BOARD_ZYBO
 assign hdmi_out_en=1'b1; // original Zybo: enable the HDMI J8 source buffer
`endif
 wire pixel_clk,serial_clk,locked;
 video_clocks clocks(.clk_in1(clk),.reset(btn[0]),.clk_out1(pixel_clk),.clk_out2(serial_clk),.locked);
 (* ASYNC_REG="TRUE" *) logic [127:0] reset_sync='1;
 always_ff @(posedge pixel_clk or negedge locked) begin
  if(!locked) reset_sync<='1;
  else reset_sync<={reset_sync[126:0],1'b0};
 end
 // Let the MMCM startup settle before releasing raster state. The core reset
 // is synchronous; the transmitter's async reset is released on the opposite
 // pixel-clock edge to satisfy its reset-bridge recovery/removal requirement.
 logic rst=1,tx_rst=1;
 always_ff @(negedge pixel_clk) rst<=reset_sync[127];
 always_ff @(negedge pixel_clk or negedge locked) begin
  if(!locked) tx_rst<=1;
  else tx_rst<=rst;
 end
 wire [23:0] rgb;wire de,hs,vs,error_flag,frame_pulse;
 wire [19:0] count;wire [3:0] settings;
 // ---- Image upload path: JTAG-to-AXI master -> AXI BRAM controller -> frame store ----
 wire [0:0] awid,arid;wire [31:0] awaddr,araddr,wdata,rdata;wire [7:0] awlen,arlen;wire [2:0] awsize,arsize,awprot,arprot;
 wire [1:0] awburst,arburst,bresp,rresp;wire awlock,arlock,awvalid,awready,wlast,wvalid,wready,bvalid,bready,arvalid,arready,rlast,rvalid,rready;
 wire [3:0] awcache,arcache,awqos,arqos,wstrb;
 jtag_axi_master jtag(.aclk(pixel_clk),.aresetn(locked),
  .m_axi_awid(awid),.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
  .m_axi_awlock(awlock),.m_axi_awcache(awcache),.m_axi_awprot(awprot),.m_axi_awqos(awqos),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),
  .m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),.m_axi_bid(1'b0),.m_axi_bresp(bresp),
  .m_axi_bvalid(bvalid),.m_axi_bready(bready),.m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),
  .m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arlock(arlock),.m_axi_arcache(arcache),
  .m_axi_arprot(arprot),.m_axi_arqos(arqos),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
  .m_axi_rid(1'b0),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));
 wire br_en;wire [3:0] br_we;wire [16:0] br_addr;wire [31:0] br_wdata,br_rdata;
 frame_axi_ctrl axi_mem(.s_axi_aclk(pixel_clk),.s_axi_aresetn(locked),
  .s_axi_awaddr(awaddr[16:0]),.s_axi_awlen(awlen),.s_axi_awsize(awsize),.s_axi_awburst(awburst),
  .s_axi_awlock(awlock),.s_axi_awcache(awcache),.s_axi_awprot(awprot),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
  .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
  .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
  .s_axi_araddr(araddr[16:0]),.s_axi_arlen(arlen),.s_axi_arsize(arsize),.s_axi_arburst(arburst),
  .s_axi_arlock(arlock),.s_axi_arcache(arcache),.s_axi_arprot(arprot),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
  .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
  .bram_rst_a(),.bram_clk_a(),.bram_en_a(br_en),.bram_we_a(br_we),.bram_addr_a(br_addr),
  .bram_wrdata_a(br_wdata),.bram_rddata_a(br_rdata));
 // ---- Source control: an upload blanks the stored image, then switches to it; BTN1 toggles ----
 (* ASYNC_REG="TRUE" *) logic [1:0] btn1_sync=0;
 logic show_image=0,loading=0,loading_q=0;logic [19:0] btn_hold=0;logic [21:0] load_cnt=0;
 wire img_write;
 always_ff @(posedge pixel_clk) begin
  btn1_sync<={btn1_sync[0],btn[1]};
  loading_q<=loading;
  if(rst) begin show_image<=0;btn_hold<=0;end
  else begin
   if(btn_hold!=0) btn_hold<=btn_hold-1'b1;
   else if(btn1_sync[1]) begin show_image<=~show_image;btn_hold<=20'd500000;end // ~20 ms debounce
   if(loading_q && !loading) show_image<=1; // upload finished: show it
  end
  if(img_write) load_cnt<=22'd2500000; // ~0.1 s quiet time ends the upload
  else if(load_cnt!=0) load_cnt<=load_cnt-1'b1;
  loading<=(load_cnt!=0);
 end
 logic [16:0] img_addr;wire [7:0] img_data;wire [31:0] frames;
 wire h_ram_en,h_mb_en,cpu_run,cpu_trap;wire [3:0] h_ram_we,h_mb_we;wire [10:0] h_ram_addr;wire [7:0] h_mb_addr;
 wire [31:0] h_ram_wdata,h_ram_rdata,h_mb_wdata,h_mb_rdata;wire [21:0] thr_used;
 frame_store store(.clk(pixel_clk),.a_en(br_en),.a_we(br_we),.a_addr(br_addr),.a_wdata(br_wdata),
  .a_rdata(br_rdata),.a_img_write(img_write),.b_addr(img_addr),.b_data(img_data),
  .edge_count(count),.flags({23'b0,cpu_trap,cpu_run,error_flag,loading,show_image,settings}),.frame_count(frames),
  .cpu_trap,.thr_used,.h_ram_en,.h_ram_we,.h_ram_addr,.h_ram_wdata,.h_ram_rdata,.h_mb_en,.h_mb_we,.h_mb_addr,.h_mb_wdata,.h_mb_rdata,.cpu_run);
 video_soc video(.clk(pixel_clk),.rst,.switches(sw),.rgb,.de,.hsync(hs),.vsync(vs),
 .alignment_error(error_flag),.edge_count(count),.frame_pulse,
 .use_image(show_image && !loading),.img_addr,.img_data,.cpu_run,
 .h_ram_en,.h_ram_we,.h_ram_addr,.h_ram_wdata,.h_ram_rdata,.h_mb_en,.h_mb_we,.h_mb_addr,.h_mb_wdata,.h_mb_rdata,
 .settings,.thr_used,.cpu_trap,.frames);
 // Digilent's IP packs the input as R,B,G.
 hdmi_tx transmitter(.PixelClk(pixel_clk),.SerialClk(serial_clk),.aRst(tx_rst),
 .vid_pData({rgb[23:16],rgb[7:0],rgb[15:8]}),.vid_pVDE(de),.vid_pHSync(hs),.vid_pVSync(vs),
 .TMDS_Clk_p(hdmi_tx_clk_p),.TMDS_Clk_n(hdmi_tx_clk_n),.TMDS_Data_p(hdmi_tx_p),.TMDS_Data_n(hdmi_tx_n));
 logic heartbeat=0;
 always_ff @(posedge pixel_clk) if(rst) heartbeat<=0;else if(frame_pulse) heartbeat<=~heartbeat;
 assign led={error_flag,heartbeat,de,locked};
endmodule
`default_nettype wire
