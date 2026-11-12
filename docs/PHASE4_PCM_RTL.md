# Phase 4.3: standalone PCM filter RTL

`acoustic_pdm_pcm_filter.vhd` implements the frozen CIC3/R5 + FIR61/R10 chain
for four synchronous PDM bits. It runs in the existing 24 MHz sample domain;
`sample_ce_i` normally pulses once per ten clocks. The coefficient package is
checked against the unchanged HW/SW JSON tables before simulation.

The CIC integrates all four bits on the common CE, using the specified updated
stage values and modular 32-bit arithmetic. Every fifth sample writes one
signed 8-bit CIC value per channel into a 128-slot circular history. Every tenth
CIC sample snapshots the history head and starts a shared MAC: 61 coefficients
for each of four channels, 244 clocks total, within the available 500 clocks.
Computing only retained FIR outputs is equivalent to the reference's full-rate
FIR followed by decimation: **all** CIC samples enter the history. New writes
during the MAC cannot overwrite its captured 61-sample window at the nominal
cadence. Unwritten history is masked by a captured sample count rather than
resetting RAM contents.

## Interface and integration obligations

- `frame_strobe_o`: one pulse per completed result, including six startup
  results. `frame_valid_o` suppresses those six; the seventh is the first valid
  four-channel vector. `filter_ready_o` asserts after the sixth completion.
- `frame_data_o`: four sign-extended signed-24 values in 32-bit slots, mic0 in
  bits 31:0. All channels belong to one sampling phase and appear atomically.
- `frame_clip_o`: one bit per saturated channel, zero for invalid startup
  results. The future block controller must count these bits only for admitted
  block frames; the standalone filter does not implement the CLIP_COUNT register.
- `overrun_o`: sticky until reset if another output calculation is requested
  while the MAC is occupied. It drops ready and suppresses valid results. Future
  integration must abort/report this error instead of accepting partial data.
- `resetn_24m_i`: resets arithmetic, phases, startup validity, and any pending
  calculation. Integration must reset on PDM clock stop/restart. START of a
  capture block must not reset a running settled filter.

The selected result corresponds to PDM indices 49, 99, 149, ... and becomes
available 244 fabric clocks later (10.167 us at nominal 24 MHz). This delivery
latency is additional to the linear-phase signal delay of 65 us. The output
rate remains one vector per 50 PDM samples.

## Verification

Run `python scripts/simulate_pdm_pcm_filter.py` with the two repositories beside
one another. It snapshots sources and coefficients into a new evidence folder,
compiles/elaborates with native XSim, simulates, and compares every result.
The software vector tool first checks the stateful integer reference against an
independent direct 13-tap CIC convolution plus FIR61. Therefore the RTL check
also has an independent oracle for the modular CIC recurrence.

XSim 2024.2.2 passed eight deterministic sequences: positive/negative DC,
identical/distinct random PDM, channel impulses, synthetic tone/image PDM,
identical tone PDM, and reset/restart with CE gaps. The positive DC run includes
32-bit integrator wraps. All 1,850 output vectors (7,400 channel samples),
including startup values, validity, ready, channel order, phase and clip masks,
match exactly. There are 1,802 accepted vectors and 2,672 accepted clipped
channel samples across the deliberate full-scale DC cases. Another 354 exact
arithmetic cases cover all 32 rounding residues around zero and both saturation
limits, plus signed-32 extremes. The bench also verifies the 244-clock delivery
latency, cancellation by mid-MAC reset, and sticky overrun/recovery.

Summary/provenance: [phase4-step3-verification.json](phase4-step3-verification.json).
Full workspace evidence is `evidence/phase-04-step-03/run-20261112T222940Z-f3150c44/`.
Compilation, elaboration and simulation produced no warnings requiring action.
This verifies the standalone digital filter. BD/register/FIFO/DMA integration,
PCM pattern transport, synthesis/resource/timing results, bitstream and board
checks remain for later steps. The phase-3 RAW candidate is preserved.
