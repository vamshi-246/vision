// Software version of the whole edge pipeline (Gaussian -> Sobel |Gx|+|Gy| + direction -> NMS -> double threshold),
// bit-exact with model/golden.py, for the hardware/software comparison on the SAME PicoRV32 configuration as the SoC
// (RV32I, no multiplier, no barrel shifter).  The testbench preloads the image at IMG and reads the classes from CLS.
typedef unsigned char u8; typedef unsigned short u16; typedef unsigned int u32;
#define W 32
#define H 24
#define MARK (*(volatile u32 *)0x30000000u)       // 1 = start, 2 = done (testbench counts the clocks in between)
#define IMG ((volatile u8 *)0x00002000u)
#define CLS ((volatile u8 *)0x00002400u)
static u8 sm[H][W], dirn[H][W]; static u16 mag[H][W], nms[H][W];
enum { LO = 64, HI = 192 };

int main(void) {
  MARK = 1;
  for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) { sm[y][x] = 0; mag[y][x] = 0; nms[y][x] = 0; dirn[y][x] = 0; }
  for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++) {          // Gaussian 1-2-1, (sum+8)>>4
    const volatile u8 *p = IMG + (y - 1) * W + (x - 1);
    u32 s = p[0] + (p[1] << 1) + p[2] + (p[W] << 1) + (p[W + 1] << 2) + (p[W + 2] << 1) + p[2 * W] + (p[2 * W + 1] << 1) + p[2 * W + 2];
    sm[y][x] = (u8)((s + 8) >> 4);
  }
  for (int y = 2; y < H - 2; y++) for (int x = 2; x < W - 2; x++) {          // Sobel, CSE form, direction comparators
    int e1 = sm[y+1][x+1] - sm[y-1][x-1], e2 = sm[y-1][x+1] - sm[y+1][x-1];
    int gx = e1 + e2 + ((sm[y][x+1] - sm[y][x-1]) << 1), gy = e1 - e2 + ((sm[y+1][x] - sm[y-1][x]) << 1);
    int ax = gx < 0 ? -gx : gx, ay = gy < 0 ? -gy : gy;
    mag[y][x] = (u16)(ax + ay);
    int c0 = (ay << 5) <= (ax << 3) + (ax << 2) + ax, c2 = (ax << 5) <= (ay << 3) + (ay << 2) + ay;
    dirn[y][x] = c0 ? 0 : c2 ? 2 : (((gx < 0) == (gy < 0)) ? 1 : 3);
  }
  for (int y = 3; y < H - 3; y++) for (int x = 3; x < W - 3; x++) {          // NMS, raster-asymmetric ties
    u16 m = mag[y][x], e, l;
    switch (dirn[y][x]) {
      case 0:  e = mag[y][x-1];   l = mag[y][x+1];   break;
      case 1:  e = mag[y-1][x-1]; l = mag[y+1][x+1]; break;
      case 2:  e = mag[y-1][x];   l = mag[y+1][x];   break;
      default: e = mag[y-1][x+1]; l = mag[y+1][x-1]; break;
    }
    nms[y][x] = (m && m >= e && m > l) ? m : 0;
  }
  for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {                  // double threshold
    u16 n = nms[y][x];
    CLS[y * W + x] = (n && n >= HI) ? 2 : (n && n >= LO) ? 1 : 0;
  }
  MARK = 2;
  for (;;) { }
}
