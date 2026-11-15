// demo_core -- everything of the board demo that is NOT a Xilinx primitive or a pin (so it runs under iverilog):
//   source timing -> BRAM test-pattern generator (2 images, 320x240 upsampled x2) -> core_top -> view mux -> RGB/DE/HS/VS
//   display timing (K+SRC_LAT cycles behind the source timing)      APB-master FSM that programs THR_HI / THR_LO
// All logic is in ONE clock domain (the 25.175 MHz pixel clock).  zybo_top.sv adds Clocking Wizard, rgb2dvi and the pins.
module demo_core #(
  parameter int W = 640, H = 480, WT = 800, HT = 525, XW = 10,
  parameter MEMFILE = "hdmi/tpg_images.mem",
  parameter int IMG_BIT = 7,                 // image changes when frame-counter bit IMG_BIT toggles: 2^7 = 128 frames (~2.1 s)
  parameter int HEART_BIT = 4,               // heartbeat LED = frame-counter bit (bit 4 -> toggles every 16 frames, ~0.27 s)
  parameter int THR_HI_A = 192, THR_LO_A = 64,      // sw_thr = 0  (golden-model defaults, used for the quality evaluation)
  parameter int THR_HI_B = 300, THR_LO_B = 120      // sw_thr = 1  (higher / stricter preset, also exercised in tb_top)
) (
  input  logic        clk,                  // pixel clock
  input  logic        rst,                  // synchronous reset, active high (held while the MMCM is not locked)
  input  logic [1:0]  sw_view,              // 0 original, 1 smoothed, 2 edges (strong white / weak grey), 3 edge overlay on original
  input  logic        sw_thr,               // 0 preset A, 1 preset B   (asynchronous switch -> 2-FF synchroniser inside)
  output logic [23:0] vid_data,
  output logic        vid_de, vid_hs, vid_vs,
  output logic [3:0]  led,
  // debug / test taps (unused on the board)
  output logic [7:0]  dbg_gray, dbg_blur, output logic [1:0] dbg_cls,
  output logic [XW-1:0] dbg_x, dbg_y,
  output logic        dbg_img
);
  localparam int LAT_K   = 3 * (WT + 1) + 19;          // core latency (doc/latency.md)
  localparam int SRC_LAT = 2;                          // BRAM read register + output register
  localparam int AHEAD   = LAT_K + SRC_LAT;            // source timing runs this many clocks ahead of the display timing
  localparam int AH_H    = AHEAD % WT;
  localparam int AH_V    = (AHEAD / WT) % HT;

  // ---------------- switch synchronisers
  logic [1:0] sv_q1, sv_q2; logic st_q1, st_q2;
  always_ff @(posedge clk) begin sv_q1 <= sw_view; sv_q2 <= sv_q1; st_q1 <= sw_thr; st_q2 <= st_q1; end

  // ---------------- timing
  logic [9:0] shc, svc, dhc, dvc; logic s_de, s_hs, s_vs, s_fo, d_de, d_hs, d_vs, d_fo;
  vga_timing #(.INIT_H(AH_H), .INIT_V(AH_V)) u_src (.clk, .rst, .hc(shc), .vc(svc), .de(s_de), .hsync(s_hs), .vsync(s_vs), .frame_origin(s_fo));
  vga_timing #(.INIT_H(0),    .INIT_V(0))    u_dsp (.clk, .rst, .hc(dhc), .vc(dvc), .de(d_de), .hsync(d_hs), .vsync(d_vs), .frame_origin(d_fo));

  // ---------------- frame counter (increments on the LAST cell of the source raster so the image index is stable over a frame)
  logic [15:0] fcnt;
  always_ff @(posedge clk) if (rst) fcnt <= '0; else if (shc == WT - 1 && svc == HT - 1) fcnt <= fcnt + 16'd1;
  logic img; assign img = fcnt[IMG_BIT];
  assign dbg_img = img;

  // ---------------- BRAM test-pattern generator: 2 images x 320 x 240 x 8 bit
  (* rom_style = "block" *) logic [7:0] rom [0:2*320*240-1];
  initial $readmemh(MEMFILE, rom);
  logic [17:0] addr; logic [7:0] rd, pix; logic fo_q1, fo_q2;
  logic [8:0] ty, tx;                                    // source row/col in the 320x240 image (x/2, y/2)
  assign ty = svc[9:1]; assign tx = shc[9:1];
  assign addr = (shc < W && svc < H) ? ((img ? 18'd76800 : 18'd0) + 18'(ty) * 18'd320 + 18'(tx)) : 18'd0;
  always_ff @(posedge clk) begin
    rd <= rom[addr]; pix <= rd;
    fo_q1 <= s_fo; fo_q2 <= fo_q1;
  end

  // ---------------- core
  logic psel, penable, pwrite; logic [7:0] paddr; logic [31:0] pwdata, prdata; logic pready, pslverr;
  logic [7:0] o_gray, o_blur; logic [1:0] o_cls; logic [XW-1:0] o_x, o_y; logic o_locked, o_frame_end, o_sync_err;
  core_top #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_core (
    .clk, .rst, .sof(fo_q2), .pix_data(pix), .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
    .o_gray, .o_blur, .o_cls, .o_x, .o_y, .o_locked, .o_frame_end, .o_sync_err);
  assign dbg_gray = o_gray; assign dbg_blur = o_blur; assign dbg_cls = o_cls; assign dbg_x = o_x; assign dbg_y = o_y;

  // ---------------- top-level controller: APB master that programs the threshold preset (see doc/top_controller.md)
  typedef enum logic [2:0] {C_RESET, C_HI_SETUP, C_HI_ACCESS, C_LO_SETUP, C_LO_ACCESS, C_IDLE} cstate_t;
  cstate_t cst; logic applied; logic [3:0] rcnt;
  always_ff @(posedge clk) begin
    if (rst) begin cst <= C_RESET; rcnt <= '0; applied <= 1'b0; psel <= 0; penable <= 0; pwrite <= 0; paddr <= 0; pwdata <= 0; end
    else begin
      case (cst)
        C_RESET:     begin rcnt <= rcnt + 4'd1; if (rcnt == 4'd15) begin applied <= st_q2; cst <= C_HI_SETUP; end end
        C_HI_SETUP:  begin psel <= 1; penable <= 0; pwrite <= 1; paddr <= 8'h04; pwdata <= 32'(applied ? THR_HI_B : THR_HI_A); cst <= C_HI_ACCESS; end
        C_HI_ACCESS: begin penable <= 1; cst <= C_LO_SETUP; end                  // PREADY is 1: transfer completes this cycle
        C_LO_SETUP:  begin psel <= 1; penable <= 0; paddr <= 8'h08; pwdata <= 32'(applied ? THR_LO_B : THR_LO_A); cst <= C_LO_ACCESS; end
        C_LO_ACCESS: begin penable <= 1; cst <= C_IDLE; end
        C_IDLE:      begin psel <= 0; penable <= 0; pwrite <= 0; if (st_q2 != applied) begin applied <= st_q2; cst <= C_HI_SETUP; end end
        default:     cst <= C_RESET;
      endcase
    end
  end

  // ---------------- view mux + output register (display timing is already K+SRC_LAT behind the source)
  logic [23:0] vpix; logic [5:0] g6; logic [23:0] dimg_px;
  assign g6 = o_gray[7:2];
  assign dimg_px = {2'b00, g6, 2'b00, g6, 2'b00, g6};
  always_comb begin
    vpix = 24'd0;
    case (sv_q2)
      2'd0: vpix = {3{o_gray}};
      2'd1: vpix = {3{o_blur}};
      2'd2: vpix = (o_cls == 2'd2) ? 24'hFFFFFF : (o_cls == 2'd1) ? 24'h606060 : 24'h000000;
      2'd3: vpix = (o_cls == 2'd2) ? 24'hFF2020 : dimg_px;  // dimmed original + red strong edges
    endcase
    if (!d_de) vpix = 24'd0;
  end
  always_ff @(posedge clk) begin
    if (rst) begin vid_data <= 24'd0; vid_de <= 1'b0; vid_hs <= 1'b1; vid_vs <= 1'b1; end   // idle levels: blank, syncs inactive (active low)
    else begin vid_data <= vpix; vid_de <= d_de; vid_hs <= d_hs; vid_vs <= d_vs; end
  end

  // ---------------- LEDs: [0] heartbeat, [1] core locked, [2] sync error seen (lit = bad), [3] preset B applied
  logic err_seen;
  always_ff @(posedge clk) if (rst) err_seen <= 1'b0; else if (o_sync_err) err_seen <= 1'b1;
  assign led = {applied, err_seen, o_locked, fcnt[HEART_BIT]};
endmodule
