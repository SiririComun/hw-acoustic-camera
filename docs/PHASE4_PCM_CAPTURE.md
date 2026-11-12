# Phase 4 — four-channel PCM capture

Status: steps 4.1–4.5 complete. The PCM control/filter/FIFO/AXI path passed
native XSim and the separate DMA BD was validated in Vivado. No phase-4 bitstream
has been generated. See [PHASE4_PCM_INTEGRATION.md](PHASE4_PCM_INTEGRATION.md)
and [PHASE4_PCM_SOFTWARE.md](PHASE4_PCM_SOFTWARE.md) for the verified local SW handoff.

## Baseline

This branch starts at the accepted phase-3 RAW source commit
`82ad0bd01c2283d5924b47e579135df359e989b5` (BUILD_ID
`CBC300E1202C4B1E9DE4178E96E3F944`). Keep the phase-3 capture candidate and its
integration record intact. The accepted hardware provides clock, RAW and pattern
capabilities (`CAPABILITIES=0xB`); PCM capability bit 2 is not yet set.

## Contracted PCM interface

The acquisition contract is `acoustic-camera-capture/1.0`. Preserve all RAW
register and data semantics while adding the already specified PCM capability:

- PDM clock nominally 2.4 MHz, common decimation factor 50, PCM rate 48 kHz.
- `FORMAT=1` selects `PCM_S24_IN_S32`; each frame is four signed 24-bit samples
  sign-extended into 32-bit words in channel order 0, 1, 2, 3.
- `SOURCE=1` emits the transport pattern `16*n+c`; it checks PCM ordering and
  block transport, but bypassing the physical filter does not validate it.
- Implement the specified `FILTER_READY`, nominal rate/decimation,
  `CLIP_COUNT` and `FILTER_SETTLE_FRAMES` behavior. Physical PCM starts only
  after the common filter settling interval.
- Preserve frame atomicity, exact counters, error recovery, and one final TLAST
  at the end of the `4*N`-word block.

The filter architecture, coefficients, fixed-point widths, scaling, rounding,
latency and settling count must be designed and recorded before RTL changes.
The frozen design is in [PHASE4_PCM_FILTER_DESIGN.md](PHASE4_PCM_FILTER_DESIGN.md);
its standalone implementation is in [PHASE4_PCM_RTL.md](PHASE4_PCM_RTL.md).
