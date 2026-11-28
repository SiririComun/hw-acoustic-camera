# Archived legacy HW project files

This directory preserves 69 tracked files from the earlier standalone XADC
reference and phase-specific PDM designs. The files were moved without changing
their contents. Historical bitstream, HWH, manifests, checksums and reports are
kept as records; their age or size is not a reason to remove them.

## Why these sources are archived

The current camera build imports the pinned PYNQ Base commit
`3c77124d86bab65ac7bb6beb0aa66e13c83508f2`. It creates and prunes the combined
block design through the active Phase 11 scripts in `scripts/`, then adds the
explicit PCM, tracker, buzzer, HDMI marker RTL and current constraints. It does
not read these archived standalone `.bd` files, XADC wrappers, Hog source lists
or the archived reference release as build inputs.

The Python runtime is given an explicit `base.bit`/`base.hwh` pair from the
combined build. The historical `bin/pynq_z2.bit` and `bin/pynq_z2.hwh` remain
here for provenance and are not the current camera overlay pair.

## Historical tooling and reproduction

`Top/pynq_z2/`, the archived block designs and constraints belong to the old
Hog-managed XADC/PDM flow. `scripts/build_reference.py`,
`scripts/export_reference.tcl`, `scripts/validate_release.py` and the archived
release workflow document that older path. The original Hog and Cog gitlinks
were uninitialized in the integration worktree when removed. Their pinned
revisions and source URLs were:

| Tool | Pinned revision | Source |
|---|---|---|
| Hog | `b56d7dec7611851f930abcc685f5cc879d3414d8` | <https://gitlab.com/hog-cern/Hog.git> |
| Cog | `fc07afc4239195f69ae57c34b5507f97129f9f06` | <https://github.com/SiririComun/Cog.git> |

To reproduce the historical flow, check out the relevant historical repository
commit and initialize those exact submodule revisions. Current active RTL and
Tcl files may have changed since that point; this archive alone does not
recreate a historical build environment.

The original XADC README, including its block-diagram discussion and register
map, is retained in [`README_ORIGINAL.md`](README_ORIGINAL.md) with a notice
that its claims describe the historical reference design.
