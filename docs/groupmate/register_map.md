# APB register map -- `rtl/apb_regs.sv` (documented as implemented)

Bus: **standard AMBA APB3 slave** (PSEL, PENABLE, PWRITE, PADDR[7:0], PWDATA[31:0], PRDATA[31:0], PREADY, PSLVERR),
single clock (`clk`), zero wait states (`PREADY` = 1), `PSLVERR` = 0 always (writes to read-only / unmapped addresses are
silently ignored, reads of unmapped addresses return 0). Word-aligned byte addresses, `PADDR[1:0]` ignored.

**RV32:** no RISC-V core is instantiated in this project (RV32 is optional in the plan). The interface is a plain APB3 slave,
so any RV32 core with an APB bridge (e.g. through a memory-mapped APB peripheral port) can attach unchanged and read
EDGE_CNT / FRAME_CNT / the histogram. In the board design the thresholds are written by a tiny APB master FSM instead
(see `rtl/zybo_top.sv`, "top-level controller").

| offset | name | access | reset | description |
|---|---|---|---|---|
| 0x00 | CTRL | R/W | 0x1 | control |
| 0x04 | THR_HI | R/W | 192 | strong threshold (11 bit) |
| 0x08 | THR_LO | R/W | 64 | weak threshold (11 bit) |
| 0x0C | STATUS | R / W1C | 0x0 | status |
| 0x10 | EDGE_CNT | RO | 0 | strong-edge pixel count, last completed frame |
| 0x14 | FRAME_CNT | RO | 0 | completed frames |
| 0x18 | WEAK_CNT | RO | 0 | weak-edge pixel count, last completed frame |
| 0x1C | HIST_SEL | R/W | 0 | histogram bin select |
| 0x20 | HIST_DATA | RO | 0 | histogram count of the selected bin, last completed frame |
| 0x24 | ID | RO | 0x50370001 | constant ID |
| 0x28 | THR_ACT | RO | 64<<16 \| 192 | thresholds currently applied by the classifier |

## CTRL (0x00)
| bits | name | access | description |
|---|---|---|---|
| 0 | EN | R/W | 1 = frame-sync tracker enabled (reset value 1). Writing 0 aborts tracking immediately: `ctrl_sync` returns to IDLE, STATUS.LOCKED drops, the next `sof` is ignored until EN=1 again. |
| 1 | CLR | W1P (reads 0) | writing 1 clears EDGE_CNT, WEAK_CNT, FRAME_CNT, all 16 histogram snapshots and the running (live) counters. Wins over a frame boundary in the same cycle. |
| 31:2 | - | RO 0 | reserved |

## THR_HI (0x04), THR_LO (0x08)
| bits | description |
|---|---|
| 10:0 | threshold on the NMS magnitude (0..2047; the magnitude itself is 0..2040). THR_HI: `nms >= THR_HI` -> strong (class 2). THR_LO: `nms >= THR_LO` -> weak (class 1). A pixel with nms = 0 is always class 0. THR_LO > THR_HI is allowed (every pixel above THR_HI is strong; weak needs `THR_LO <= nms < THR_HI`, so none). |
| 31:11 | reserved, read 0 |

**Latching:** the values written here are copied into the *active* thresholds (readable at THR_ACT) only at the end of a frame
(`ctrl_sync.frame_end`), so a write in the middle of a frame never changes that frame; while the tracker is IDLE the active
values follow the written ones immediately (so values programmed before the first `sof` apply from frame 0). Verified in
`tb/tb_top.sv` (thresholds changed mid-frame 1: frame 1 keeps the old pair, frame 2 uses the new pair).

## STATUS (0x0C)
| bit | name | access | description |
|---|---|---|---|
| 0 | LOCKED | RO | `ctrl_sync` is in RUN (tracking frames) |
| 1 | FRAME_DONE | R / W1C | set at every end of frame (sticky); write 1 to clear. A set event in the same cycle wins over the clear. |
| 2 | SYNC_ERR | R / W1C | set when a `sof` arrives while RUN at a cell other than (0,0) (the counters are re-aligned); sticky, write 1 to clear |
| 3 | THR_PENDING | RO | THR_HI/THR_LO differ from the active thresholds, i.e. a write is waiting for the next frame boundary |
| 31:4 | - | RO 0 | reserved |

## EDGE_CNT (0x10), WEAK_CNT (0x18)
Bits 19:0 (reads 0 above). Number of pixels classified strong (class 2) / weak (class 1) in the **last completed frame**
(snapshot taken at `frame_end`; maximum 640*480 = 307,200 < 2^20). The counters run on the classified pixel stream;
borders are never counted because classification is 0 outside the margin-3 valid region.

## FRAME_CNT (0x14)
Bits 31:0: number of `frame_end` events since reset / CLR.

## HIST_SEL (0x1C), HIST_DATA (0x20)
16-bin histogram of the **non-zero NMS magnitudes** of the last completed frame. Bin index = `nms[10:7]` (= nms >> 7),
i.e. bin b covers magnitudes 128*b .. 128*b+127 (bin 15 = 1920..2040). HIST_SEL[3:0] (R/W, upper bits read 0) selects the bin;
HIST_DATA[19:0] reads its count (upper bits read 0). Pixels with nms = 0 are not counted.

## ID (0x24)
0x5037_0001 ("P7", version 1).

## THR_ACT (0x28)
Bits [10:0] = active THR_HI, bits [26:16] = active THR_LO; other bits 0.
