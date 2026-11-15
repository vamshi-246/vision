#!/usr/bin/env python3
"""Laptop-side tool for the Zybo edge-detector demo (everything goes over the JTAG cable).

    fpga_image.py send PHOTO [--fit crop|pad]   convert + upload a photo, (re)load and start the RV32 firmware, verify
    fpga_image.py convert PHOTO                 conversion + expected-result previews only (no hardware)
    fpga_image.py status                        read board registers + the CPU mailbox and verify against the model
    fpga_image.py threshold LO HI | auto        host override of the CPU's edge thresholds (auto = back to the switches)

Pipeline: EXIF-rotate -> 4:3 crop (or pad) -> 320x240 -> grayscale with the model's formula ((77R+150G+29B)>>8) -> raw bytes ->
JTAG-to-AXI burst writes into the FPGA frame buffer -> full read-back compare -> RV32 firmware is loaded and started ->
the firmware's mailbox (edge count, thresholds in effect, 64-bin histogram) is compared with model/golden.py.
AXI byte map: see rtl/video/frame_store.sv.
"""
from __future__ import annotations
import argparse, os, subprocess, sys, time, zlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.golden import Config, edge_frame, histogram64  # noqa: E402

W, H = 320, 240
PRESETS = [(80, 200), (20, 40), (160, 400), (300, 700)]
VIVADO = os.environ.get("VIVADO", "/tools/Xilinx/Vivado/2024.2/bin/vivado")
OUT = ROOT / "build" / "upload"
IMG, CPURAM, MBOX, REGS = 0x0, 0x14000, 0x16000, 0x18000
MAGIC_REG, MAGIC_MB = 0x5A420001, 0x5037C0DE
FW_BIN = ROOT / "fw/build/fw.bin"
LAST = OUT / "last_gray.npy"


# --------------------------------------------------------------------------- image conversion
def load_photo(path: Path) -> Image.Image:
    if path.suffix.lower() in (".heic", ".heif"):
        try:
            import pillow_heif  # type: ignore
            pillow_heif.register_heif_opener()
        except ImportError:
            sys.exit("HEIC photo: install pillow-heif (pip install pillow-heif) or export it as JPEG/PNG first.")
    img = ImageOps.exif_transpose(Image.open(path))      # phone photos are often stored rotated
    if img.mode in ("RGBA", "LA", "P"):
        bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img = Image.alpha_composite(bg, img.convert("RGBA"))
    return img.convert("RGB")


def to_gray_320x240(img: Image.Image, fit: str) -> np.ndarray:
    img = ImageOps.fit(img, (W, H), Image.LANCZOS, centering=(0.5, 0.5)) if fit == "crop" else \
        ImageOps.pad(img, (W, H), Image.LANCZOS, color=(128, 128, 128))
    a = np.asarray(img).astype(np.int32)
    return ((77 * a[..., 0] + 150 * a[..., 1] + 29 * a[..., 2]) >> 8).astype(np.uint8)   # == model/golden.py


def model(gray: np.ndarray, lo: int, hi: int) -> dict:
    full = np.repeat(np.repeat(gray, 2, axis=0), 2, axis=1)
    r = edge_frame(full, Config(thr_lo=lo, thr_hi=hi))
    hist, _ = histogram64(r["nms"])
    return {"cls": r["cls"], "strong": int((r["cls"] == 2).sum()), "hist": [int(v) for v in hist]}


def save_previews(name: str, gray: np.ndarray) -> Path:
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    Image.fromarray(gray).save(d / "gray_320x240.png")
    tiles = [np.where(model(gray, *PRESETS[p])["cls"] == 2, 255, 0).astype(np.uint8) for p in range(4)]
    top = np.hstack([np.repeat(np.repeat(gray, 2, 0), 2, 1), tiles[0]])
    Image.fromarray(top).save(d / "expected_original_and_preset0_edges.png")
    Image.fromarray(np.hstack(tiles)).resize((1280, 240)).save(d / "expected_edges_all_presets.png")
    return d


