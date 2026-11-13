# Phase 5.1 — hardware candidate baseline

Reviewed 2026-11-13 against the accepted phase 4 candidate. This step makes no
RTL, Block Design, constraint, or bitstream changes.

## Pinned candidate

- BUILD_ID: `B691CC9C9F6249AD938D2063E4767C54`
- Phase 4 published base: `16914da9e334fd62e2aeb15b18a2c5337b338295`
- Source candidate reviewed in 4.6: `29f9d1d08b95442d5dc8882017b56083d5a48a3d`
- BIT SHA-256: `5b7b14e34d9372302132746d9ad24475c4df9a1c66f06236ace752b439e91cf2`
- HWH SHA-256: `fc757a78ae638b88eea46fa9a75a0fa67ecdaa09c2599aec19732102bdc9824f`
- Vivado: 2024.2.2

## Implementation review

The routed candidate reports WNS `+2.422 ns`, WHS `+0.029 ns`, WPWS
`+3.000 ns`, no failing setup or hold endpoints, no unconstrained internal
endpoints, and no bitstream DRC errors. The data setup and hold minimum slacks
are `22.158 ns` and `3.930 ns`; bus-skew minimum slack is `9.018 ns`.

The warning review in
`evidence/phase-04-step-06/review.json` does not identify a functional reason to
rebuild for phase 5. SmartConnect width messages concern generated internal
AXI-Lite payload fields; the external DMA stream remains 32 bits. The optional
DMA debug pin is unused. FIFO write-first advisories are handled by occupancy
control and the actual-board pattern/recovery exercise in phase 4.7. Reset and
RAM warnings describe invalidating a whole acquisition on reset; the accepted
recovery flow and simulation cover that behavior. Placed LUT packing messages
did not cause routed timing or bit-generation DRC failures. No claim is made
that Vivado emitted zero warnings.

The external clock-to-data envelope remains conditional: the microphone
waveform was not measured externally. That limitation is recorded and does not
by itself justify changing the accepted candidate for the phase 5 block-capture
stability campaign.

## Decision for phase 5

Keep this candidate fixed for the 100-block campaign. Revisit hardware only if
the campaign exposes a concrete error, overflow, count mismatch, or other
hardware-attributable failure. If no change is required, do not rebuild or
reprogram a new bitstream solely to clear advisory warnings.
