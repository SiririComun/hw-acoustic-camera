# Phase 7 closeout — continuous PCM hardware

Status: **closed, 2026-11-18**. The continuous candidate in this repository
passed the synthetic transport/overload gate (7.5) and the prolonged physical
four-microphone capture (7.6) on the PYNQ-Z2.

## Candidate and board evidence

- BUILD_ID: `7A2C7F017A2C4E7D8F70070100000003`, ABI 1.1.
- S2MM Scatter/Gather, status stream disabled, non-cyclic descriptors.
- BIT SHA-256:
  `679d890f92c9ae7d13b6fb71d2777a6e3c89d2c375f1cee10f04fec970b7a56a`.
- HWH SHA-256:
  `e1cb95983851088f5cd22e1b8a107eab5462ac24eaf33bb31f8eb563dacf0833`.
- Physical capture used all four microphones on Pmod B for 30.0466 s. It
  returned 352 contiguous 4096-frame packets over five ring wraps, then drained
  one complete descriptor at STOP. Totals were 1,445,888 frames, 5,783,552
  words and 23,134,208 bytes; zero overflow/clips; all four channels varied.
  The official Base overlay was restored and no DMA buffers were retained.
- The shared workspace retains full run evidence at
  `../../evidence/phase-07-step-06/physical-pcm-20261118/` and the synthetic
  acceptance at `../../evidence/phase-07-step-05/`.

## Block Design and CDC

Vivado 2024.2.2 exported the current source Block Design to the PDF below.
It is included in this repository and is the drawing for the 7.5 DMA status
stream correction:

- [Vivado Block Design PDF](phase-07-closeout/pdm_pcm_continuous_capture-vivado-block-design.pdf)
- PDF SHA-256: `2065aafea4bc731812a846674afac118d6ee2460067de5b102ab9c995af638b5`
- Source BD SHA-256:
  `f90ae753ec99dc6f4921351f551ac7063422a207fc07aec39c0e491b57f6e992`

The final routed CDC report retains 459 CDC-1 Critical, 2 CDC-10 Critical,
2 CDC-11 Critical, 389 CDC-15 Warning and 11 CDC-3 Info classifications. The
functional board tests passed, but they are not CDC sign-off; no CDC-clean claim
is made. Full CDC and export evidence is retained in the shared workspace at
`../../evidence/phase-07-step-05/dma-status-off/reports/implement/` and
`../../evidence/phase-07-closeout/`.

Phase 6 remains closed in its approved scope. PCM/video coexistence was not
tested in this phase. The accepted RAW lock and finite PCM candidate were
preserved.
