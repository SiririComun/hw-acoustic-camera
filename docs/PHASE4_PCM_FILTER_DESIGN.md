# Phase 4.2: PDM-to-PCM filter design

Status: design and integer reference frozen for review; no PCM RTL, bitstream,
or board changes are part of this step. The machine-readable specification is
[`pcm_filter_v1.json`](pcm_filter_v1.json); the software repository keeps the
same file as package data and includes the generator and integer reference.

## Signal chain

All four microphone bits are sampled on one common 2.4 MHz PDM event and mapped
as `0 -> -1`, `1 -> +1`. The chain is:

1. CIC3, differential delay 1, decimation 5: 2.4 MHz to 480 kHz. Its gain is
   125; normalization is included in the FIR scale. Three 32-bit two's
   complement modular integrators and three modular comb stages avoid unbounded
   state without changing the CIC result. The CIC output is bounded by +/-125
   and fits in signed 8 bits.
2. A 61-tap symmetric equiripple FIR at 480 kHz, then decimation by 10 to
   48 kHz. The passband is 0–3 kHz, transition is 3–24 kHz, and stopband is
   24–240 kHz. Coefficients were designed with `scipy.signal.remez`, weights
   `[1, 100]`, and unity-DC normalization.

The FIR history and multiply-accumulate operation consume **every** 480 kHz CIC
sample; only the filtered output is decimated. CIC results occur after PDM
sample indices 4, 9, 14, ...; PCM outputs occur after indices 49, 99, 149, ...
for all channels on the same phase.

## Integer arithmetic

The frozen table has signed 18-bit coefficients, formed as
`C[k] = round_even(h[k] * 2^(23+5) / 125)`. The exact table and its hashes are
in the JSON. Its sum is 2,147,484; its absolute sum is 2,148,648. With CIC
samples bounded by 125, the FIR accumulator magnitude is bounded by
268,581,000. A signed 30-bit accumulator would satisfy that bound; 32 bits are
selected for implementation margin.

After the MAC, divide by 32 using round-to-nearest, ties-to-even; saturate to
signed 24-bit range `[-8,388,608, 8,388,607]`; then sign-extend into the
contract's `int32` PCM representation. Count one clip per saturated channel
sample in an accepted block. Discard output indices 0–5 after reset; index 6
is the first valid output after the FIR has a full 61-sample history and the
CIC startup transient has passed. The linear-phase group delay is 156 PDM
sample periods (65 us, 3.12 PCM frames).

## Offline response analysis

The quantized chain gives:

- Combined 0–3 kHz passband ripple: 0.5912 dB (target <= 1 dB).
- FIR stopband attenuation from 24–240 kHz: at least 69.58 dB.
- Combined attenuation for 45–47 kHz input images: at least 74.11 dB
  (target >= 60 dB).
- Minimum sampled attenuation over all input frequencies from 24 kHz to PDM
  Nyquist: 69.76 dB on a 1,000,001-point grid.
- Combined DC gain: 1.00000016 before any later DC removal.

These are numerical frequency-grid measurements, not a formal continuous
frequency proof. They do not model the exact microphone suffix or its shaped
PDM modulator noise. Electrical margins, clock-pin waveform, and acoustic
response remain for their respective later checks. The full measured response,
alias point, tool versions, coefficient table, and quantization bounds are in
the JSON. The digital RTL/model equivalence work must compare against the same
coefficient hash before hardware integration.

Design references: [ST MP34DT01-M datasheet](https://www.st.com/resource/en/datasheet/mp34dt01-m.pdf),
[ST AN5027 on PDM filtering and decimation](https://www.st.com/resource/en/application_note/an5027-interfacing-pdm-digital-microphones-using-stm32-mcus-and-mpus-stmicroelectronics.pdf),
and [SciPy `remez` documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.remez.html).