# --------------------------------------------------------------------------- JTAG-to-AXI session
TCL = r'''
set ops_file $::env(P7_OPS)
set out_file $::env(P7_RESULT)
open_hw_manager
connect_hw_server
open_hw_target
catch {set_property PARAM.FREQUENCY $::env(P7_TCK) [current_hw_target]}
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
refresh_hw_device $dev
set axis [get_hw_axis]
if {[llength $axis] == 0} {error "No JTAG-AXI core found: program zybo_edge_hdmi.bit first and keep the board powered"}
set axi [lindex $axis 0]
set fo [open $out_file w]
set rev 0
proc wr_words {axi addr words} {
  global rev
  for {set i 0} {$i < [llength $words]} {incr i 256} {
    set chunk [lrange $words $i [expr {$i + 255}]]
    if {$rev} {set chunk [lreverse $chunk]}
    create_hw_axi_txn -force wr $axi -type write -address [format %08x [expr {$addr + $i * 4}]] -len [llength $chunk] -data [join $chunk ""]
    run_hw_axi wr
  }
}
proc rd_words {axi addr n} {
  global rev
  set res {}
  for {set i 0} {$i < $n} {incr i 256} {
    set m [expr {min(256, $n - $i)}]
    create_hw_axi_txn -force rd $axi -type read -address [format %08x [expr {$addr + $i * 4}]] -len $m
    run_hw_axi rd
    set d [string tolower [string map {_ {}} [get_property DATA [get_hw_axi_txns rd]]]]
    set ws {}
    for {set k 0} {$k < [string length $d]} {incr k 8} {lappend ws [string range $d $k [expr {$k + 7}]]}
    if {$rev} {set ws [lreverse $ws]}
    set res [concat $res $ws]
  }
  return $res
}
# Determine burst word order empirically using unused mailbox words (index 200..203).
create_hw_axi_txn -force probe $axi -type write -address [format %08x [expr {0x16000 + 800}]] -len 4 -data 44444444_33333333_22222222_11111111
run_hw_axi probe
create_hw_axi_txn -force pr $axi -type read -address [format %08x [expr {0x16000 + 800}]] -len 1
run_hw_axi pr
set rev [expr {[string match *11111111 [string tolower [string map {_ {}} [get_property DATA [get_hw_axi_txns pr]]]]] ? 1 : 0}]
puts $fo "ORDER_REV $rev"
set f [open $ops_file r]
set t0 [clock milliseconds]
while {[gets $f line] >= 0} {
  set t [split [string trim $line] " "]
  switch [lindex $t 0] {
    W { wr_words $axi [expr [lindex $t 1]] [lrange $t 2 end] }
    R { puts $fo "R [lindex $t 3] [join [rd_words $axi [expr [lindex $t 1]] [lindex $t 2]] " "]" }
    S { after [lindex $t 1] }
  }
}
close $f
puts $fo "TOTAL_MS [expr {[clock milliseconds] - $t0}]"
close $fo
close_hw_target
close_hw_manager
'''


class Ops:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def write(self, addr: int, words: list[int]) -> None:
        self.lines.append(f"W {addr} " + " ".join(f"{w & 0xFFFFFFFF:08x}" for w in words))

    def read(self, addr: int, n: int, tag: str) -> None:
        self.lines.append(f"R {addr} {n} {tag}")

    def sleep(self, ms: int) -> None:
        self.lines.append(f"S {ms}")


def bytes_to_words(data: bytes) -> list[int]:
    data = data + b"\0" * (-len(data) % 4)
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]


