// P7 control firmware for the PicoRV32 subsystem (RV32I, no libc).
//  * enables APB threshold control (CTRL.threshold_cpu),
//  * once per frame reads EDGE_CNT and all 64 histogram bins through the APB register bank,
//  * sets the edge thresholds from the switches (SW3:2 preset) or from a host override in the mailbox,
//  * publishes everything in the mailbox, which the laptop reads over JTAG (scripts/fpga_image.py).
// Mailbox word map (byte address = 0x2000_0000 + 4*index):
//   0 magic  1 seq (even = stable, odd = being written)  2 frames published  3 FRAME_CNT  4 EDGE_CNT
//   5/6 thr_lo/thr_hi that were in effect for the counted frame  7 switches  8/9 thr_lo/hi written for the next frame
//   10 override-active flag  16..79 histogram bins
//   128 host override enable  129 override lo  130 override hi   (host -> CPU)
typedef unsigned int u32;
#define APB(off) (*(volatile u32 *)(0x10000000u + (off)))
#define MB       ((volatile u32 *)0x20000000u)
#define GPIO     (*(volatile u32 *)0x30000000u)
enum { CTRL = 0x00, THR_HI = 0x04, THR_LO = 0x08, EDGE_CNT = 0x10, FRAME_CNT = 0x14, HIST_IDX = 0x2c, HIST_DATA = 0x30 };
#define MAGIC 0x5037C0DEu

static const u32 PRESET_LO[4] = {80, 20, 160, 300};
static const u32 PRESET_HI[4] = {200, 40, 400, 700};

int main(void) {
  u32 seq = 0, published = 0, hist[64];
  APB(CTRL) = 0x21;                                  // EN=1, threshold_cpu=1
  u32 sw = GPIO & 0xf;
  u32 cur_lo = PRESET_LO[(sw >> 2) & 3], cur_hi = PRESET_HI[(sw >> 2) & 3];
  APB(THR_LO) = cur_lo; APB(THR_HI) = cur_hi;
  u32 used_lo = cur_lo, used_hi = cur_hi;
  MB[0] = MAGIC; MB[1] = 0;
  u32 last = APB(FRAME_CNT);
  for (;;) {
    u32 f = APB(FRAME_CNT);
    if (f == last) continue;
    last = f;
    for (volatile int d = 0; d < 200; d++) { }       // let the histogram snapshot settle (a few cycles after the pulse)
    u32 edges = APB(EDGE_CNT);
    for (u32 i = 0; i < 64; i++) { APB(HIST_IDX) = i; hist[i] = APB(HIST_DATA); }
    sw = GPIO & 0xf;
    u32 ov = MB[128] & 1;
    u32 nlo = ov ? MB[129] : PRESET_LO[(sw >> 2) & 3];
    u32 nhi = ov ? MB[130] : PRESET_HI[(sw >> 2) & 3];
    MB[1] = seq + 1;                                 // odd: update in progress
    MB[2] = ++published; MB[3] = f; MB[4] = edges;
    MB[5] = used_lo; MB[6] = used_hi; MB[7] = sw;
    MB[8] = nlo; MB[9] = nhi; MB[10] = ov;
    for (u32 i = 0; i < 64; i++) MB[16 + i] = hist[i];
    seq += 2; MB[1] = seq;                           // even: stable
    APB(CTRL) = 0x21;                                // re-assert every frame: BTN0 resets the APB bank, which would drop threshold_cpu
    APB(THR_LO) = nlo; APB(THR_HI) = nhi;            // take effect at the next frame start
    used_lo = nlo; used_hi = nhi;
  }
}
