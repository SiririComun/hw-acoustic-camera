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
PYNQ source and Vivado 2024.2. The script emits a matched `base.bit`/`base.hwh`
pair, timing/DRC/CDC/I/O reports, hashes, and logs. This is a PC build result;
it does not establish that the buzzer circuit, tone frequency, pulse audibility,
PCM identity, or physical angular response has been validated on a board.

The combined AXI-Lite layout is PCM `0x43C80000`, marker GPIO `0x43C90000`,
buzzer `0x43CA0000`, and DMA `0x40400000`.
