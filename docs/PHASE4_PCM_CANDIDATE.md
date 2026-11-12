# Phase 4.6 — routed PCM candidate

Vivado2024.2.2 synthesized and implemented the separate `pdm_pcm_capture.bd`
for xc7z020clg400-1. The isolated build used committed HW source
`744e54a9946b2dc0db2b397bc7d6e198a1077f56`, including the staged native build
script. No new HDL changes were needed. The generated BD/HWH and BIT came from
one project, retained under `builds/phase04-20261112T231414Z-112f5bba/`.

## Result

- BUILD_ID: `B691CC9C9F6249AD938D2063E4767C54`.
- Routed WNS +2.422ns, WHS +0.029ns, pulse-width slack +3.000ns; no failing endpoints.
- Four input paths use the intended falling-PDM to third24MHz edge:125ns.
  Minimum setup slack +22.158ns; minimum hold slack +3.930ns.
- No unconstrained internal endpoints, missing input delay or missing clocks.
  The one `no_output_delay` item is the forwarded PDM clock, not an untimed data output.
- LUT7231/53200 (13.59%), registers8739/106400 (8.21%), BRAM8.5/140 (6.07%), DSP1/220.
- All five fixed LVCMOS33 pins match W14/Y14/T11/T10/V16. HWH validates
  DMA simple S2MM32/length23/address32, PS HP0=64 and DMA-local stream reset.
- Constraint endpoints:4 samples,68 snapshot bits,34 held configuration bits,
  9 first-stage synchronizer inputs and the unique physical clock divider.
- FIFO Gray-pointer bus skew slack ≥9.018ns; held-bus max-delay constraints met.
- BIT SHA256:`5b7b14e34d9372302132746d9ad24475c4df9a1c66f06236ace752b439e91cf2`.
- HWH SHA256:`fc757a78ae638b88eea46fa9a75a0fa67ecdaa09c2599aec19732102bdc9824f`.

## Warnings reviewed by effect

CDC reports are not empty:308 CDC-1 and260 CDC-15 entries correspond to held
configuration and snapshot buses. The synchronized START and request/ack protocol
keep data stable while consumed;41.667ns and15ns datapath bounds cover settling.
The four CDC-10 entries are stop/error/recovery, ready/overrun, reset assertion and
clock-ready gating before their two-stage synchronizers. Sticky/monotonic flags
and reset gating are intentional; reset deassertion is synchronized. The two
CDC-11 entries are independent synchronizers of the same FIFO read-reset status.
No blanket clock-domain false path or new warning waiver was introduced.

REQP-1839/1840 identify asynchronous global-reset drivers of FIFO RAM enables.
A global reset discards the entire acquisition and resets FIFO pointers, so RAM
contents across reset are never reused as valid samples. Local recovery resets
the stream/FIFO through its handshake and reset-busy sequence. Mid-frame recovery
passed simulation in4.4; actual-board recovery remains to be demonstrated.
The report caps repeated REQP-1839 entries at20 (CHECK-3); the same rule applies
across all slices of this FIFO. This is not a claim of zero DRC warnings.

DSP pipeline suggestions do not require architectural changes because routed
performance is met. LUT packing warnings pass bit generation. Unused generated
SmartConnect reset nets, optional DMA debug outputs, absent vendor waiver targets,
internal SC payload field narrowing and unsupported updatemem patching of some
XPM memories do not change this acquisition interface. REQP-181 is the vendor DMA
FIFO WRITE_FIRST advisory; collision avoidance relies on its occupancy control.
Full bit generation completed with zero errors/critical warnings in that command.

## Delivery and limits

`docs/phase4-step6-verification.json` summarizes the evidence. Full reports and
warning assessment: `evidence/phase-04-step-06/reports/` and `review.json`.
The candidate folder contains the actual pair, source/hash manifest and software
wheel/delivery manifest. Companion software pins the pair and candidate manifest;
its notebook still defaults to all hardware flags false and never programs FPGA.
Read-only preflight rejected altered temporary copies of manifest/BIT/HWH.
The wheel was built and its packaged bytes compared with source, without install.

No SSH, board programming or hardware tests were performed. The external return
envelope0..90ns remains an engineering condition, not a measured microphone bound.
The accepted RAW HDL/BD/build files, driver/loader, pair and integration lock are
preserved. Phase4 is still pending digital/acoustic acceptance on the actual board.
Next4.7: authorized installation/programming, brief RAW check after restored Mic0/B2
and Mic1/B3 wiring, PCM patterns and recovery. The actual Vivado BD PDF must be
exported/delivered for the accepted candidate at phase4 closure.
