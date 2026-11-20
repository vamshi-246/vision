`default_nettype none
module zybo_hdmi_top(input wire clk,input wire [3:0] sw,input wire [3:0] btn,
`ifdef BOARD_ZYBO
 output wire hdmi_out_en, // original Zybo only: HDMI source-buffer enable (F17)
`endif
 output wire eth_rst_b,output wire [3:0] led,output wire hdmi_tx_clk_p,hdmi_tx_clk_n,
 output wire [2:0] hdmi_tx_p,hdmi_tx_n
`ifdef LIVE_RX
 // Live build (Zybo Z7 only): HDMI RX J10 from the laptop
 ,input wire hdmi_rx_clk_p,hdmi_rx_clk_n,input wire [2:0] hdmi_rx_p,hdmi_rx_n,
 output wire hdmi_rx_hpd,inout wire hdmi_rx_scl,hdmi_rx_sda
`endif
 );
 assign eth_rst_b=1'b1; // PHY supplies the 125 MHz reference; never hold it reset.
`ifdef BOARD_ZYBO
 assign hdmi_out_en=1'b1; // original Zybo: enable the HDMI J8 source buffer
`endif
 wire pixel_clk,serial_clk,locked;
`ifdef LIVE_RX
 // One clock buffer feeds both the video MMCM and the 200 MHz RX reference PLL (both clock IPs use No_buffer here).
 wire clk_ib,clk_g;
 IBUF clk_ibuf(.I(clk),.O(clk_ib));
 BUFG clk_bufg(.I(clk_ib),.O(clk_g));
 video_clocks clocks(.clk_in1(clk_g),.reset(btn[0]),.clk_out1(pixel_clk),.clk_out2(serial_clk),.locked);
`else
 video_clocks clocks(.clk_in1(clk),.reset(btn[0]),.clk_out1(pixel_clk),.clk_out2(serial_clk),.locked);
`endif
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

 // ---- Live video (LIVE_RX): HDMI RX 800x600@60 -> gray -> 320x240 -> frame store (same buffer as the JTAG upload) ----
 wire live_en,live_valid,live_pop;wire [14:0] live_addr;wire [31:0] live_data;wire rx_ok_s;
`ifdef LIVE_RX
 wire ref_clk,ref_locked;
 // 200 MHz IDELAYCTRL reference: PLL 125 MHz x8 = 1000 MHz VCO / 5
 wire ref_fb,ref_raw;
 PLLE2_BASE #(.CLKIN1_PERIOD(8.0),.CLKFBOUT_MULT(8),.DIVCLK_DIVIDE(1),.CLKOUT0_DIVIDE(5)) refgen(.CLKIN1(clk_g),.CLKFBIN(ref_fb),.CLKFBOUT(ref_fb),
  .CLKOUT0(ref_raw),.CLKOUT1(),.CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.LOCKED(ref_locked),.PWRDWN(1'b0),.RST(1'b0));
 BUFG ref_bufg(.I(ref_raw),.O(ref_clk));
 wire rclk,plocked;wire [23:0] rx_rgb;wire rx_de,rx_hs,rx_vs;wire [26:0] rxdbg;
 wire sda_i,sda_o,sda_t,scl_i,scl_o,scl_t;
 IOBUF sda_buf(.IO(hdmi_rx_sda),.I(sda_o),.O(sda_i),.T(sda_t));
 IOBUF scl_buf(.IO(hdmi_rx_scl),.I(scl_o),.O(scl_i),.T(scl_t));
 assign hdmi_rx_hpd=ref_locked;
 dvi2rgb #(.kEmulateDDC(1'b1),.kRstActiveHigh(1'b1),.kAddBUFG(1'b1),.kClkRange(3),.kEdidFileName("dgl_800x600.data"),.kDebug(1'b0))
 rx(.TMDS_Clk_p(hdmi_rx_clk_p),.TMDS_Clk_n(hdmi_rx_clk_n),.TMDS_Data_p(hdmi_rx_p),.TMDS_Data_n(hdmi_rx_n),
  .RefClk(ref_clk),.aRst(!ref_locked),.aRst_n(1'b1),
  .vid_pData(rx_rgb),.vid_pVDE(rx_de),.vid_pHSync(rx_hs),.vid_pVSync(rx_vs),.PixelClk(rclk),.SerialClk(),.aPixelClkLckd(),.pLocked(plocked),
  .SDA_I(sda_i),.SDA_O(sda_o),.SDA_T(sda_t),.SCL_I(scl_i),.SCL_O(scl_o),.SCL_T(scl_t),.pRst(1'b0),.pRst_n(1'b1),.dbg(rxdbg));
 wire [9:0] lx,ly;wire lde,lhs,lvs,lsof,leol,timing_bad;wire [7:0] lgray;
 // RX-side reset: held until the clock is locked and all three channels are aligned and valid, then ~50 us
 logic [10:0] rhold=0;logic rrst=1;
 always_ff @(posedge rclk) begin
  if(!plocked || !(&rxdbg[2:0]) || !(&rxdbg[5:3]) || timing_bad) begin rhold<=0;rrst<=1;end // timing_bad: restart on the next frame
  else if(rhold!=11'h7FF) rhold<=rhold+1'b1;
  else rrst<=0;
 end
 rx_timing #(.W(800),.H(600),.HT(1056)) front(.clk(rclk),.rst(rrst),.rgb(rx_rgb),.de(rx_de),.hs(rx_hs),.vs(rx_vs),
  .x(lx),.y(ly),.o_de(lde),.o_hs(lhs),.o_vs(lvs),.o_sof(lsof),.o_eol(leol),.gray(lgray),.timing_bad);
 rx_downscale scaler(.rclk,.rrst,.de(lde),.x(lx),.y(ly),.gray(lgray),.wclk(pixel_clk),.pop(live_pop),.valid(live_valid),
  .waddr(live_addr),.wdata(live_data));
 // pixel-clock side: RX healthy (synchronised) and not switched off with BTN2 -> live source shown
 (* ASYNC_REG="TRUE" *) logic [1:0] rx_ok_m=0,btn2_sync=0;
 logic live_off=0;logic [19:0] b2_hold=0;
 always_ff @(posedge pixel_clk) begin
  rx_ok_m<={rx_ok_m[0],!rrst};
  btn2_sync<={btn2_sync[0],btn[2]};
  if(rst) begin live_off<=0;b2_hold<=0;end
  else if(b2_hold!=0) b2_hold<=b2_hold-1'b1;
  else if(btn2_sync[1]) begin live_off<=~live_off;b2_hold<=20'd500000;end
 end
 assign rx_ok_s=rx_ok_m[1];
 assign live_en=rx_ok_s && !live_off;
`else
 assign live_en=1'b0;assign live_valid=1'b0;assign live_addr=15'd0;assign live_data=32'd0;assign rx_ok_s=1'b0;
