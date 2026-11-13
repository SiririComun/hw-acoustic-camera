# Phase 4.8 — physical PCM candidate observation

The routed 4.6 PCM BIT/HWH pair (BUILD_ID
`B691CC9C9F6249AD938D2063E4767C54`) was explicitly programmed for each
of six physical microphone sessions. The four-channel output supplied 60
blocks of 48000 nominal 48 kHz PCM frames, with exact DMA lengths and zero
clips, overflow or error flags. Each run ended with the PDM clock disabled.
The first block showed filter startup settling; subsequent blocks were stable
enough for acoustic spectral and pair-delay comparisons.

Laptop-speaker tones at 1, 2 and 3 kHz were present in all four channels in
all ten blocks per tone. Minimum peak-to-neighbor-floor margins were 42.17,
52.08 and 73.72 dB. Broadband tests at the first two closely spaced physical
modules yielded earliest arrival on logical channels 0 and 1, respectively,
in nine settled blocks per position. This is provisional geometry evidence.

The user deferred full physical channel mapping until the microphones are
placed in the intended square. Centered/equidistant six-pair broadband testing
also remains pending because the current geometry lacks a controlled center.
Section-D physical acceptance and phase-4 closure remain open. The
accepted phase-3 RAW candidate and lock remain unchanged. The real Vivado BD
PDF is due at phase-4 closeout. Full evidence and review live at
`../evidence/phase-04-step-08/` in the shared workspace.
