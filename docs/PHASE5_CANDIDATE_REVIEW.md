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

## Phase 5 campaign and closure

The phase 5.3 physical campaign passed 100/100 serial captures of 48,000
four-channel PCM frames on the pinned candidate. Every returned array and its
metadata passed the frame, word, byte, status, range, provenance, overflow, clip
and DMA checks; the clock was disabled at completion. The campaign report and
per-block records are retained in workspace evidence under
`evidence/phase-05-step-03/board/pcm-stability-20261113T184651Z-45725f00/`.

No RTL, Block Design, constraints, BIT or HWH changed during phase 5, so no
hardware rebuild was needed. The 1.902949 s host call for block 51 passed its
data and hardware counters; criterion E has no maximum call-duration limit.
The logged inter-call pauses do not establish sample loss inside complete
blocks, and the campaign does not claim continuous acquisition. No tones,
channel mapping or geometry tests were performed.

The actual Vivado 2024.2.2 Block Design PDF delivered at phase 5 closeout is
`evidence/phase-05-closeout/phase5-vivado-block-design.pdf`, SHA-256
`61e81bf3c304dea847b2d670193daa16492ae97c685eb39ac0de38aa33579078`. It is a
byte-identical copy of the accepted phase 4 export; the source BD hash remains
`40f8ccb6be80e597422272a63e3d48e2352322238da04f6884c71c9f49ccd7fc`.
