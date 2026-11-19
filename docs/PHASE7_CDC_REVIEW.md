# Phase 7.4 — CDC review of the continuous PCM candidate

Historical review snapshot from 2026-11-17. Phase 6 was still open at that
point; its approved scope and the phase-7 physical-capture result are recorded
in [`PHASE7_CLOSEOUT.md`](PHASE7_CLOSEOUT.md). The later 7.5 BD correction and
the final Vivado PDF are also recorded there. This report remains the CDC
review record; the listed Critical/Warning findings are not called clean.

Date: 2026-11-17 (America/Bogota). Status: **review complete for the synthetic
transport gate in 7.5; no claim that the design is CDC-clean**. Phase 6 remains
open at 6.3. The continuous PCM candidate remains separate from the accepted
PCM and video designs.

## Reviewed build

This is a correction to the 7.2 candidate, kept separate from the accepted
design. The source changes register the producer stop indication in `clk100m`
and filter readiness in `clk24m` before their existing two-flop crossings. The
register simulation and continuous stream simulation pass. Vivado rebuilt the
acoustic-capture out-of-context synthesis and then reran synthesis and routed
implementation; this avoids reusing the stale OOC checkpoint from the first
attempt. The current build is ABI 1.1, BUILD_ID
`7A2C7F017A2C4E7D8F70070100000002`.

The corrected `.bit` and matching `.hwh` are in
`evidence/phase-07-step-04/candidate/`. SHA-256:

- bit: `8072ec35f2bedeedfdea1b0ba13961fee40d430aca032c706436c56a98e5ab74`
- HWH: `3882d98dc20fc284154bd93b1cdbcd7cc80f6fd37df6cd1fffae49712c67075c`

The Block Design did not change; the actual Vivado PDF exported in 7.2 remains
the applicable drawing. The candidate has **not** been programmed on the board.

## CDC disposition

The final routed report classifies CDC-1: 459 Critical, CDC-3: 11 Info, CDC-10:
2 Critical, CDC-11: 2 Critical, and CDC-15: 389 Warning. Vivado's “Safely
Timed” clock-pair label does not mean the design is CDC-clean.

### Functional paths corrected

- `stop_level` is now registered in the 100 MHz source domain before
  `stop_pipe[0]`; Vivado reports this as CDC-3.
- `filter_ready_24` is now registered in the 24 MHz source domain before
  `filter_ready_pipe[0]`; Vivado reports this as CDC-3.

Both source registers and first-stage destinations are visible in the routed
CDC report. This removes the two functional combinational-before-synchronizer
concerns from the prior review.

### Remaining classifications and practical disposition

- The two CDC-10 entries are reset-related: asynchronous assertion at
  `reset24_pipe[0]/CLR`, already narrowly false-pathed by the existing Phase 4
  constraint, and reset status entering the fail-closed ready synchronizer.
  Reset release remains synchronized in the destination domain.
- The two CDC-11 entries originate in the XPM FIFO reset controller and feed
  its reset synchronizer and the local `read_busy_pipe[0]` synchronizer. The
  destination is a synchronizer stage; reset recovery waits for FIFO busy
  status to clear before acknowledging recovery. FIFO read/write requests are
  gated by reset, busy, and empty status. Preserve this reset sequence.
- Most CDC-1/CDC-15 rows are the held configuration and snapshot buses. The
  start and snapshot toggle/acknowledge protocols keep each bus stable while
  sampled; the existing XDC bounds configuration to 41.667 ns and snapshot
  data to 15 ns. These grouped paths remain classified by Vivado and must not
  be described as individually synchronized or as proof of clean CDC.

For 7.5, the candidate is suitable for a **controlled synthetic-pattern
transport test** that checks stream continuity, descriptor completion, and
overload/error reporting. That is a functional board gate, not CDC sign-off.
Stop if reset recovery, ready status, DMA completion, or sample counters behave
unexpectedly. Do not use this review alone to authorize the later prolonged
physical microphone capture.

## Implementation report

- Routed setup: WNS `+1.746 ns`, zero failing setup endpoints.
- Routed hold: WHS `+0.018 ns`, zero failing hold endpoints.
- Timing summary: all user-specified timing constraints met.
- `check_timing`: no unconstrained internal endpoints, no missing input
  delays, and one LOW missing output delay on `pdm_clk_o`.
- DRC: 43 checks (42 Warning, 1 Advisory), zero errors. The report includes
  20 REQP-1839 and 6 REQP-1840 asynchronous BRAM-control warnings, plus
  pipelining, slice-pairing, report-limit, and routability findings. Preserve
  them as known implementation findings; this step does not claim the
  warnings are fixed. The FIFO access gating and synthetic transport test
  provide the next functional evidence rather than another warning-count
  cleanup loop.

## Evidence and next action

See `evidence/phase-07-step-04/README.md`, the candidate manifest, routed
CDC/timing/DRC reports, endpoint counts, Vivado logs, and the two simulation
reports referenced there. No PYNQ programming, DMA run, or microphone test was
performed in 7.4. No microphone connection is needed for the synthetic test;
the four microphones must be confirmed before the prolonged physical capture
step.
