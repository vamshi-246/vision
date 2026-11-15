# P7 - Real-Time Edge-Detection Video Pipeline

> **Status 2026-11-15: merged project complete except the items listed below.** Read **docs/FINAL_REPORT.md** (deliverables, evidence,
> resources, quality, formal, hardware), **docs/DEMO_GUIDE.md** (how to run the live demo) and **docs/MERGE_STATUS.md** (how this tree and the
> group-mate's tree (preserved subset in `study/groupmate/` and `docs/groupmate/`) were compared and merged). The older milestone/tool tables that used to be in this file were a
> 2026-10-21 snapshot and are superseded.

## Open / not claimed
* Post-route SDF timing simulation (slow/fast corners): unresolved; boards are programmed with `P7_HW_DEBUG=1`.
* Zybo Z7-10: built and functionally simulated, **not run on hardware** (no Z7 board available); original Zybo is hardware-tested.
* DDR/DMA frame store and OV7670 camera: not built (BRAM frame store loaded over JTAG-AXI is the stated substitute).
* The APB CRC register is not connected to a CRC of the edge map.
* Monitor picture of the final CPU bitstream awaiting the user's visual confirmation.
