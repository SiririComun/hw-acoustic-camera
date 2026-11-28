#!/usr/bin/env bash
# Build PYNQ v3.1.2 Base with PCM, PL I/Q tracking and marker, and AR2 buzzer pulse.
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

# Vivado may retain its module-ref source override across projects. The R11
# tracker run script used R10's generated tree and silently reused its DCP.
# Pin the override to this build, delete both checkpoint copies, and verify the
# regenerated OOC run after the normal Base wrapper/constraints are loaded.
text = build_tcl.read_text()
needle = 'launch_runs impl_1 -to_step write_bitstream -jobs 4\nwait_on_run impl_1\n'
if text.count(needle) != 1:
    raise SystemExit('Pinned PYNQ implementation launch commands were not found exactly once')
preflight = '''set project_dir [file normalize ./base]
set mref_dir [file normalize [file join $project_dir base.gen sources_1 bd mref]]
if {![file isdirectory $mref_dir]} {error "Missing current-build module-ref directory: $mref_dir"}
set_param ips.modRefOverrideMrefDirPath $mref_dir
set tracker_run_name base_acoustic_pcm_iq_tracker_0_synth_1
set tracker_run_dir [file join $project_dir base.runs $tracker_run_name]
set tracker_run_dcp [file join $tracker_run_dir base_acoustic_pcm_iq_tracker_0.dcp]
set tracker_gen_dcp [file join $project_dir base.gen sources_1 bd base ip base_acoustic_pcm_iq_tracker_0 base_acoustic_pcm_iq_tracker_0.dcp]
reset_run [get_runs synth_1]
reset_run [get_runs impl_1]
file delete -force $tracker_run_dcp $tracker_gen_dcp
'''
postflight = '''
set tracker_run [get_runs -quiet $tracker_run_name]
if {[llength $tracker_run] != 1} {error "Vivado did not create tracker OOC run $tracker_run_name"}
set tracker_run [lindex $tracker_run 0]
set tracker_status [get_property STATUS $tracker_run]
if {![string match {*Complete*} $tracker_status]} {error "Tracker OOC synthesis did not complete: $tracker_status"}
if {![file isfile $tracker_run_dcp]} {error "Tracker OOC checkpoint is missing: $tracker_run_dcp"}
set tracker_run_tcl [file join $tracker_run_dir base_acoustic_pcm_iq_tracker_0.tcl]
set tracker_run_fd [open $tracker_run_tcl r]
set tracker_run_script [read $tracker_run_fd]
close $tracker_run_fd
if {[string first $mref_dir $tracker_run_script] < 0} {error "Tracker OOC run used a different module-ref tree than this build"}
set tracker_dcp_sha256 [lindex [split [exec sha256sum $tracker_run_dcp]] 0]
if {$tracker_dcp_sha256 eq "65ca6fae023b54b87e6255a795458bf1adf95625f2936b28a09bedb6929f5621"} {error "Refusing the known stale R10 tracker checkpoint"}
if {![file isfile $tracker_gen_dcp]} {error "Generated tracker checkpoint is missing: $tracker_gen_dcp"}
set tracker_gen_sha256 [lindex [split [exec sha256sum $tracker_gen_dcp]] 0]
if {$tracker_dcp_sha256 ne $tracker_gen_sha256} {error "Tracker run and generated checkpoints do not match"}
puts "TRACKER_MREF=$mref_dir"
puts "TRACKER_STATUS=$tracker_status"
puts "TRACKER_DCP=$tracker_run_dcp"
puts "TRACKER_DCP_SHA256=$tracker_dcp_sha256"
'''
build_tcl.write_text(text.replace(needle, preflight + needle + postflight, 1))

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
# The patched PYNQ bitstream Tcl sets the module-ref source tree and removes
# stale tracker checkpoints immediately before its normal implementation run.
sha256sum "$BASE/build_bitstream.tcl" >"$BUILD_ROOT/build-bitstream-tcl-sha256.txt"
TRACKER_DCP="$BASE/base/base.runs/base_acoustic_pcm_iq_tracker_0_synth_1/base_acoustic_pcm_iq_tracker_0.dcp"
make bitstream >"$BUILD_ROOT/bitstream.log" 2>&1
TRACKER_DCP_SHA256="$(sha256sum "$TRACKER_DCP" | cut -d ' ' -f 1)"
if [[ "$TRACKER_DCP_SHA256" == "65ca6fae023b54b87e6255a795458bf1adf95625f2936b28a09bedb6929f5621" ]]; then
    echo "Refusing the known stale R10 tracker checkpoint: $TRACKER_DCP" >&2
    exit 1
