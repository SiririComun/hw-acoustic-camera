# Phase 2: PDM clock and AXI control

The separate `pdm_clock_control` block design targets PYNQ-Z2. It contains the
accepted PS configuration, AXI SmartConnect, reset infrastructure and the
`acoustic_capture_0` module reference at `0x43C00000`. This design implements clock
and control only; microphone DATA capture, FIFO, DMA and PCM start in later phases.

## Clock and interface

- AXI/control remains at 100 MHz from PS FCLK0.
- MMCME2_BASE uses M=36, D=5 and O=30: VCO 720 MHz, output 24 MHz.
- A synchronous divide by 10 generates nominal 2.4 MHz with nominal 50% duty.
- CLOCK_ENABLE and status use two-stage synchronizers. Reset asserts
  asynchronously and releases synchronously in the 24 MHz domain.
- CLOCK_READY requires MMCM lock and 48,000 rising PDM edges (nominal 20 ms).
- MAGIC=`0x4143414D`, ABI=`0x00010000`, channels=4, capabilities=`0x1`.
- Accepted BUILD_ID=`710bf4adefe94edab8e0ab42a5138648`.
- START is unavailable, sets a configuration error and is recoverable with CLEAR.

| Signal | Pmod B pin | FPGA pin | Direction |
|---|---:|---|---|
| CLK common to all microphones | 1 | W14 | Output |
| DATA0 (reserved) | 2 | Y14 | Input |
| DATA1 (reserved) | 3 | T11 | Input |
| DATA2 (reserved) | 4 | T10 | Input |
| DATA3 (reserved) | 7 | V16 | Input |

All signals use LVCMOS33. DATA inputs have no sampler in phase 2. Their external
input timing must be defined with the phase-3 sampler; they are not certified
capture channels by this design.

## Original build (historical; retired after interrupted board test)

Vivado 2024.2.2 completed implementation and bitstream generation in step 2.8.
Routed timing: WNS +4.070 ns, WHS +0.106 ns, no failing endpoints, no unrouted
nets and zero DRC checks reported. The exact design input hashes are preserved in
the original `evidence/phase-02-step-08/candidate-manifest.json` in the common
workspace. The source snapshot committed as
`52c376c52206b72bc4e29f9cb7c5e67cbdcb6537` matches those recorded input hashes.
The original manifest retains the baseline-plus-uncommitted-source state at build
time; committing that snapshot does not change its historical provenance.

- BIT SHA-256: `6d0197d636f53169931fa26bb3b2ef6c0e59457166a998def09d3247e6edc5d0`
- HWH SHA-256: `e04547331973c393c34121e41bf08df394178668c03a76e22080b12329f94901`
- SW wheel source commit: `6ad1acb49555d8b332dad2d8d2712f07a84b6ff5`

`scripts/create_pdm_clock_control_bd.tcl` creates and synthesizes the separate BD.
`scripts/implement_pdm_clock_control.tcl` implements an existing generated project
and exports the matching BIT/HWH. Neither script programs a board.

## Board validation and mechanical connection

The corrected candidate passed on the real PYNQ-Z2 on 2026-11-11 (America/Bogota):
identity, ten enable/ready/disable cycles, wrong BUILD_ID rejection with no writes,
START/CLEAR without bus exceptions, and reset by a second explicit FPGA load.
Six code cells executed without errors; runtime dependencies were unchanged.
The clock was disabled at the end. The user performed the interactive sudo call.

Accepted source commit: `bbfa3abb13154fbe61dc5d1bd5b677f439fd09d2`.
Accepted BIT SHA-256: `9fd66b9cea4eb7bc7a8c7a5ba0f1baf4be7d25df6d281d5db9c98bbef5325bf7`.
Accepted HWH SHA-256: `2edb08e0243ff66b624e323a3be25900c859ddb88b2a983b5aab89d2b03df3c5`.
Corrected routed timing: WNS +3.940 ns, WHS +0.118 ns; no failing endpoints or DRC violations.
Artifacts, report and review: `evidence/phase-02-closure/` in the common workspace.
The phase-2 acceptance record is `context/integration-lock.json`.

The block diagram PDF was exported from the implementation project's actual BD
and is preserved in `evidence/phase-02-closure/` in the common workspace.

Functional clock/control acceptance does not certify the external waveform.
Without an oscilloscope or logic analyzer, frequency, duty and signal integrity
at Pmod B remain unmeasured. Microphones remain disconnected for this test.
Before physical mounting in phase 3, confirm module identity and orientation,
check continuity with power off, measure the 3.3 V rail and give the user the
final wiring instructions.

## Board-attempt correction (2026-11-11)

The initial candidate has been retired following an interrupted board test.
Its unused proc_sys_reset auxiliary input was tied low while configured active
low, holding AXI peripherals in reset. The corrected design explicitly sets
C_AUX_RESET_HIGH=1 and C_EXT_RESET_HIGH=0 (PS FCLK_RESET0_N remains active low).
The new BUILD_ID is 710bf4adefe94edab8e0ab42a5138648.
Unsupported operations at valid command/configuration addresses acknowledge AXI
with OKAY and set ERROR_FLAGS; this allows software to inspect and clear the
application error without a CPU external abort. Malformed/unmapped/RO accesses
retain AXI bus errors. The corrected candidate subsequently passed the real board validation above.
