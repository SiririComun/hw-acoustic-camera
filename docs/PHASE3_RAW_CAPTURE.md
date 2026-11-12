# Phase 3 RAW capture — sampling stage

Step 3.2 implements and simulates the reusable sampling source. The accepted
board overlay is still phase-2 clock/control. FIFO, AXI Stream, finite-block
control, error handling, DMA and Python capture are the following steps.

`acoustic_pdm_clock` now exports its existing free-running 24 MHz clock, local
reset and a combinational sample CE. The CE is active before the third 24 MHz
rising edge after the PDM falling edge (125 ns nominal), only after the existing
48000-rising-edge warmup. The existing MMCM/divider/enable/reset behavior is
retained. Phase-2 control maps the additional internal ports to `open`; its public
ports, ABI, BUILD_ID and clock-only capabilities are unchanged. No new candidate
BIT/HWH is supplied by this step.

`acoustic_pdm_raw_source` consumes that CE at 24 MHz. On `block_start_i` it latches
the source and resets the diagnostic index. START has priority over sampling;
if both coincide, the first sample is taken on the following eligible CE.
All four physical inputs are registered together into bits 0..3 of a 32-bit word;
bits 4..31 are zero. Pattern words are the complete 32-bit index, starting at zero
on every START. No PCM conversion occurs.

The source interface is a registered write pulse for a future FIFO, not AXI
Stream. A sample appears after its capture edge; a consumer on the same clock
enqueues it on the next edge. `capture_enable_i=0` stops admission without
destroying the already registered word. The future block controller must reserve
capacity before each CE and provide command CDC, N, TLAST, counters, BUSY and
errors. A reset clears the internal pending word and index asynchronously; the
reset of an eventual AXI interface must be coordinated as described in step 3.1.

## Reproduce the simulation

From the HW repository, with the SW repository as a sibling:

```bash
python3 scripts/simulate_pdm_raw_source.py \
  --vivado-bin /home/siriricomun/tools/Xilinx/Vivado/2024.2/bin
```

`--reference-tool` selects the SW tool explicitly if the checkout is elsewhere.
The runner makes a new directory under `../evidence/phase-03-step-02/`, snapshots
all inputs, generates deterministic four-channel vectors with the standalone SW
tool, compiles VHDL-2008 and UNISIM, and runs XSim. It checks two concurrent suites:

- Source-only: physical sequences and full diagnostic words at N=1,2,17,4096,65536;
  new START after the largest block; source selection latched; disabled admission;
  reset of a pending word; START coincident with CE.
- Actual clock source: real MMCME2_BASE/BUFG models, full warmup, four distinct
  physical sequences, actual sampling offset/cadence against PDM falling edges,
  equal enqueue latency, source-local reset while PDM continues, idle clock disable
  and global reset.

DATA is deliberately poisoned before/after the sampling aperture to reveal early,
late, live or channel-shifted reads. This is a digital test stimulus, not a sensor
electrical model. The independent SW checker verifies exact words, count, order,
cadence, latency and the phase trace. A missing all-pass marker, wrong trace or
command timeout fails the run even if the simulator exits zero.

No synthesis, implementation, timing closure or board operation is run. The
current PDM BD does not yet instantiate the new source or route DATA to it. Input
timing constraints must be attached and inspected when those endpoints are
integrated in the phase-3 candidate; no false-path waiver is added in this step.
The external I/O budget remains conditional, as documented in the architecture
handoff. The actual Vivado BD PDF is due at phase-3 closeout.
