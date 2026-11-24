#!/usr/bin/env bash
# Build PYNQ v3.1.2 Base with PCM, the PL HDMI marker, and AR2 buzzer pulse.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 /path/to/PYNQ-v3.1.2 [output-directory]" >&2
    exit 2
fi

HW_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYNQ_SOURCE="$(cd "$1" && pwd)"
PYNQ_COMMIT="3c77124d86bab65ac7bb6beb0aa66e13c83508f2"
PYNQ_HLS_CACHE_SOURCE="${PYNQ_HLS_CACHE_SOURCE:-$PYNQ_SOURCE/boards/ip/hls}"
VIVADO_BIN="${VIVADO_BIN:-/home/siriricomun/tools/Xilinx/Vivado/2024.2/bin}"
VITIS_HLS_BIN="${VITIS_HLS_BIN:-/home/siriricomun/tools/Xilinx/Vitis_HLS/2024.2/bin}"
BUILD_ROOT="${2:-$HW_REPO/../builds/phase11-combined-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd)"
if [[ -e "$BUILD_ROOT/pynq" || -e "$BUILD_ROOT/base.bit" ]]; then
    echo "Refusing to reuse a build directory containing a project or bitstream: $BUILD_ROOT" >&2
    exit 2
fi

actual="$(git -C "$PYNQ_SOURCE" rev-parse HEAD)"
if [[ "$actual" != "$PYNQ_COMMIT" ]]; then
    echo "Expected PYNQ $PYNQ_COMMIT, found $actual" >&2
    exit 2
fi
if [[ ! -d "$PYNQ_HLS_CACHE_SOURCE" ]]; then
    echo "PYNQ HLS cache directory does not exist: $PYNQ_HLS_CACHE_SOURCE" >&2
    exit 2
fi

mkdir -p "$BUILD_ROOT/pynq"
git -C "$PYNQ_SOURCE" archive "$PYNQ_COMMIT" boards/Pynq-Z2/base boards/ip \
    | tar -x -C "$BUILD_ROOT/pynq"
BASE="$BUILD_ROOT/pynq/boards/Pynq-Z2/base"

# This Base Tcl source was generated with Vivado 2024.1. Permit Vivado 2024.2
# to open and upgrade the isolated copy; the caller's PYNQ source is untouched.
python3 - "$BASE/base.tcl" "$BASE/vivado/constraints/base.xdc" \
    "$BASE/build_bitstream.tcl" "$BASE/build_ip.tcl" \
    "$PYNQ_HLS_CACHE_SOURCE" <<'PY'
from pathlib import Path
import shutil
import sys

tcl = Path(sys.argv[1])
text = tcl.read_text()
old = 'set scripts_vivado_version 2024.1'
if text.count(old) != 1:
    raise SystemExit('Pinned PYNQ base.tcl version marker was not found exactly once')
tcl.write_text(text.replace(old, 'set scripts_vivado_version 2024.2', 1))

xdc = Path(sys.argv[2])
text = xdc.read_text()
start, end = '## HDMI TX\n', '## Raspberry PI \n'
if text.count(start) != 1 or text.count(end) != 1:
    raise SystemExit('Pinned PYNQ Base HDMI TX constraint section was not found exactly once')
_, section = text.split(start, 1)
tx, _ = section.split(end, 1)
xdc.write_text('# Minimal Phase 11 constraints: HDMI OUT only.\n' + start + tx)

build_tcl = Path(sys.argv[3])
text = build_tcl.read_text()
needle = 'set_property strategy Performance_Auto_1 [get_runs impl_1]\n'
if text.count(needle) != 1:
    raise SystemExit('Pinned PYNQ Base implementation strategy command was not found exactly once')
build_tcl.write_text(text.replace(
    needle, needle + 'set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE RuntimeOptimized [get_runs impl_1]\n', 1))

# HDMI IN and both trace analyzers are removed from the Block Design before
# synthesis. Only the HDMI OUT color conversion and pixel unpack HLS cores are
# used by the retained video path.
hls_tcl = Path(sys.argv[4])
text = hls_tcl.read_text()
old = 'set ip {color_convert pixel_pack pixel_unpack trace_cntrl_32 trace_cntrl_64}'
if text.count(old) != 1:
    raise SystemExit('Pinned PYNQ HLS IP list was not found exactly once')
hls_tcl.write_text(text.replace(old, 'set ip {color_convert pixel_unpack}', 1))

