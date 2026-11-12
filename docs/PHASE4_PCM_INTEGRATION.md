# Phase 4.4: integrated RAW/PCM acquisition

The new `pdm_pcm_capture.bd` uses `acoustic_pdm_pcm_control` as module reference
`acoustic_capture_0`. It retains the control and stream IP names required by the
contract, and introduces BUILD_ID `B691CC9C9F6249AD938D2063E4767C54`, ABI 1.0 and
capabilities 0xF. The accepted phase-3 RAW sources, BD, wrapper and build script
are preserved separately. This step produces no BIT/HWH candidate.

## Data, storage and control

A common four-bit register samples physical inputs at the established CE event
125 ns after falling PDM. One fabric clock later the filter consumes that vector.
The standalone CIC/FIR remains continuous between blocks and across stream
recovery; its reset follows clock readiness/global reset. It does not follow
block START, CLEAR or the DMA-local reset.

A selected frame enters a 2048-by-129-bit asynchronous XPM FIFO: four 32-bit
channel slots and a final-frame bit. RAW uses only slot0. The 100 MHz serializer
advances to the next frame only after channel3 is accepted in PCM (or slot0 in
RAW). Whole-frame admission avoids per-channel FIFO fragments. WORDS_SENT counts
individual AXI handshakes; FRAMES_PRODUCED counts complete FIFO entries.
CLIP_COUNT counts set channel bits for admitted physical PCM frames. RAW and
pattern report zero clips. Coherent snapshots carry all frame/clip/error counters
across domains using the existing held-bus request/acknowledgement mechanism.

The configured FIFO stores 2048 frames: 8192 PCM payload words or 2048 RAW words.
RAW payload storage is smaller than the separate accepted RAW candidate's
8192-word FIFO. The native FWFT model additionally holds a prefetched frame;
forced exhaustion accepted 2049 full frames before reporting overflow. Capacity
is treated conservatively and the first failure invalidates the whole block.

Pattern output resets its index on accepted START. RAW emits `n` at each PDM CE;
PCM emits `16*n+c` at every 50th PDM sample. It requires CLOCK_READY and bypasses
FILTER_READY. Physical PCM START additionally requires FILTER_READY; the six
startup filter results are excluded. Pattern and physical PCM have the same
cadence but different pipeline delays, since the pattern bypasses the filter.
The physical PCM path adds one sampler clock, the 244-clock MAC, and two producer
pipeline clocks before FIFO write (247 clocks after its selected PDM sample),
followed by FIFO CDC and stream delivery. Linear-phase signal delay remains 65 us.

A rejected busy write preserves the accepted configuration and invalidates the
block. ABORT/errors stop future frame admission while preserving a stalled AXI
word. The DMA primary reset resets FIFO/serializer locally, retaining identity,
configuration, clock, settled filter and sticky errors. CLEAR is permitted only
idle with an empty stream and then clears counters/errors. Filter scheduler
loss/overrun during physical PCM is reported as overflow and invalidates capture.

## Block design and timing constraints

`python scripts/simulate_pdm_pcm_capture.py --suite stream` and `--suite registers`
run standalone native XSim suites. To recreate the separate BD without synthesis:

```
vivado -mode batch -source scripts/create_pdm_pcm_capture_bd.tcl
```

Vivado 2024.2.2 validated the BD, generated its wrapper, and checked DMA settings:
simple S2MM, 23-bit length, 32-bit stream/master, PS HP0=64. The DMA's primary
stream reset connects to the capture local recovery port. GP0 controls the
capture/DMA registers; the S2MM master reaches DDR through HP0. The saved control
clock interface resolves to 100 MHz. The source replay explicitly adds module
sources before loading module references.

`pynq_z2_pcm.xdc` retains the Pmod pinout. `pynq_z2_pcm_timing.xdc` adapts the
accepted conditional I/O envelope to the shared sample register, adds the new
filter-ready first-stage synchronizer, and bounds held configuration/status
buses. No blanket clock exceptions were added. Actual endpoint coverage, resource
mapping and routed setup/hold remain checks for step 4.6; BD validation cannot
establish them.

## Digital evidence and limits

The stream suite verified 17 successful blocks and 348,497 exact words. PCM and
RAW patterns cover N=1,2,17,4096,65536. Physical RAW and physical PCM use known
constant bits to check selected-source routing, sign extension and channel clips.
PCM pattern stress uses CE accelerated by ten to exercise the largest blocks;
physical PCM and the native-clock top use the nominal CE cadence. Separate tests
verify TREADY stalls, final-TLAST blocking of DONE, overflow, abort with mic1
stalled after mic0 handshakes, invalid commands/configuration, local recovery and
global reset. The initial failed stream run caught a testbench configuration
left on physical source before a pattern recovery test; the corrected complete
suite passed and both runs are retained.

The full-control suite instantiates the real clock RTL and native MMCM model,
waits its 48,000-PDM-cycle warmup, and checks identity, AW/W separation, held B/R,
WSTRB, malformed accesses, readiness and per-block counters. Five successful
captures checked 165 more stream words. It verifies rejection before physical
filter readiness, pattern bypass, preservation through START/CLEAR/local stream
reset, and readiness reset on clock disable.

These suites exercise the native XPM FIFO and emulate the DMA's local reset
input. They do not simulate complete DMA-to-DDR writes or prove board operation.
Those remain part of the candidate/board work. Summary, hashes and evidence paths
are in [phase4-step4-verification.json](phase4-step4-verification.json); the SW
interface target is [pcm-hardware-interface.json](pcm-hardware-interface.json).

Warnings were reviewed by impact: XPM assertion reporting is intentional; legacy
XADC IP/source warnings concern the read-only PS template; inherited negative
DDR-skew settings remain for the build/board review. The read-only reset-polarity
warning did not change the effective value, checked by Tcl. Initial clock metadata
resolved to 100 MHz in the saved BD. AXI-Lite SmartConnect WRAP warnings concern
unsupported burst traffic not generated by these single-register accesses. No
candidate BD validation error occurred.
