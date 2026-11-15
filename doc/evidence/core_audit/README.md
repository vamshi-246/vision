# Preserved baseline verification evidence

Audit date: **13 November 2026**. Interpretation and scope are in
[`CORE_RTL_REVIEW.md`](../../../docs/CORE_RTL_REVIEW.md); reproduction commands
are in [`FPGA_NEXT_STEPS.md`](../../../docs/FPGA_NEXT_STEPS.md).

- `audit_manifest.json`: source hashes, tools, counts and scope.
- `full_rtl_*`, `icarus_regression.txt`: stage-by-stage comparisons and traffic modes.
- `stress_*`, `mutation_checks.txt`: arithmetic, exhaustive direction, protocol,
  histogram, recovery, CRC and test sensitivity results.
- `netlist_*`: actual Vivado synthesized-netlist simulation in XSim.
- `python_tests.txt`, `unit_tests.txt`, `photo_result.json`, `custom_photo_result.json`:
  software, unit benches and independent image-file comparison results.
- `bare_core_*`: bare OOC resource/timing results, including boundary hold failures.
- `registered_*`, `timing_gate.txt`: the registered shell's internal setup/hold
  pass, resources, DRC and acknowledged methodology warnings.
- `auxiliary_synthesis.txt`: standalone auxiliary blocks synthesize without latches.
- `installed_video_ips.txt`: local catalog inventory, not proof of board/IP compatibility.

The unmodified initial core passed small legal-frame tests but failed Vivado
import; `baseline_small_regression.txt` preserves that limited simulation
result. The current corrected core is identified by the manifest hashes.
Large vectors, executables, netlists, checkpoints and full tool logs are kept
in ignored `build/`. No formal or hardware result is implied by these files.
