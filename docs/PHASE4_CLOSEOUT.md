# Phase 4 closeout — four-channel PCM capture

The user confirmed that phase 4 is scoped to functional capture and audio;
physical geometry is deferred until the microphones are mounted as a square.
Under that scope, the four-channel PDM-to-PCM pipeline at 48 kHz is accepted.
This does not claim that the original section-D microphone map or the centered,
equidistant six-pair test passed. Both remain explicitly deferred.

## Hardware result

- Candidate BUILD_ID: `B691CC9C9F6249AD938D2063E4767C54`.
- Vivado 2024.2.2 implementation: WNS `+2.422 ns`, WHS `+0.029 ns`, no failing
  setup/hold endpoints, no unconstrained internal endpoints, and no bitstream DRC
  errors. Warnings were reviewed for actual effect.
- The candidate ran on the PYNQ-Z2 during the phase-4 physical PCM sessions:
  60 blocks × 48,000 frames, four channels, with zero clips, overflow, or DMA
  errors. See `../evidence/phase-04-step-08/board-evidence-review.json` in the
  shared workspace.
- The actual Vivado block-design PDF and its hashes are in
  `../evidence/phase-04-closeout/`; its source BD SHA-256 is
  `40f8ccb6be80e597422272a63e3d48e2352322238da04f6884c71c9f49ccd7fc`.

The phase-3 RAW candidate and integration lock were preserved. Phase 5 stability
and later physical geometry work have not started.

The `phase/04-pcm-capture` branch has been published to GitHub. The final
remote commit IDs are recorded in the workspace closeout record. Phase-4
functional acceptance and geometry deferral are documented above.
