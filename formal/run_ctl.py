#!/usr/bin/env python3
"""CTL model checking of the SHIPPED frame/line-synchronisation RTL.

For every target: real RTL (small parameters) -> Yosys write_smv -> NuSMV 2.6 (CTL + check_fsm), then RTL mutants are checked
to prove each property set can fail.  Reset state is the initial state (Yosys emits no initial values).  Properties are
checked on the reduced-size instance; the logic is parameterised only by comparisons with the sizes, so the same RTL is
instantiated at 640x480 in the product (an instance-size limit that is stated in the report).
"""
import json, re, subprocess, sys, shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
NUSMV = ROOT / "build/tools/NuSMV-2.6.0-Linux/bin/NuSMV"
OUT = ROOT / "build/formal"; OUT.mkdir(parents=True, exist_ok=True)

def u(width, val): return f"0ud{width}_{val}"

def targets():
    # vga_timing: H_TOTAL=6 (3 active), V_TOTAL=5 (2 active); counters are 3-bit words.
    vga = dict(
        file="rtl/vga_timing.sv", top="vga_timing",
        chparam="-set H_ACTIVE 3 -set H_FP 1 -set H_SYNC 1 -set H_BP 1 -set V_ACTIVE 2 -set V_FP 1 -set V_SYNC 1 -set V_BP 1",
        init=f"top._h_count = {u(3,0)} & top._v_count = {u(3,0)}",
        specs={
         "P1 horizontal counter bounded (h < H_TOTAL)": f"AG (top._h_count < {u(3,6)})",
         "P2 vertical counter bounded (v < V_TOTAL)": f"AG (top._v_count < {u(3,5)})",
         "P3 SOF only at the raster origin": f"AG (bool(top._sof) -> (top._h_count = {u(3,0)} & top._v_count = {u(3,0)}))",
         "P4 a new frame can always start (AG EF sof)": "AG EF bool(top._sof)",
         "P5 end of frame is always reachable (AG EF eof)": "AG EF bool(top._eof)",
         "P6 end-of-line only inside active video (eol -> de)": "AG (bool(top._eol) -> bool(top._de))",
         "P7 line wraps: last column -> column 0": f"AG (top._h_count = {u(3,5)} -> AX top._h_count = {u(3,0)})",
         "P8 raster wraps: last cell -> origin": f"AG ((top._h_count = {u(3,5)} & top._v_count = {u(3,4)}) -> AX (top._h_count = {u(3,0)} & top._v_count = {u(3,0)}))",
         "P9 active video recurs (AG EF de)": "AG EF bool(top._de)",
         "P10 EOF implies EOL": "AG (bool(top._eof) -> bool(top._eol))",
        },
        mutants={
         "M1 line one cycle too long": ("h_count == H_TOTAL - 1", "h_count == H_TOTAL"),
         "M2 frame never wraps (v stuck at last line)": ("v_count <= '0;\n      end else begin\n        v_count <= v_count + 1'b1;", "v_count <= v_count;\n      end else begin\n        v_count <= v_count + 1'b1;"),
         "M3 SOF one pixel late": ("(h_count == '0) && (v_count == '0);\n    eol", "(h_count == 1) && (v_count == '0);\n    eol"),
         "M4 EOL one pixel late (outside active video)": ("eol   = de && (h_count == H_ACTIVE - 1)", "eol   = (h_count == H_ACTIVE)"),
         "M5 vertical counter never advances": ("v_count <= v_count + 1'b1;", "v_count <= v_count;"),
        })
    sync = dict(
        file="rtl/ctrl_sync.sv", top="ctrl_sync", chparam="-set IMG_W 3 -set IMG_H 3",
        init=f"top._x = {u(2,0)} & top._y = {u(2,0)} & top._sync_error = {u(1,0)}",
        specs={
         "S1 out-of-range coordinate always raises sync_error": f"AG (((top._x > {u(2,2)}) | (top._y > {u(2,2)})) -> top._sync_error = {u(1,1)})",
         "S3 clean stream reachable again (AG EF no error)": f"AG EF (top._sync_error = {u(1,0)})",
         "S4 a protocol-conformant frame start is reachable (AG EF x=0,y=0)": f"AG EF (top._x = {u(2,0)} & top._y = {u(2,0)})",
        },
        mutants={
         "C1 error flag never set": ("sync_error <= 1'b1;", "sync_error <= 1'b0;"),
         "C2 line end ignores IMG_W": ("(in_eol != (x == X_W'(IMG_W - 1)))", "1'b0"),
         "C3 row counter never wraps": ("y <= (y == Y_W'(IMG_H - 1)) ? '0 : y + 1'b1;", "y <= y + 1'b1;"),
        })
    return {"vga_timing": vga, "ctrl_sync": sync}

