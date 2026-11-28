# HW Acoustic Camera

PL design sources and build scripts for the PYNQ-Z2 acoustic camera.

## Current combined design

The active flow starts from the pinned PYNQ Base source commit
`3c77124d86bab65ac7bb6beb0aa66e13c83508f2` and uses
[`scripts/build_phase11_combined.sh`](scripts/build_phase11_combined.sh) with
[`scripts/add_phase11_pcm_to_pynq_base.tcl`](scripts/add_phase11_pcm_to_pynq_base.tcl),
[`scripts/prune_phase11_base_to_camera.tcl`](scripts/prune_phase11_base_to_camera.tcl)
and [`scripts/report_phase11_combined.tcl`](scripts/report_phase11_combined.tcl).
The flow exports the `base.bit` and `base.hwh` pair expected by the PS runtime.

The camera PL path includes four-channel PDM-to-PCM capture and filtering, a
continuous PCM DMA, the PDoA/TDoA IQ tracker, a scheduled buzzer output and the
HDMI video marker. The active RTL and constraints are added explicitly by the
Phase 11 Tcl flow. The build imports PYNQ Base; it does not use the old Hog
project or the standalone XADC/PDM block designs.

Build outputs, reports and measurement evidence remain in `builds/` and
`evidence/`. Their presence or age is not evidence that they can be removed.
The source and runtime documentation describe the implementation path; this
README does not claim new physical acceptance of an AOA3 camera build. See
[`docs/PL_PDOA_TDOA.md`](docs/PL_PDOA_TDOA.md) for tracker design details and
[`docs/PHASE11_INTEGRATION.md`](docs/PHASE11_INTEGRATION.md) for the integration
record.

## Archived source projects

[`archive/legacy-hw/README.md`](archive/legacy-hw/README.md) maps the archived
XADC reference, standalone PDM block designs, their legacy constraints and
release tooling. Those files are retained for history and reproducibility;
they are not inputs to the current combined camera flow. The former XADC
overview is preserved in
[`archive/legacy-hw/README_ORIGINAL.md`](archive/legacy-hw/README_ORIGINAL.md).

## License

This project is licensed under the MIT License; see [LICENSE](LICENSE).
