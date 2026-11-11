# Release a phase-1 hardware candidate

The selected build already exists. Publishing it does not require another Vivado
run. Preserve the original build manifest and the BIT/HWH from that same run.

1. Copy `pynq_z2.bit`, `pynq_z2.hwh`, and `build-manifest.json` from its complete
   `artifacts/` directory into `bin/`. Keep the reviewed implementation summary
   in `bin/implementation-review.json`; it must identify the same source and run.
2. Generate `bin/SHA256SUMS.txt` for those four files. Update release notes.
3. Commit packaging changes on the phase branch. RTL, BD, constraints, build
   scripts, hooks and submodule pins must match the manifest's source commit.
   The validator permits only `bin/`, `docs/`, README, .gitignore, the two workflow
   files and the release validator to differ. A changed hardware input requires
   a new build; documentation or publication changes alone do not.
4. Create a new annotated candidate tag, for example `v0.1.0-rc.1`. Do not move
   previously published tags or replace release assets.
5. Validate and stage outside the repository:

   ```bash
   python3 scripts/validate_release.py --tag v0.1.0-rc.1 \
     --output-dir /path/to/fresh/release-assets
   ```

6. Push the phase branch and then that specific tag. GitHub Actions validates the
   tagged commit and creates a prerelease with five assets. It does not invoke
   Vivado. Publishing fails if the release already exists; rerunning a successful
   publication is not an update mechanism.
7. Confirm the workflow result, release target and downloaded hashes. Record the
   tag, packaging commit, built source commit and manifest SHA-256 for the SW repo.

The current candidate is XADC only and untested on the board. Full reports/XSA
remain in the workspace build directory; their hashes are in the build manifest.
The compact implementation review is published separately and does not rewrite
that manifest's original `not_performed_by_packager` review field.

The existing VHDL syntax workflow now covers `main`, `phase/**` and `feat/**`.
It is a syntax check, not a functional test or an FPGA implementation run.
