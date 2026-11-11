# Hardware candidate — legacy XADC reference

This candidate prepares the distribution infrastructure for the acoustic camera.
It contains the existing two-channel XADC design for the PYNQ-Z2. Four-channel
PDM capture, localization, webcam and HDMI integration are not implemented.

- Source commit: `50b98d0ea8863c8cd8665fb6061b8cfb39222e0b`.
- Vivado 2024.2.2; xc7z020clg400-1; implementation at 100 MHz.
- WNS +0.267 ns; WHS +0.016 ns; TNS/THS zero.
- Exact mean calculation pipelined; bypass retained. Averaging modes add three cycles.
- Native shared IP cache enabled for subsequent builds.
- DRC warnings are recorded in `implementation-review.json`, including LUT packing
  and unloaded-net warnings; they have not been independently validated on hardware.

## Assets and identity

`pynq_z2.bit`, `pynq_z2.hwh`, `build-manifest.json`,
`implementation-review.json`, and `SHA256SUMS.txt`.
The original build manifest is preserved byte for byte. Its `source_commit` is
the built source, while the release tag identifies the later packaging commit.
The workflow checks that only packaging/documentation changed between them.
The checksum file covers the other four assets; it does not hash itself.

**Board programming and acquisition have not been validated.** This is a
prerelease for phase-1 distribution integration, not a completed acoustic camera.
There is no runtime PDM BUILD_ID in this legacy design. The new Python package
will pin the release and manifest hash in the next software step.
