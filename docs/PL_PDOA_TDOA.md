# Phase 13 — PL PDoA/TDoA and dual marker

Status: the correlation tracker and AOA3 completed-result sequence are present
in the current RTL. The workspace contains a generated BIT/HWH pair at
`builds/phase16-aoa3-result-sequence-timingfix-20261127T`. All 20 entries in
that build's `source-sha256.txt` match the feature HW worktree. In this integration
worktree, 19 entries match byte for byte; `src/con/pynq_z2_pcm.xdc` differs only
in a corrected comment added after the build, with its XDC commands unchanged. The
build manifest says physical AoA calibration is pending and the PL marker was
not board-validated by that build. These build records do not establish camera
accuracy or physical acceptance.

## Signal path

The four-channel PCM stream remains in channel order 0, 1, 2, 3. An AXI-Stream
tee sends the original words to the existing DMA and to the PL estimator; the
estimator is permanently ready, so it adds no new backpressure or sample
mutation. The tracker and pulse driver run from FCLK3 at 100 MHz. The AR2
buzzer output edge is connected internally to the tracker and is also kept on
the external AR2 pin.

PDoA uses the PS-programmed DDS phase increment and a configurable I/Q frame
window. A per-channel DC tracker removes the slow PCM baseline before coherent
integration. The PL obtains four edge-pair phase differences with an iterative
CORDIC, averages the opposite edges, converts them to provisional direction
cosines, and projects them to pixels. The pair map is 0→1 and 2→3 for x,
0→2 and 1→3 for y. R13 PCM showed coherent lags in these pairs; the prior
3→2, 3→0 and 2→1 map inverted or mixed axes. The square geometry, target frequency,
sound speed and pixel map are supplied at runtime by the PS. AXI `TLAST` marks
DMA descriptor ends; the tracker advances its acoustic frame clock after each
complete group of four channel words, so normal 4096-frame descriptors no
longer stall the 128-frame PDoA windows.

TDoA arms at the AR2 pulse edge. Per-channel first-difference envelopes and
background levels locate a shared active window. Their four threshold crossing
offsets remain available at `0xAC–0xB8` for diagnostics only: R13 demonstrated
that amplitude-dependent threshold crossing times are not reliable acoustic
delays. After all four channels cross, PL captures 64 simultaneous PCM frames.
One pipelined multiplier correlates first-difference samples across each
opposing pair over a common 48-frame segment and lags −8…+8 frames. This
bounded search gives four pair delays in PCM frames; a multi-cycle datapath
then forms horizontal and vertical directions in Mic1..Mic4 / PCM0..PCM3 order:

```text
dx = (lag(0,1) + lag(2,3)) / 2
dy = (lag(0,2) + lag(1,3)) / 2
ux = dx * sound_speed / (sample_rate * baseline_x)
uy = dy * sound_speed / (sample_rate * baseline_y)
```

Correlation removes the channel-amplitude bias that dominated R13. The search
range is still provisional: with the configured 50 mm baseline at 48 kHz, a
physical pair delay should be at most about seven frames. The existing unit
disk check rejects impossible combined directions. The individual threshold
crossing offsets remain relative to the electrical pulse edge; they do not
provide calibrated absolute range. Timeouts and hold times use 48 kHz frames.
Correlation accuracy, channel geometry, and room reflection effects still
require board measurement with the generated candidate.

Both directions use a provisional linear image mapping, `center + direction ×
pixels_per_unit`. It makes the point respond across the frame but is not a
camera calibration. The default 50 mm baselines and channel map are provisional.
PDoA currently checks channel magnitude and the physical unit-disk bound; it
does not use diagonal pairs as a residual-quality gate. The TDoA window gate
still depends on per-channel envelope thresholds, while its delay estimate
comes from bounded correlation. Reflections and the periodic tone can still
bias the estimate. No angular accuracy or tolerance is claimed.

## PS runtime control

`acoustic_pcm_iq_tracker` is mapped at `0x43CB0000`. AXI-Lite parameters are
written by the PS and consumed by the PL. To change a configuration, the helper
stops tracking, writes the complete set, clears state, and restarts; a new
bitstream is not needed for these values.

| Offset | R/W | Purpose |
|---:|:---:|---|
| `0x00` | R/W | Enable bit 0, clear bit 1, PDoA bit 2, TDoA bit 3 |
| `0x04` | R/W | 32-bit DDS phase increment for the selected fixed tone |
| `0x08` | R | Tracker enable, I/Q result-valid, stream error and I/Q sequence |
| `0x0C` | R/W | I/Q integration window, 16–2048 frames; reset default 128 |
| `0x10–0x2C` | R | Four-channel I/Q sums, in unchanged PCM order |
| `0x30–0x50` | R | PCM frame/cycle counters and electrical pulse reference |
| `0x54–0x60` | R/W | Four onset margins; effective envelope margin is `max(1500, register/32)` PCM counts |
| `0x64` | R/W | Minimum `abs(I)+abs(Q)` magnitude for PDoA validity |
| `0x68` | R/W | Maximum trigger-to-onset search interval in PCM frames |
| `0x6C–0x78` | R/W | PDoA/TDoA geometry conversion coefficients, signed Q16 |
| `0x7C–0x88` | R/W | Pixel center and pixels per direction unit |
| `0x8C–0x98` | R | PDoA valid flag, direction Q16 and packed pixel `(x,y)` |
| `0x9C–0xA8` | R | TDoA valid flag/event count, direction Q16 and packed pixel |
| `0xAC–0xB8` | R | Four envelope crossing offsets from the last pulse, diagnostic only |
| `0xBC–0xC4` | R | Horizontal/vertical correlation delay in frames and event count |
| `0xC8` | R/W | TDoA result hold time in PCM frames; zero means no expiry |
| `0xCC–0xD8` | R | Four signed pair correlation lags: 0–1, 2–3, 0–2, 1–3 |
| `0xDC` | R | Correlation energy quality flag, bit 0 |
| `0xE0` | R | `0x54444F31` (`TDO1`) correlation register-map identifier |
| `0xF8` | R | Sequence of the completed PDoA projection, rather than the newer I/Q window |
| `0xFC` | R | `0x414F4133` (`AOA3`) completed-result-sequence identifier |

The AOA3 result-sequence registers above are included in the source set and
generated BIT/HWH pair identified in the status note. Older AOA2 BIT/HWH pairs
do not contain them; the bounded PS runner retains its compatibility fallback
to the I/Q sequence, which can briefly precede the projected pixel. The
continuous `aoa_live.py` service requires an AOA3 pair for coherent PDoA output.

The PS sets the independent marker visibility mode to none, PDoA, TDoA or both.
PDoA is red and TDoA is cyan; each is a radial multi-level glow. The dual AXI
GPIO at `0x43C90000` has one 32-bit config word per point, with bit 31 enable,
bits 25:20 radius, bits 19:10 y and bits 9:0 x. The glow uses an octagonal
distance approximation to keep the pixel-clock path small. The PL performs the
HDMI pixel composition. The PS forwards PL-produced pixels but does not
calculate AoA.

## Build and verification

The PYNQ-Z2 candidate was generated with `scripts/build_phase11_combined.sh`,
using the pinned PYNQ v3.1.2 source and Vivado 2024.2. The matched `base.bit`
and `base.hwh`, logs and reports are stored in the workspace `builds/`
directory. The result manifest identifies the AOA3 tracker and records that
physical AoA calibration is pending and the PL marker was not board-validated.
The current tracker and marker testbenches are present in `sim/`; no simulation
or board-validation result is claimed here. Build/source correspondence does
not establish physical channel identity, room acoustic behavior or angular
calibration.
