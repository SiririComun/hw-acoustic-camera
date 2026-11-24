# Phase 11 pulsed-source extension

This branch adds a programmable, one-shot active-buzzer driver to the existing
Phase 11 PCM/video candidate. It leaves the four-channel PCM RTL and its sample
ordering unchanged.

## PL addition

`acoustic_buzzer_pulse` runs from FCLK3 at 100 MHz and drives PYNQ-Z2 Arduino
digital AR2 (`U13`) as a 3.3 V logic output. The output is intended to switch
the existing transistor stage; it does not power a buzzer directly. The
historical circuit diagram is in the SW repository at
`docs/LEGACY_SOUND_LOCALIZER.md`. Check the installed transistor's package and
pinout against its own datasheet before wiring it.

The PL emits one bounded high pulse for each start command. Its reset width is
500,000 clocks (5 ms); software can set 10 ns through 1 s. There is no automatic
retrigger or volume change. AXI-Lite base address is `0x43CA0000`:

| Offset | Access | Meaning |
|---|---|---|
| `0x00` | W | bit 0 starts; bit 1 aborts; bit 2 clears done/error |
| `0x04` | R/W | pulse width in 100 MHz FCLK3 cycles |
| `0x08` | R | bit 0 active; bit 1 done; bit 2 error |
| `0x0C` | R | PL cycle counter at the accepted start command, low 32 bits |
| `0x10` | R | same counter, high 32 bits |

The PL timestamp marks the electrical command edge. It is not an acoustic
emission timestamp and is not synchronized to the PCM frame counter.

## Arrival processing

The initial software API estimates each channel's pulse-envelope arrival from
four-channel PCM, reports all six pairwise TDoAs, and fits those differences to
the configured planar array. This is the far-field plane-wave approximation
for the complete array. The common buzzer launch and filter delays cancel in
the differences. The result is a direction candidate; it does not calculate
absolute ToA range or solve a near-field source position.

Absolute ToA/range would need a common, measured time relationship from the PL
start counter to PCM frames, along with calibrated buzzer turn-on and acoustic
delay. That relationship is not part of this extension. Mic-to-PCM mapping and
microphone coordinates remain explicit software configuration; raw PCM
columns are never reordered in storage or capture.

## Build and evidence

Run `scripts/build_phase11_combined.sh` from this repository with the pinned
PYNQ source and Vivado 2024.2. If the source checkout has no generated HLS
packages, set `PYNQ_HLS_CACHE_SOURCE` to a package cache generated from that
same PYNQ commit. The script emits a matched `base.bit`/`base.hwh`
pair, timing/DRC/CDC/I/O reports, hashes, and logs. This is a PC build result;
it does not establish that the buzzer circuit, tone frequency, pulse audibility,
PCM identity, or physical angular response has been validated on a board.

The combined AXI-Lite layout is PCM `0x43C80000`, marker GPIO `0x43C90000`,
buzzer `0x43CA0000`, and DMA `0x40400000`.

## Combined pulsed candidate build (2026-11-24)

Vivado 2024.2.2 completed the combined PCM, PL marker, and buzzer build from
HW commit `48e112ff505ca73d6cb6ea14a261a93d464b6684` on branch
`feat/four-mic-pulse-toa`, using PYNQ v3.1.2 commit
`3c77124d86bab65ac7bb6beb0aa66e13c83508f2`. The matched artifacts and all
build logs are in
`builds/phase11-combined-pulse-toa-20261124-r3/` in the workspace.

The output hashes are BIT
`dbd128325e7d2fc0dbf4dfed7faae226767e46a858e1da2d362c36d72062aa62` and HWH
`779bbb1b6e80b89d53c231ec29789de26b4f83a3ec4c15ea0e191f20c9962b17`; the
stored SHA-256 check passes for both. The HWH maps the buzzer at `0x43CA0000`,
and Vivado reports `buzzer_pulse_o` on U13/AR2. The routed timing summary has
no failing constrained setup or hold endpoints (WNS `+1.956 ns`, WHS
`+0.030 ns`); the build's `check_timing` gate passed. DRC reports no errors,
with warnings/advisories retained in `phase11_reports/drc.rpt`.

This result is a PC build only: the BIT/HWH pair has not been loaded or tested
on the board, and buzzer audibility, pulse timing against PCM, microphone
channel identity, and physical ToA/TDoA direction are unvalidated. The timing
reports also show I/O outputs without delay constraints and an HDMI serial
generated-clock warning; see `phase11_reports/check_timing.rpt` and
`phase11_reports/timing_summary.rpt` before making any external timing claim.
