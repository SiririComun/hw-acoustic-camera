# Phase 7.4 — Static CDC review of the continuous PCM candidate

Date: 2026-11-17 (America/Bogota). Status: **static review completed; the
candidate is not yet cleared for board programming**. Phase 6 remains open at
6.3; this review does not change that status or integrate video.

## Scope and evidence

Reviewed the routed Vivado 2024.2.2 reports for `pdm_pcm_continuous_capture`
from `evidence/phase-07-step-02/candidate/reports/`, the candidate RTL and
constraints in `src/hdl/` and `src/con/`, and the SG driver/interface contract.
The source candidate is HW commit `c5d0ef32d28bf30624b9094fd6f87a244be505b7`
(BUILD_ID `7A2C7F017A2C4E7D8F70070100000001`).

No RTL or constraints were changed in this review. No Vivado build, simulation,
board programming, DMA run, or microphone test was performed. The existing
simulation and host evidence remains the evidence from steps 7.2 and 7.3; it
does not prove metastability behavior or DMA operation on the board.

## Disposition

The report lists CDC-1: 459 Critical, CDC-10: 4 Critical, CDC-11: 2 Critical,
CDC-15: 389 Warning, and CDC-3: 9 Info. The report labels the reviewed clock
pair `clk_fpga_0` to `clk24_mmcm` as `Safely Timed`; this label and the rule
counts are not, by themselves, a clean-CDC determination.

### Held configuration and snapshot buses — documented bundled-data crossings

Most CDC-1/CDC-15 endpoints are data buses sampled under a separately
synchronized control event:

- `block_length`, `block_pattern`, `block_pcm`, and `continuous_mode` are set
  together with the 100 MHz `start_req` toggle and remain stable while a run is
  active. The toggle passes through `start_pipe`; the 24 MHz side consumes the
  configuration on `start_pulse`. `pynq_z2_pcm_continuous_timing.xdc` bounds
  the configuration paths to `clk24_mmcm` with a 41.667 ns datapath-only
  maximum delay.
- The 132-bit `snapshot_data` bus is registered in the 24 MHz domain and held
  until the synchronized acknowledgement returns. `snapshot_req_pipe` crosses
  the request to 100 MHz; the XDC bounds snapshot-data paths to `clk_fpga_0`
  with a 15 ns datapath-only maximum delay.

These are intentional bundled-data crossings, not per-bit synchronizers. The
current RTL and constraints provide a plausible handshake and timing basis for
their disposition. Preserve the hold-until-ack behavior and both bounds; if
either protocol or constraints change, re-review these paths. The report still
contains the Critical/Warning classifications and is not to be described as
CDC-clean on this basis alone.

### CDC-3 and CDC-11 — synchronizer topology

The nine CDC-3 paths terminate at first-stage synchronizer registers carrying
`ASYNC_REG`. The two CDC-11 paths originate at the XPM FIFO reset controller
and fan out to the XPM write-reset synchronizer and the local
`read_busy_pipe[0]` synchronizer. The local chain is marked `ASYNC_REG`; both
reported destinations are synchronization stages rather than direct
functional consumers. This topology is consistent with independent reset or
status synchronization, but the Critical classification remains recorded and
must be rechecked if the FIFO implementation or reset path changes.

The RTL holds FIFO reset for eight write-clock cycles and waits for write-busy
and synchronized read-busy to clear before acknowledging recovery. AMD's
7-series/Zynq-7000 XPM FIFO guide requires waiting for the busy outputs to
deassert after reset and not toggling `wr_en`/`rd_en` while reset or busy is
asserted ([UG953, XPM_FIFO_ASYNC](https://docs.amd.com/r/2022.1-English/ug953-vivado-7series-libraries/XPM_FIFO_ASYNC)).

### CDC-10 — two status paths need a design disposition before programming

1. `stop_level` is combinationally decoded from `errors` and `state` and feeds
   `stop_pipe[0]`. It can affect producer activity in the 24 MHz domain. The
   current artifacts do not prove that transitions cannot create a short
   spurious level. Register the source status or supply a design-specific
   timing/glitch argument before accepting this path.
2. `filter_ready_o` is combinationally decoded from `settle_count = 6` and
   `overrun = 0`, then feeds `filter_ready_pipe[0]`. A transient decode could
   report readiness early to the AXI domain. This matters for physical
   microphone capture. Register the readiness indication in its source domain
   or prove the transition safe before accepting this path.

The remaining CDC-10 paths have intentional fail-safe/reset behavior:

- `reset24_async` asserts the reset pipe asynchronously from PS reset or loss
  of MMCM lock; the two-stage `reset24_pipe` releases it synchronously to
  `clk24`. The bundled phase-4 constraint file `pynq_z2_pcm.xdc` already
  false-paths only the `reset24_pipe` asynchronous `CLR` pins.
- `clock_ready_24m_o` is gated by `reset24n` before its two-stage 100 MHz
  synchronizer. This gate forces readiness low immediately on reset; the
  clock-ready source is not asserted until its warm-up interval completes.
  Keep the fail-closed behavior and re-review if the reset or warm-up sequence
  changes.

All four CDC-10 entries are reported with false-path exceptions to their
intended first-stage or asynchronous-reset pins. Those exceptions do not by
themselves establish that the two status signals above are glitch-free.

## Related implementation limits

The routed timing report has WNS +2.235 ns and WHS +0.016 ns with no failing
setup/hold endpoints. `check_timing` reports one low-severity missing
output-delay constraint on `pdm_clk_o`. These are not CDC findings, but remain
part of candidate release review.

The DRC report has no errors but includes REQP-1839/1840 asynchronous-control
warnings on BRAM ports; the REQP-1839 report limit was reached. The candidate
gates FIFO read/write activity with reset/busy/empty conditions, but this
static CDC review does not close the BRAM-reset warning. Preserve it as an
open reset/implementation disposition before claiming the candidate fully
reviewed.

## Gate and next action

**Do not program this candidate yet.** The bundled configuration/snapshot
crossings and reset synchronizer have a documented basis, but the two CDC-10
status paths and the related BRAM asynchronous-control warnings are not
cleared. The next Phase 7 work should address or justify those findings and
produce current CDC/DRC evidence before the synthetic on-board transport run.
No microphone connection is needed for that synthetic test; the four
microphones will be requested before the later ten-minute physical capture.
