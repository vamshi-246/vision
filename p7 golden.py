 #!/usr/bin/env python3
"""
P7 golden model - streaming Canny-style edge detector (VL401).

Pipeline (all integer, bit-exact, 1 pixel/clock in hardware):
  RGB -> gray -> Gaussian (3x3 or 5x5) -> Sobel (|Gx|+|Gy|, 4-sector dir)
      -> non-maximum suppression -> double threshold -> (optional) hysteresis

Two models that MUST agree bit-for-bit:
  * frame model  : vectorised NumPy, easy to read, used for reference maps
  * stream model : raster-scan, shift-register line buffers, replicate border
                   handling, reports latency in lines; mirrors the RTL structure

Usage:
  python p7_golden.py selftest
  python p7_golden.py run [image.png|.pgm|.ppm] [--gauss 3|5] [--lo N] [--hi N]
                          [--no-hyst] [--size WxH] [--dump outdir]
"""
import argparse
import os
import sys
import time
from dataclasses import dataclass

import numpy as np

# ----------------------------------------------------------------------------
# Constants (fixed-point design decisions - keep in sync with RTL)
# ----------------------------------------------------------------------------
GAUSS3 = [[1, 2, 1], [2, 4, 2], [1, 2, 1]]            # sum 16  -> >>4
GAUSS5 = [[a * b for b in (1, 4, 6, 4, 1)] for a in (1, 4, 6, 4, 1)]  # sum 256 -> >>8
GAUSS_SHIFT = {3: 4, 5: 8}
GAUSS_K = {3: GAUSS3, 5: GAUSS5}

KX = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
KY = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]

# Direction quantiser without atan: compare |Gy|*256 against |Gx|*K
T22 = 106   # round(tan(22.5 deg)*256) = 106.04
T67 = 618   # round(tan(67.5 deg)*256) = 618.04

# Direction codes (image coords: x right, y down). Neighbours compared in NMS.
#   0: gradient E-W          -> (0,-1),(0,+1)
#   1: gradient down-right   -> (-1,-1),(+1,+1)   (Gx*Gy > 0)
#   2: gradient N-S          -> (-1,0),(+1,0)
#   3: gradient down-left    -> (-1,+1),(+1,-1)   (Gx*Gy < 0)
NB = {0: ((0, -1), (0, 1)), 1: ((-1, -1), (1, 1)),
      2: ((-1, 0), (1, 0)), 3: ((-1, 1), (1, -1))}

MAG_BITS = 11          # max |Gx|+|Gy| = 2040
HIST_BINS = 16         # magnitude histogram: mag >> 7


@dataclass
class Cfg:
    gauss: int = 3          # 3 or 5
    lo: int = 80            # weak threshold  (on 11-bit magnitude scale)
    hi: int = 200           # strong threshold
    hysteresis: bool = True

    def check(self):
        assert self.gauss in (3, 5)
        assert 0 < self.lo <= self.hi < (1 << MAG_BITS)


# ----------------------------------------------------------------------------
# Scalar primitives (shared by the stream model; also used for cross-checks)
# ----------------------------------------------------------------------------
def quant_dir(gx, gy):
    ax, ay = abs(gx), abs(gy)
    if ay * 256 <= ax * T22:
        return 0
    if ay * 256 >= ax * T67:
        return 2
    return 1 if gx * gy > 0 else 3


def gauss_scalar(win, size):
    k, sh = GAUSS_K[size], GAUSS_SHIFT[size]
    acc = 0
    for i in range(size):
        for j in range(size):
            acc += k[i][j] * win[i][j]
    return (acc + (1 << (sh - 1))) >> sh


def sobel_scalar(win):
    gx = gy = 0
    for i in range(3):
        for j in range(3):
            gx += KX[i][j] * win[i][j]
            gy += KY[i][j] * win[i][j]
    return abs(gx) + abs(gy), quant_dir(gx, gy)


def nms_scalar(win, r, c, H, W, lo, hi):
    """win: 3x3 of (mag, dir). Returns (nms_mag, class)."""
    if r == 0 or c == 0 or r == H - 1 or c == W - 1:
        return 0, 0
    m, d = win[1][1]
    (ar, ac), (br, bc) = NB[d]
    a = win[1 + ar][1 + ac][0]
    b = win[1 + br][1 + bc][0]
    nm = m if (m > a and m >= b) else 0
    cls = 2 if nm >= hi else (1 if nm >= lo else 0)
    return nm, cls


