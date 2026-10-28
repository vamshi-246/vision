# RTL and verification checklist

- [ ] SystemVerilog synthesizable constructs only in `rtl/`.
- [ ] Every stateful control path uses the one pixel clock and synchronous
      control reset; datapath registers are unreset unless functionally needed.
- [ ] `always_ff` and `always_comb` are used with explicit widths and complete
      combinational assignments.
- [ ] Each streaming block implements `valid`, `sof`, `eol`, and data; core
      blocks have no back-pressure.
- [ ] Constant multiplies use shifts/adds; no divider is permitted in the pixel
      stream.
- [ ] BRAM line buffers follow a registered simple-dual-port template with
      deliberate `ram_style` attributes.
- [ ] A self-checking testbench, assertions, golden vectors, and a pass/fail
      log exist before a block is integrated.
- [ ] No latches, unconstrained paths, critical warnings, or multi-driven nets
      are accepted in implementation reports.

