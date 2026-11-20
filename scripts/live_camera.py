#!/usr/bin/env python3
"""Show the laptop webcam full-screen, 800x600, on the display that is wired to the FPGA's HDMI RX port (default xrandr output DP-1).
The FPGA reads this picture over HDMI, runs the edge pipeline and shows the result on the monitor.  Quit: Esc or Ctrl+C.
Usage: python3 scripts/live_camera.py [--output DP-1] [--device /dev/video0] [--no-mirror]"""
import argparse, os, re, subprocess, sys
os.environ.setdefault("GDK_SCALE", "1"); os.environ.setdefault("GDK_DPI_SCALE", "1")
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("Gst", "1.0")
from gi.repository import Gtk, Gst, GLib, Gdk

ap = argparse.ArgumentParser()
ap.add_argument("--output", default="DP-1"); ap.add_argument("--device", default="/dev/video0")
ap.add_argument("--no-mirror", action="store_true")
a = ap.parse_args()
xr = subprocess.run(["xrandr"], capture_output=True, text=True).stdout
m = re.search(rf"^{re.escape(a.output)} connected (?:primary )?(\d+)x(\d+)\+(\d+)\+(\d+)", xr, re.M)
if not m: sys.exit(f"xrandr output {a.output} is not connected/active")
w, h, x, y = map(int, m.groups())
if (w, h) != (800, 600): sys.exit(f"{a.output} is {w}x{h}; set it first: xrandr --output {a.output} --mode 800x600 --scale 1x1")
Gst.init(None); Gtk.init(None)
flip = "" if a.no_mirror else "videoflip method=horizontal-flip ! "
pipe = Gst.parse_launch(f"v4l2src device={a.device} ! videoconvert ! videocrop left=160 right=160 ! videoscale ! video/x-raw,width=800,height=600 ! {flip}videoconvert ! gtksink name=sink")
sink = pipe.get_by_name("sink"); sink.set_property("sync", False)
win = Gtk.Window(); win.set_decorated(False); win.set_default_size(800, 600); win.add(sink.props.widget)
win.connect("destroy", Gtk.main_quit)
win.connect("key-press-event", lambda _w, e: Gtk.main_quit() if e.keyval == Gdk.KEY_Escape else None)
win.show_all(); win.move(x, y); win.resize(800, 600)
pipe.set_state(Gst.State.PLAYING)
try: Gtk.main()
finally: pipe.set_state(Gst.State.NULL)