def build(t, name, src_text=None):
    """Export the RTL once; return (dir, body_smv_text)."""
    d = OUT / name; d.mkdir(parents=True, exist_ok=True)
    f = d / Path(t["file"]).name
    f.write_text(src_text if src_text is not None else (ROOT / t["file"]).read_text())
    smv = d / "rtl.smv"
    cmd = f"read_verilog -sv \"{f}\"; chparam {t['chparam']} {t['top']}; hierarchy -top {t['top']}; proc; flatten; opt -fast; memory_map; opt -fast; dffunmap; write_smv \"{smv}\""
    r = subprocess.run(["yosys", "-q", "-p", cmd], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr + r.stdout)
    return d, smv.read_text()

def check_all(t, d, body):
    """One NuSMV run per property (verdict order is not preserved by NuSMV, so runs are kept separate).
    -ctt also checks that the transition relation is total (no deadlock state)."""
    verdicts, total = {}, None
    for i, (k, v) in enumerate(t["specs"].items()):
        m = d / f"spec{i}.smv"
        m.write_text(body + f"\nMODULE main\nVAR top : _{t['top']};\nINIT {t['init']}\nCTLSPEC {v};\n")
        r = subprocess.run([str(NUSMV), "-ctt", str(m)], capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL)
        out = r.stdout + r.stderr
        (d / f"spec{i}.log").write_text(out)
        mm = re.search(r"-- specification .*? is (true|false)", out)
        if not mm: raise RuntimeError(f"NuSMV gave no verdict for {k}:\n{out[-800:]}")
        verdicts[k] = mm.group(1) == "true"
        total = "The transition relation is total: No deadlock state exists" in out
    return verdicts, total

def main():
    if not NUSMV.exists(): sys.exit(f"NuSMV not found at {NUSMV}")
    report = {}
    for name, t in targets().items():
        d, body = build(t, name)
        base, total = check_all(t, d, body)
        print(f"== {name}: transition relation total (no deadlock state): {total}")
        for k, v in base.items(): print(f"   {'TRUE ' if v else 'FALSE'}  {k}")
        assert all(base.values()) and total, f"{name}: original RTL does not satisfy all properties"
        mut_res = {}
        for mname, (old, new) in t["mutants"].items():
            src = (ROOT / t["file"]).read_text()
            assert old in src, f"mutation anchor not found: {mname}"
            md, mbody = build(t, f"{name}_{mname.split()[0]}", src.replace(old, new, 1))
            mv, mtotal = check_all(t, md, mbody)
            caught = [k for k, v in mv.items() if not v] + ([] if mtotal else ["deadlock (transition relation not total)"])
            mut_res[mname] = caught
            print(f"   mutant {mname}: caught by {len(caught)} -> {[c.split()[0] for c in caught]}")
            assert caught, f"mutant not caught: {mname}"
        report[name] = {"properties": base, "deadlock_free": total, "mutants": mut_res}
    (OUT / "ctl_results.json").write_text(json.dumps(report, indent=2) + "\n")
    print("\nALL PROPERTIES TRUE ON THE SHIPPED RTL; EVERY MUTANT CAUGHT")

if __name__ == "__main__": main()
