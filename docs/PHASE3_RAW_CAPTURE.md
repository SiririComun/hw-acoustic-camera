# Phase 3 RAW capture — source, FIFO and stream core

Step 3.2 implements the reusable sampling source; step 3.3 adds and simulates
the finite-block producer, FIFO, AXI Stream, counters and errors. The accepted
board overlay is still phase-2 clock/control. AXI-Lite/DMA integration and the
Python capture API belong to step 3.4.

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

## Step 3.3: capture core

`acoustic_pdm_raw_capture` wraps the source and an actual `xpm_fifo_async`,
8192x33 by default, block RAM, FWFT, two synchronization stages. Payload and
TLAST travel in the same FIFO word from 24 MHz to the 100 MHz AXI Stream port.
TKEEP is always 0xF. The single writer reserves a word at the sample CE before
its registered source enqueues it on the next write-clock edge. FIFO full
invalidates and stops the entire block; it does not pause the sampling clock.

The command pins are pulses in the 100 MHz domain, not an AXI-Lite slave.
START latches N/source into a held mailbox; a toggle crosses into 24 MHz.
One coherent snapshot mailbox returns frames produced, overflow, producer
quiescence and command epochs. Final DONE waits for the final TLAST handshake
and the final producer snapshot. WORDS_SENT counts actual handshakes.
These ports will be mapped to the shared register contract in step 3.4.

START validates idle/error/ready/length (1..65536) and FIFO state. Error bits
are configuration=0, overflow=1 and aborted=2. The AXI-Lite adapter must pulse
`config_error_i` for forbidden configuration writes or selections. ABORT/errors
stop future production while maintaining an already offered AXI word unchanged.
An errored active block remains BUSY until stream recovery; DONE stays zero.

The future DMA's `s2mm_prmry_reset_out_n` must connect to `stream_resetn_i`.
Local recovery clamps the stream, resets the source/FIFO for eight stable write
clock cycles, waits for both XPM reset-busy signals, then completes a request/ack
handshake. It preserves sticky errors and diagnostics until an idle CLEAR.
CLEAR uses a generation-tagged snapshot to prevent stale producer state from
reappearing after counters/errors are cleared. No clock-enable, identity or
configuration outside the core is reset. Global reset clears the whole core.
BUSY also covers startup/local reset and the brief CLEAR handshake.

Run the targeted simulation without repeating the MMCM warmup suite:

```bash
python3 scripts/simulate_pdm_raw_source.py --suite stream
```

This uses ideal 24/100 MHz test clocks and the real XPM model with depth 8192.
It checks exact patterns at N=1,2,17,4096,65536, physical RAW padding, interleaved
TREADY, held final TLAST, overflow at capacity, ABORT, invalid arguments/commands,
local recovery followed by exact captures and global reset during a held word.
AXI stability is monitored even after errors; logs/CSV contain 11 successful
captures and fault/recovery assertions. The XPM notice about SIM_ASSERT_CHK=1
only announces enabled simulation diagnostics; it is accepted without cleanup.

The core is not yet instantiated in the production BD. No register-bank mapping,
DMA soft-reset behavior, board acquisition or routed timing is certified here.
The next step connects this tested core, the register bank and the DMA.

## Step 3.4 — register bank and DMA integration

`acoustic_pdm_raw_control.vhd` joins the accepted clock, the RAW register adapter
and the simulated capture core. New BUILD_ID: `9fd0ddcdb84d4c52910805339c28ce2e`,
CAPABILITIES `0xB`, MAX_FRAMES 65536. The phase-2 control and XADC BD are preserved.
The adapter keeps independent AXI AW/W channels, byte strobes, held B/R responses
and application errors in ERROR_FLAGS (malformed/RO accesses return SLVERR).
Configuration writes during BUSY are rejected without changing configuration.

Run `vivado -mode batch -source scripts/create_pdm_raw_capture_bd.tcl` to prepare
and validate the new `src/bd/pdm_raw_capture.bd` and wrapper. This script does not
launch synthesis, implementation or bitstream generation. The validated design
uses `axi_dma_audio`, simple S2MM, 32-bit stream/memory, 23-bit length, HP0 DDR and
the primary S2MM reset only for local stream recovery. AXI-Lite and clock control
remain outside that reset. Control/DMA addresses are 0x43C00000/0x40400000;
software obtains actual addresses and DMA parameters from the loaded HWH.

`python3 scripts/simulate_pdm_raw_source.py --suite registers` checks AXI-Lite plus
the native 8192-word XPM core using ideal clocks: 3 successful blocks, malformed
accesses, strobes, PCM/length rejection, BUSY rejection, abort/reset/CLEAR and
subsequent capture. The accepted clock simulation need not be repeated unchanged.

Step 3.5 still must build the identified BIT/HWH pair, add and verify scoped RAW
input/CDC timing constraints against actual synthesis endpoints (see architecture
handoff 3.1), review routed timing/DRC, and perform board pattern/error checks.
The inherited phase-2 XDC alone does not close timing for DATA. No DATA false
paths or global asynchronous clock groups are authorized. No hardware acceptance
or external timing measurement is implied by BD validation or ideal simulation.