def run_session(ops: Ops, tag: str, tck: int) -> dict:
    OUT.mkdir(parents=True, exist_ok=True)
    of, rf, tf = OUT / f"{tag}_ops.txt", OUT / f"{tag}_result.txt", OUT / f"{tag}.tcl"
    of.write_text("\n".join(ops.lines) + "\n")
    tf.write_text(TCL)
    rf.unlink(missing_ok=True)
    env = dict(os.environ, P7_OPS=str(of), P7_RESULT=str(rf), P7_TCK=str(tck))
    p = subprocess.run([VIVADO, "-mode", "batch", "-source", str(tf), "-log", str(OUT / f"{tag}_vivado.log"),
                        "-journal", str(OUT / f"{tag}_vivado.jou"), "-notrace"], env=env, cwd=ROOT, capture_output=True, text=True)
    if not rf.exists() or "TOTAL_MS" not in rf.read_text():
        sys.exit(f"Vivado hardware step failed (see {OUT / (tag + '_vivado.log')}):\n" + "\n".join(
            l for l in (p.stdout + p.stderr).splitlines() if "ERROR" in l)[:2000])
    res: dict = {"reads": {}}
    for line in rf.read_text().splitlines():
        t = line.split()
        if t[0] == "ORDER_REV": res["rev"] = int(t[1])
        elif t[0] == "TOTAL_MS": res["ms"] = int(t[1])
        elif t[0] == "R": res["reads"][t[1]] = [int(x, 16) for x in t[2:]]
    return res


# --------------------------------------------------------------------------- verification
def check_board(res: dict, gray: np.ndarray | None) -> bool:
    regs, m2, seq_after = res["reads"]["regs"], res["reads"]["mb"], res["reads"]["seq"][0]
    m1 = m2
    magic, edges_hw, flags, frames = regs[0:4]
    run, trap, thr = regs[4] & 1, regs[5] & 1, regs[6]
    print(f"Board: magic {'ok' if magic == MAGIC_REG else hex(magic)}  frames {frames}  settings {flags & 0xF}  show_image {flags >> 4 & 1}"
          f"  loading {flags >> 5 & 1}  alignment_error {flags >> 6 & 1}  cpu_run {run}  cpu_trap {trap}")
    ok = magic == MAGIC_REG and not (flags >> 5 & 1) and not (flags >> 6 & 1) and not trap
    if m1[0] != MAGIC_MB:
        print("CPU mailbox: no firmware magic -> the RV32 firmware is not running"); return False
    # Seqlock: the firmware keeps the sequence word even while a record is stable. If it is unchanged and even after the burst
    # read, no update happened during the read, so the record is a consistent snapshot.
    stable = m2[1] == seq_after and m2[1] % 2 == 0
    print(f"CPU (PicoRV32): published {m2[2]} frames, hardware FRAME_CNT {m2[3]}, mailbox record "
          f"{'stable' if stable else 'changing'}; thresholds in effect {m2[5]}/{m2[6]}, switches {m2[7]:04b}, override {m2[10]}")
    print(f"  CPU-read EDGE_CNT {m2[4]}; hardware edge register {edges_hw}; thresholds register lo={thr & 0x7FF} hi={thr >> 11 & 0x7FF}")
    ok &= m2[2] > 2 and m2[0] == MAGIC_MB
    if gray is None:
        print("  (no image on record: model comparison skipped)"); return ok
    lo, hi = m2[5], m2[6]
    e = model(gray, lo, hi)
    hist_hw = m2[16:80]
    m_edges = m2[4] == e["strong"]
    m_hist = hist_hw == e["hist"]
    print(f"  model @ {lo}/{hi}: strong edges {e['strong']} -> CPU value {'MATCH' if m_edges else 'MISMATCH'}; "
          f"64-bin histogram read by the CPU -> {'MATCH' if m_hist else 'MISMATCH (%d bins differ)' % sum(a != b for a, b in zip(hist_hw, e['hist']))}")
    return bool(ok and m_edges and m_hist and stable)


def regs_and_mailbox(ops: Ops) -> None:
    ops.read(REGS, 8, "regs"); ops.read(MBOX, 80, "mb"); ops.read(MBOX + 4, 1, "seq")