# The generated Base Tcl still parses the full shell before the prune pass, so
# Vivado needs catalog metadata for its soon-to-be-removed HLS instances. Reuse
# packaged IP from the selected cache, which must correspond to the pinned
# PYNQ commit; never run Vitis HLS for pixel_pack or either trace controller.
hls_cache_root = Path(sys.argv[5])
for name in ('color_convert', 'pixel_pack', 'pixel_unpack',
             'trace_cntrl_32', 'trace_cntrl_64'):
    source_hls = hls_cache_root / name / 'solution1/impl/ip'
    target_hls = (Path(sys.argv[1]).parents[2] / 'ip/hls' / name
                  / 'solution1/impl/ip')
    if source_hls.is_dir():
        shutil.copytree(source_hls, target_hls, dirs_exist_ok=True)
    if name in ('color_convert', 'pixel_unpack'):
        report = (hls_cache_root / name / 'solution1/syn/report'
                  / f'{name}_csynth.rpt')
        if report.is_file():
            target_report = (Path(sys.argv[1]).parents[2] / 'ip/hls' / name
                             / 'solution1/syn/report' / report.name)
            target_report.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(report, target_report)
    elif not list(target_hls.glob('*.zip')):
        raise SystemExit(
            f'Missing cached package for unused Base HLS IP {name}; '
            'refusing to compile an IP that will be removed')
PY

export PATH="$VIVADO_BIN:$VITIS_HLS_BIN:$PATH"
cd "$BASE"
make hls_ip >"$BUILD_ROOT/hls.log" 2>&1
make block_design >"$BUILD_ROOT/base_block_design.log" 2>&1
vivado -mode batch -source "$HW_REPO/scripts/add_phase11_pcm_to_pynq_base.tcl" \
    -tclargs "$BASE/base/base.xpr" "$HW_REPO" >"$BUILD_ROOT/phase11_augmentation.log" 2>&1
vivado -mode batch -source "$HW_REPO/scripts/prune_phase11_base_to_camera.tcl" \
    -tclargs "$BASE/base/base.xpr" >"$BUILD_ROOT/phase11_prune.log" 2>&1
make bitstream >"$BUILD_ROOT/bitstream.log" 2>&1
make check_timing >"$BUILD_ROOT/check_timing.log" 2>&1
vivado -mode batch -source "$HW_REPO/scripts/report_phase11_combined.tcl" \
    -tclargs "$BASE/base/base.xpr" >"$BUILD_ROOT/reports.log" 2>&1

cp base.bit base.hwh "$BUILD_ROOT/"
cp -r base/phase11_reports "$BUILD_ROOT/"
sha256sum base.bit base.hwh >"$BUILD_ROOT/sha256.txt"
cat >"$BUILD_ROOT/build-manifest.txt" <<EOF
PYNQ commit: $PYNQ_COMMIT
PYNQ HLS cache source: $PYNQ_HLS_CACHE_SOURCE
Vivado: $(vivado -version | head -1)
HW repository commit: $(git -C "$HW_REPO" rev-parse HEAD)
PCM source: acoustic_pdm_pcm_continuous_control
PCM control AXI-Lite: 0x43C80000
Marker GPIO AXI-Lite: 0x43C90000
PL video marker: acoustic_video_marker after pixel_unpack and before HDMI OUT
Marker shape: square range check; radius is half-width and half-height in pixels
Active buzzer output: AR2/U13, AXI-Lite base 0x43CA0000, one-shot at FCLK3 100 MHz
Active buzzer pulse default: 5 ms (500000 FCLK3 cycles); command is not periodic
Active buzzer registers: command 0x00, width 0x04, status 0x08, start tick 0x0C/0x10
Marker CDC: two ASYNC_REG stages; false path only from FCLK3 to first-stage D pins
Marker CDC report: see phase11_reports/cdc.rpt; source-to-sync path is excluded intentionally
DMA AXI-Lite: 0x40400000
Minimal Block Design: PS7, HDMI OUT/VDMA on HP0, four-channel PCM/DMA on HP2
Removed: HDMI IN, four MicroBlaze IOPs, trace analyzers, and unused Base peripherals
PCM DDR path: HP2 at FCLK3 (100 MHz); video VDMA remains on HP0
Pmod B: reserved for PDM pins defined by pynq_z2_pcm.xdc
Physical AoA calibration: pending; not accepted by this build
PL marker candidate: not board-validated by this build
EOF
echo "Combined candidate written to $BUILD_ROOT"