`endif
 logic [16:0] img_addr;wire [7:0] img_data;wire [31:0] frames;
 wire h_ram_en,h_mb_en,cpu_run,cpu_trap;wire [3:0] h_ram_we,h_mb_we;wire [10:0] h_ram_addr;wire [7:0] h_mb_addr;
 wire [31:0] h_ram_wdata,h_ram_rdata,h_mb_wdata,h_mb_rdata;wire [21:0] thr_used;
 frame_store store(.clk(pixel_clk),.a_en(br_en),.a_we(br_we),.a_addr(br_addr),.a_wdata(br_wdata),
  .a_rdata(br_rdata),.a_img_write(img_write),.b_addr(img_addr),.b_data(img_data),
  .edge_count(count),.flags({22'b0,live_en,cpu_trap,cpu_run,error_flag,loading,show_image,settings}),.frame_count(frames),
  .cpu_trap,.thr_used,.h_ram_en,.h_ram_we,.h_ram_addr,.h_ram_wdata,.h_ram_rdata,.h_mb_en,.h_mb_we,.h_mb_addr,.h_mb_wdata,.h_mb_rdata,.cpu_run,
  .live_en,.live_valid,.live_addr,.live_data,.live_pop);
 video_soc video(.clk(pixel_clk),.rst,.switches(sw),.rgb,.de,.hsync(hs),.vsync(vs),
 .alignment_error(error_flag),.edge_count(count),.frame_pulse,
 .use_image((show_image && !loading) || live_en),.img_addr,.img_data,.cpu_run,
 .h_ram_en,.h_ram_we,.h_ram_addr,.h_ram_wdata,.h_ram_rdata,.h_mb_en,.h_mb_we,.h_mb_addr,.h_mb_wdata,.h_mb_rdata,
 .settings,.thr_used,.cpu_trap,.frames);
 // Digilent's IP packs the input as R,B,G.
 hdmi_tx transmitter(.PixelClk(pixel_clk),.SerialClk(serial_clk),.aRst(tx_rst),
 .vid_pData({rgb[23:16],rgb[7:0],rgb[15:8]}),.vid_pVDE(de),.vid_pHSync(hs),.vid_pVSync(vs),
 .TMDS_Clk_p(hdmi_tx_clk_p),.TMDS_Clk_n(hdmi_tx_clk_n),.TMDS_Data_p(hdmi_tx_p),.TMDS_Data_n(hdmi_tx_n));
 logic heartbeat=0;
 always_ff @(posedge pixel_clk) if(rst) heartbeat<=0;else if(frame_pulse) heartbeat<=~heartbeat;
`ifdef LIVE_RX
 assign led={live_en,heartbeat,de,locked}; // live build: LD3 = live HDMI-in source active
`else
 assign led={error_flag,heartbeat,de,locked};
`endif
endmodule
`default_nettype wire