def hyst_scalar(win):
    """win: 3x3 of class (0/1/2). Weak kept iff a strong 8-neighbour exists."""
    cls = win[1][1]
    if cls == 2:
        return 1
    if cls == 1:
        for i in range(3):
            for j in range(3):
                if (i, j) != (1, 1) and win[i][j] == 2:
                    return 1
    return 0


# ----------------------------------------------------------------------------
# Frame model (NumPy)
# ----------------------------------------------------------------------------
def rgb2gray(rgb):
    """Y = (77R + 150G + 29B + 128) >> 8   (weights sum to 256)."""
    a = np.asarray(rgb)
    if a.ndim == 2:
        return a.astype(np.uint8)
    r, g, b = (a[..., i].astype(np.int32) for i in range(3))
    return ((77 * r + 150 * g + 29 * b + 128) >> 8).astype(np.uint8)


def conv_frame(img, k, R):
    """Integer correlation with replicate border."""
    H, W = img.shape
    p = np.pad(img.astype(np.int32), R, mode="edge")
    acc = np.zeros((H, W), np.int32)
    for i in range(2 * R + 1):
        for j in range(2 * R + 1):
            if k[i][j]:
                acc += k[i][j] * p[i:i + H, j:j + W]
    return acc


def gaussian_frame(gray, size):
    sh = GAUSS_SHIFT[size]
    acc = conv_frame(gray, GAUSS_K[size], size // 2)
    return ((acc + (1 << (sh - 1))) >> sh).astype(np.uint8)


def sobel_frame(smooth):
    gx = conv_frame(smooth, KX, 1)
    gy = conv_frame(smooth, KY, 1)
    mag = np.abs(gx) + np.abs(gy)
    ax, ay = np.abs(gx), np.abs(gy)
    d = np.where(ay * 256 <= ax * T22, 0,
                 np.where(ay * 256 >= ax * T67, 2,
                          np.where(gx * gy > 0, 1, 3))).astype(np.uint8)
    return gx, gy, mag.astype(np.int32), d


def nms_frame(mag, d):
    H, W = mag.shape
    p = np.pad(mag, 1, mode="constant")
    nb = lambda dr, dc: p[1 + dr:1 + dr + H, 1 + dc:1 + dc + W]
    keep = np.zeros((H, W), bool)
    for dd, ((ar, ac), (br, bc)) in NB.items():
        keep |= (d == dd) & (mag > nb(ar, ac)) & (mag >= nb(br, bc))
    keep[0, :] = keep[-1, :] = False
    keep[:, 0] = keep[:, -1] = False
    return np.where(keep, mag, 0).astype(np.int32)


def threshold_frame(nms, lo, hi):
    return ((nms >= lo).astype(np.uint8) + (nms >= hi).astype(np.uint8))


def hysteresis_frame(cls):
    H, W = cls.shape
    strong = cls == 2
    p = np.pad(strong, 1, mode="constant")
    near = np.zeros((H, W), bool)
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if (dr, dc) != (0, 0):
                near |= p[1 + dr:1 + dr + H, 1 + dc:1 + dc + W]
    return (strong | ((cls == 1) & near)).astype(np.uint8)


def edge_frame(img, cfg=Cfg()):
    """Full frame-based reference. img: HxW gray or HxWx3 RGB uint8."""
    cfg.check()
    gray = rgb2gray(img)
    smooth = gaussian_frame(gray, cfg.gauss)
    gx, gy, mag, d = sobel_frame(smooth)
    nms = nms_frame(mag, d)
    cls = threshold_frame(nms, cfg.lo, cfg.hi)
    edge = hysteresis_frame(cls) if cfg.hysteresis else (cls > 0).astype(np.uint8)
    return dict(gray=gray, smooth=smooth, gx=gx, gy=gy, mag=mag, dir=d,
                nms=nms, cls=cls, edge=edge)


# ----------------------------------------------------------------------------
# Stream model: shift-register line buffer + window generator
# ----------------------------------------------------------------------------
class WindowGen:
    """(2R+1)x(2R+1) window generator over a raster pixel stream.

    Holds the last 2*R*W+2R+1 samples (the line buffers + window registers).
    The window centred on pixel k becomes available when pixel k+R*W+R has
    been pushed -> latency of R lines + R pixels. Borders: replicate (pad=None)
    or a constant pad value.
    """

    def __init__(self, W, H, R, pad=None):
        self.W, self.H, self.R, self.pad = W, H, R, pad
        self.delay = R * W + R
        self.size = 2 * self.delay + 1
        self.ring = [None] * self.size
        self.n = 0

    def push(self, x):
        n = self.n
        self.ring[n % self.size] = x
        self.n += 1
        k = n - self.delay
        if k < 0:
            return None
        return k, self._window(k)

    def _window(self, k):
        W, H, R = self.W, self.H, self.R
        r, c = divmod(k, W)
        win = []
        for dr in range(-R, R + 1):
            row = []
            rr = r + dr
            for dc in range(-R, R + 1):
                cc = c + dc
                if 0 <= rr < H and 0 <= cc < W:
                    row.append(self.ring[(rr * W + cc) % self.size])
                elif self.pad is not None:
                    row.append(self.pad)
                else:
                    q = min(max(rr, 0), H - 1) * W + min(max(cc, 0), W - 1)
                    row.append(self.ring[q % self.size])
            win.append(row)
        return win


class Stage:
    def __init__(self, name, W, H, R, op, pad=None):
        self.name, self.W, self.R = name, W, R
        self.wg = WindowGen(W, H, R, pad)
        self.op = op
        self.out = [None] * (W * H)

    def push(self, x):
        res = self.wg.push(x)
        if res is None:
            return None
        k, win = res
        r, c = divmod(k, self.W)
        y = self.op(win, r, c)
        self.out[k] = y
        return y


class StreamPipeline:
    def __init__(self, W, H, cfg=Cfg()):
        cfg.check()
        self.W, self.H, self.cfg = W, H, cfg
        g = cfg.gauss
        self.stages = [
            Stage("gauss", W, H, g // 2, lambda w, r, c: gauss_scalar(w, g)),
            Stage("sobel", W, H, 1, lambda w, r, c: sobel_scalar(w)),
            Stage("nms_thr", W, H, 1,
                  lambda w, r, c: nms_scalar(w, r, c, H, W, cfg.lo, cfg.hi),
                  pad=(0, 0)),
        ]
        # NMS window holds (mag,dir); stage output is (nms,cls); hysteresis needs cls
        if cfg.hysteresis:
            self.stages.append(
                Stage("hyst", W, H, 1, lambda w, r, c: hyst_scalar(
                    [[v for v in row] for row in w]), pad=0))
        self.latency_pixels = sum(s.wg.delay for s in self.stages)

    @property
    def latency_lines(self):
        return self.latency_pixels / self.W

    def _feed(self, i, x):
        y = self.stages[i].push(x)
        if y is not None and i + 1 < len(self.stages):
            nxt = y
            # hysteresis consumes only the class field
            if self.stages[i + 1].name == "hyst":
                nxt = y[1]
            self._feed(i + 1, nxt)

    def run(self, gray):
        gray = np.asarray(gray)
        assert gray.shape == (self.H, self.W)
        for x in gray.ravel().tolist():
            self._feed(0, int(x))
        for i, st in enumerate(self.stages):          # flush each stage in order
            for _ in range(st.wg.delay):
                self._feed(i, None)
        H, W = self.H, self.W
        sm = np.array(self.stages[0].out, np.uint8).reshape(H, W)
        sb = np.array(self.stages[1].out, np.int32).reshape(H, W, 2)
        nc = np.array(self.stages[2].out, np.int32).reshape(H, W, 2)
        res = dict(smooth=sm, mag=sb[..., 0], dir=sb[..., 1].astype(np.uint8),
                   nms=nc[..., 0], cls=nc[..., 1].astype(np.uint8))
        if self.cfg.hysteresis:
            res["edge"] = np.array(self.stages[3].out, np.uint8).reshape(H, W)
        else:
            res["edge"] = (res["cls"] > 0).astype(np.uint8)
        return res


# ----------------------------------------------------------------------------
# Quality metrics, RV32-visible statistics, test images, I/O
# ----------------------------------------------------------------------------
def fscore(test, ref):
    t, r = test.astype(bool), ref.astype(bool)
    tp = int((t & r).sum())
    p = tp / max(int(t.sum()), 1)
    q = tp / max(int(r.sum()), 1)
    f = 2 * p * q / (p + q) if (p + q) else 0.0
    return dict(precision=p, recall=q, f=f)


def psnr(a, b, peak=255.0):
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    return float("inf") if mse == 0 else 10 * np.log10(peak ** 2 / mse)


def stats(res):
    """What the APB register block exposes to RV32."""
    hist = np.bincount((res["mag"] >> 7).ravel(), minlength=HIST_BINS)[:HIST_BINS]
    return dict(edge_count=int(res["edge"].sum()), mag_hist=hist.tolist())


def make_test_images(W=640, H=480, seed=1):
    """5 deterministic synthetic RGB test images."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:H, 0:W].astype(np.float64)
    s = min(W, H)

    shapes = np.full((H, W), 40.0)
    shapes[int(.15 * H):int(.45 * H), int(.1 * W):int(.4 * W)] = 120
    shapes[((x - .7 * W) ** 2 + (y - .35 * H) ** 2) < (.18 * s) ** 2] = 220
    shapes[(y > .6 * H) & (x - .2 * W > (y - .6 * H) * 1.2) & (x < .5 * W)] = 180

    grad = 255 * x / W * 0.6 + 40
    grad += 120 * (np.abs((x - y * 1.3) % (.2 * W)) < 3)
    grad += 90 * (np.abs(y - .5 * H) < 2)

    ck = max(s // 8, 2)
    checker = np.where(((x // ck) + (y // ck)) % 2 == 0, 60.0, 200.0)

    noisy = shapes + rng.normal(0, 8, (H, W))

    rr = np.hypot(x - W / 2, y - H / 2)
    rings = 127 + 127 * np.tanh(3 * np.sin(rr * (2 * np.pi / max(s / 12, 4))))

    out = []
    for name, g in [("shapes", shapes), ("gradient_lines", grad),
                    ("checker", checker), ("noisy_shapes", noisy),
                    ("rings", rings)]:
        g = np.clip(g, 0, 255)
        rgb = np.stack([g, np.clip(g * .9 + 10, 0, 255),
                        np.clip(g * .8 + 20, 0, 255)], -1)
        out.append((name, np.round(rgb).astype(np.uint8)))
    return out


def load_image(path, size=None):
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB")
        if size:
            im = im.resize(size)
        return np.array(im, np.uint8)
    except ImportError:
        # minimal binary PGM/PPM reader
        with open(path, "rb") as f:
            tok = f.read().split(None, 4)
        magic, w, h = tok[0], int(tok[1]), int(tok[2])
        data = np.frombuffer(tok[4][-(w * h * (3 if magic == b"P6" else 1)):], np.uint8)
        return data.reshape(h, w, 3) if magic == b"P6" else data.reshape(h, w)


def write_pgm(path, a):
    a = np.asarray(a, np.uint8)
    with open(path, "wb") as f:
        f.write(b"P5\n%d %d\n255\n" % (a.shape[1], a.shape[0]))
        f.write(a.tobytes())


def write_mem(path, a, digits):
    with open(path, "w") as f:
        for v in np.asarray(a).ravel():
            f.write("%0*x\n" % (digits, int(v)))


def dump(res, cfg, outdir, tag="img"):
    os.makedirs(outdir, exist_ok=True)
    spec = [("gray", 2), ("smooth", 2), ("mag", 3), ("dir", 1),
            ("nms", 3), ("cls", 1), ("edge", 1)]
    for k, dg in spec:
        write_mem(os.path.join(outdir, f"{tag}_{k}.mem"), res[k], dg)
    write_pgm(os.path.join(outdir, f"{tag}_gray.pgm"), res["gray"])
    write_pgm(os.path.join(outdir, f"{tag}_smooth.pgm"), res["smooth"])
    write_pgm(os.path.join(outdir, f"{tag}_edges.pgm"), res["edge"] * 255)
    with open(os.path.join(outdir, f"{tag}_cfg.txt"), "w") as f:
        f.write(f"gauss={cfg.gauss} lo={cfg.lo} hi={cfg.hi} "
                f"hysteresis={int(cfg.hysteresis)} "
                f"W={res['gray'].shape[1]} H={res['gray'].shape[0]}\n")


# ----------------------------------------------------------------------------
# Self-test
# ----------------------------------------------------------------------------
def _check(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        _check.failed += 1


_check.failed = 0


def selftest():
    print("[1] direction quantiser vs atan2")
    bad = 0
    for gx in range(-40, 41):
        for gy in range(-40, 41):
            if gx == 0 and gy == 0:
                continue
            th = np.degrees(np.arctan2(gy, gx)) % 180.0
            edges = (22.5, 67.5, 112.5, 157.5)
            if any(abs(th - e) < 1.5 for e in edges):
                continue
            exp = 0 if (th < 22.5 or th >= 157.5) else 1 if th < 67.5 else 2 if th < 112.5 else 3
            if quant_dir(gx, gy) != exp:
                bad += 1
    _check(bad == 0, "sector matches atan2 away from boundaries")

    print("[2] vertical step edge -> 1-pixel-thin NMS ridge, dir=0")
    H, W = 24, 32
    img = np.zeros((H, W), np.uint8)
    img[:, W // 2:] = 255
    r = edge_frame(img)
    cnt = (r["nms"][1:-1] > 0).sum(axis=1)
    _check(np.all(cnt == 1), "exactly one NMS pixel per interior row")
    cols = np.nonzero(r["nms"][5])[0]
    _check(len(cols) == 1 and r["dir"][5, cols[0]] == 0, f"ridge at col {cols}, direction 0")
    _check(r["edge"][0].sum() == 0 and r["edge"][:, 0].sum() == 0, "border pixels are never edges")

    print("[3] flat image -> no edges")
    r = edge_frame(np.full((20, 20), 77, np.uint8))
    _check(r["mag"].sum() == 0 and r["edge"].sum() == 0, "zero gradient, zero edges")

    print("[4] stream model == frame model (bit-exact)")
    imgs = make_test_images(80, 60)
    for g in (3, 5):
        for hy in (True, False):
            cfg = Cfg(gauss=g, hysteresis=hy)
            ok = True
            for name, rgb in imgs:
                ref = edge_frame(rgb, cfg)
                sp = StreamPipeline(80, 60, cfg)
                st = sp.run(ref["gray"])
                for k in ("smooth", "mag", "dir", "nms", "cls", "edge"):
                    if not np.array_equal(ref[k], st[k]):
                        ok = False
                        print(f"      mismatch: {name} / {k}")
            _check(ok, f"gauss={g} hysteresis={hy}: 5 images, all stages identical "
                       f"(latency {sp.latency_lines:.2f} lines)")

    print("[5] full 640x480 frame model")
    for name, rgb in make_test_images(640, 480):
        t = time.time()
        r = edge_frame(rgb)
        s = stats(r)
        _check(r["edge"].sum() > 0 and r["mag"].max() < (1 << MAG_BITS),
               f"{name:15s} edges={s['edge_count']:6d}  max|G|={r['mag'].max():4d}  "
               f"({time.time() - t:.2f}s)")

    print("[6] metrics sanity")
    a = np.zeros((8, 8), np.uint8)
    a[2:5, 3] = 1
    _check(abs(fscore(a, a)["f"] - 1) < 1e-12 and psnr(a, a) == float("inf"),
           "F-score=1, PSNR=inf for identical maps")

    print("\nRESULT:", "ALL PASS" if _check.failed == 0 else f"{_check.failed} FAILED")
    return _check.failed == 0


# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selftest")
    r = sub.add_parser("run")
    r.add_argument("image", nargs="?", help="input image (default: synthetic set)")
    r.add_argument("--gauss", type=int, default=3, choices=(3, 5))
    r.add_argument("--lo", type=int, default=80)
    r.add_argument("--hi", type=int, default=200)
    r.add_argument("--no-hyst", action="store_true")
    r.add_argument("--size", default="640x480")
    r.add_argument("--dump", help="output dir for .mem/.pgm vectors")
    r.add_argument("--stream", action="store_true",
                   help="also run stream model and verify equality (slow at 640x480)")
    a = ap.parse_args()

    if a.cmd == "selftest":
        sys.exit(0 if selftest() else 1)

    W, H = (int(v) for v in a.size.lower().split("x"))
    cfg = Cfg(a.gauss, a.lo, a.hi, not a.no_hyst)
    items = ([(os.path.splitext(os.path.basename(a.image))[0],
               load_image(a.image, (W, H)))] if a.image else make_test_images(W, H))
    for name, img in items:
        res = edge_frame(img, cfg)
        s = stats(res)
        h, w = res["gray"].shape
        print(f"{name}: {w}x{h} edges={s['edge_count']} hist={s['mag_hist']}")
        if a.stream:
            sp = StreamPipeline(w, h, cfg)
            st = sp.run(res["gray"])
            same = all(np.array_equal(res[k], st[k]) for k in
                       ("smooth", "mag", "dir", "nms", "cls", "edge"))
            print(f"   stream==frame: {same}   latency {sp.latency_pixels} px "
                  f"= {sp.latency_lines:.2f} lines")
        if a.dump:
            dump(res, cfg, a.dump, name)


if __name__ == "__main__":
    main()