# --------------------------------------------------------------------------- commands
def cmd_convert(a) -> None:
    gray = to_gray_320x240(load_photo(Path(a.photo)), a.fit)
    print("Converted", a.photo, "->", save_previews(Path(a.photo).stem, gray))


def cmd_send(a) -> None:
    if not FW_BIN.exists():
        sys.exit("Firmware not built: run  make -C fw")
    photo = Path(a.photo)
    gray = to_gray_320x240(load_photo(photo), a.fit)
    d = save_previews(photo.stem, gray)
    OUT.mkdir(parents=True, exist_ok=True)
    np.save(LAST, gray)
    data = gray.tobytes()
    words = bytes_to_words(data)
    fw = bytes_to_words(FW_BIN.read_bytes())
    print(f"Converted {photo.name}: {W}x{H} gray, {len(data)} bytes, CRC32 {zlib.crc32(data):08x}; previews in {d}")
    ops = Ops()
    ops.write(REGS + 0x10, [0])               # hold the CPU in reset while memories are loaded
    ops.write(IMG, words)                     # image (display switches to it when the upload settles)
    ops.write(CPURAM, fw)                     # firmware
    ops.read(IMG, len(words), "image")        # read-back for the byte-exact compare
    ops.read(CPURAM, len(fw), "fwback")
    ops.write(REGS + 0x10, [1])               # start the CPU
    ops.sleep(900)                            # let it publish several frames
    regs_and_mailbox(ops)
    res = run_session(ops, "send", a.tck)
    ok_img = res["reads"]["image"] == words
    ok_fw = res["reads"]["fwback"] == fw
    print(f"Session {res['ms']} ms. Image read-back: {'PASS - all %d bytes identical' % len(data) if ok_img else 'FAIL'}; "
          f"firmware read-back: {'PASS' if ok_fw else 'FAIL'} ({len(fw)} words)")
    ok = check_board(res, gray) and ok_img and ok_fw
    print("RESULT:", "OK - BTN1 toggles pattern/image, SW1:0 = view, SW3:2 = thresholds (set by the CPU)" if ok else "PROBLEM - see lines above")
    sys.exit(0 if ok else 1)


def cmd_status(a) -> None:
    ops = Ops(); regs_and_mailbox(ops)
    res = run_session(ops, "status", a.tck)
    gray = np.load(LAST) if LAST.exists() else None
    sys.exit(0 if check_board(res, gray) else 1)


def cmd_threshold(a) -> None:
    ops = Ops()
    if a.lo == "auto":
        ops.write(MBOX + 128 * 4, [0])
    else:
        lo, hi = int(a.lo), int(a.hi)
        if not (0 <= lo <= 2047 and 0 <= hi <= 2047):
            sys.exit("thresholds are 11-bit registers: use values 0..2047 (the edge magnitude itself only reaches 2040)")
        ops.write(MBOX + 129 * 4, [lo, hi]); ops.write(MBOX + 128 * 4, [1])
    ops.sleep(700); regs_and_mailbox(ops)
    res = run_session(ops, "threshold", a.tck)
    gray = np.load(LAST) if LAST.exists() else None
    sys.exit(0 if check_board(res, gray) else 1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tck", type=int, default=10_000_000, help="JTAG clock (Hz)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for n, f in (("send", cmd_send), ("convert", cmd_convert)):
        s = sub.add_parser(n); s.add_argument("photo"); s.add_argument("--fit", choices=("crop", "pad"), default="crop"); s.set_defaults(fn=f)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    s = sub.add_parser("threshold"); s.add_argument("lo"); s.add_argument("hi", nargs="?"); s.set_defaults(fn=cmd_threshold)
    a = ap.parse_args()
    if a.cmd == "threshold" and a.lo != "auto" and a.hi is None:
        sys.exit("usage: threshold LO HI | threshold auto")
    a.fn(a)


if __name__ == "__main__":
    main()
