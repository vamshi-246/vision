# P7 - Real-Time Edge-Detection Video Pipeline

> **Status 2026-11-15: merged project complete except the items listed below.** Read **docs/FINAL_REPORT.md** (deliverables, evidence,
> resources, quality, formal, hardware), **docs/DEMO_GUIDE.md** (how to run the live demo) and **docs/MERGE_STATUS.md** (how this tree and the
> group-mate's tree (preserved subset in `study/groupmate/` and `docs/groupmate/`) were compared and merged). The older milestone/tool tables that used to be in this file were a
> 2026-10-21 snapshot and are superseded.

## Open / not claimed
* Post-route SDF timing simulation (slow/fast corners): unresolved; boards are programmed with `P7_HW_DEBUG=1`.
* Zybo Z7-10: **hardware-verified 2026-11-20** (HDMI TX to monitor, JTAG upload, RV32 firmware; see release/zybo_z7_v1/). Original Zybo also hardware-tested.
* DDR/DMA frame store and OV7670 camera: not built (BRAM frame store loaded over JTAG-AXI is the stated substitute).
* The APB CRC register is not connected to a CRC of the edge map.
* (Closed) Monitor picture confirmed by the user on the Zybo Z7.