fi
make check_timing >"$BUILD_ROOT/check_timing.log" 2>&1
vivado -mode batch -source "$HW_REPO/scripts/report_phase11_combined.tcl" \
    -tclargs "$BASE/base/base.xpr" >"$BUILD_ROOT/reports.log" 2>&1

cp base.bit base.hwh "$BUILD_ROOT/"
cp -r base/phase11_reports "$BUILD_ROOT/"
sha256sum base.bit base.hwh >"$BUILD_ROOT/sha256.txt"
git -C "$HW_REPO" status --short --branch >"$BUILD_ROOT/hw-git-status.txt"
(
    cd "$HW_REPO"
    sha256sum \
        src/hdl/acoustic_buzzer_pulse.vhd \
        src/hdl/acoustic_pdm_clock.vhd \
        src/hdl/acoustic_pcm_filter_pkg.vhd \
        src/hdl/acoustic_pdm_pcm_filter.vhd \
        src/hdl/acoustic_pdm_pcm_continuous_capture.vhd \
        src/hdl/acoustic_pdm_pcm_continuous_registers.vhd \
        src/hdl/acoustic_pdm_pcm_continuous_control.vhd \
        src/hdl/acoustic_pcm_axis_tee.vhd \
        src/hdl/acoustic_pcm_iq_tracker.vhd \
        src/hdl/acoustic_video_marker.vhd \
        src/con/pynq_z2_buzzer.xdc \
        src/con/pynq_z2_pcm.xdc \
        src/con/pynq_z2_pcm_continuous_timing.xdc \
        src/con/phase11_marker_cdc.xdc \
        scripts/add_phase11_pcm_to_pynq_base.tcl \
        scripts/prune_phase11_base_to_camera.tcl \
        scripts/report_phase11_combined.tcl \
        scripts/build_phase11_combined.sh \
        sim/tb_acoustic_pcm_iq_tracker.vhd \
        sim/tb_acoustic_video_marker.vhd
) >"$BUILD_ROOT/source-sha256.txt"
cat >"$BUILD_ROOT/build-manifest.txt" <<EOF
PYNQ commit: $PYNQ_COMMIT
PYNQ HLS cache source: $PYNQ_HLS_CACHE_SOURCE
Vivado: $(vivado -version | head -1)
HW repository branch: $(git -C "$HW_REPO" branch --show-current)
HW repository commit: $(git -C "$HW_REPO" rev-parse HEAD)
HW working tree: see hw-git-status.txt; input source hashes: source-sha256.txt
PCM source: acoustic_pdm_pcm_continuous_control
PCM control AXI-Lite: 0x43C80000
PL four-channel I/Q/PDoA/TDoA tracker AXI-Lite: 0x43CB0000, parallel to PCM DMA
Tracker: PS-programmed fixed frequency/window/thresholds/geometry; PL phase, arrival, direction and pixel projection; no PCM reorder
Tracker OOC synthesis: PYNQ implementation resets both tracker checkpoints, pins the module-ref tree to this build, verifies fresh run and generated DCPs match, and rejects the known R10 DCP
Tracker OOC DCP SHA-256: $TRACKER_DCP_SHA256
Patched PYNQ build_bitstream.tcl SHA-256: see build-bitstream-tcl-sha256.txt
Marker GPIO AXI-Lite: 0x43C90000
PL video marker: acoustic_video_marker after pixel_unpack and before HDMI OUT
Marker shape: two independently controlled radial glow points (red PDoA, cyan TDoA)
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
