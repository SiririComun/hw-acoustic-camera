#!/usr/bin/env python3
"""Run standalone phase-4.3 PCM RTL/reference checks in native XSim."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    hw = Path(__file__).resolve().parents[1]
    workspace = hw.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin', type=Path, default=Path('/home/siriricomun/tools/Xilinx/Vivado/2024.2/bin'))
    parser.add_argument('--output-root', type=Path, default=workspace/'evidence/phase-04-step-03')
    args = parser.parse_args()
    run = args.output_root.resolve()/(datetime.now(timezone.utc).strftime('run-%Y%m%dT%H%M%SZ-')+uuid.uuid4().hex[:8])
    source = run/'source'
    source.mkdir(parents=True)
    print('SIMULATION_RUN='+str(run), flush=True)
    report = dict(status='running', scope='standalone_pcm_rtl', inputs=[], commands=[],
                  synthesis_run=False, bitstream_generated=False, board_accessed=False,
                  runner_sha256=sha(Path(__file__).resolve()))

    def snapshot(path):
        dest = source/path.name
        shutil.copyfile(path, dest)
        report['inputs'].append(dict(path=str(path), snapshot=str(dest.relative_to(run)), sha256=sha(dest)))
        return dest

    def execute(label, command):
        print('STAGE='+label, flush=True)
        command = [str(a) for a in command]
        with (run/(label+'.log')).open('w') as log:
            result = subprocess.run(command, cwd=run, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        report['commands'].append(dict(stage=label, argv=command, exit_code=result.returncode))
        if result.returncode:
            raise RuntimeError(f'{label} failed: {run/(label+".log")}')
    try:
        design = snapshot(hw/'docs/pcm_filter_v1.json')
        pkg = snapshot(hw/'src/hdl/acoustic_pcm_filter_pkg.vhd')
        rtl = snapshot(hw/'src/hdl/acoustic_pdm_pcm_filter.vhd')
        bench = snapshot(hw/'sim/tb_pdm_pcm_filter.vhd')
        reference = snapshot(workspace/'sw-acoustic-camera/tools/pcm_fixed_reference.py')
        vectors = snapshot(workspace/'sw-acoustic-camera/tools/phase4_pcm_vectors.py')
        spec = json.loads(design.read_text())
        parsed = [int(v) for v in re.findall(r'to_signed\((-?\d+), 18\)', pkg.read_text())]
        if parsed != spec['fixed_point']['fir_coefficients']:
            raise ValueError('RTL coefficient table differs from frozen specification')
        if sha(design) != sha(workspace/'sw-acoustic-camera/pynq_acoustic_camera/data/pcm_filter_v1.json'):
            raise ValueError('HW/SW filter specifications differ')
        execute('vectors', [sys.executable, vectors, 'generate', '--directory', run/'vectors', '--design', design])
        execute('compile', [args.vivado_bin/'xvhdl', '--2008', '--work', 'xil_defaultlib', pkg, rtl, bench])
        execute('elaborate', [args.vivado_bin/'xelab', '--relax', '--mt', '2', 'xil_defaultlib.tb_pdm_pcm_filter', '--snapshot', 'pcm_filter_tb'])
        execute('simulate', [args.vivado_bin/'xsim', 'pcm_filter_tb', '--runall', '--onerror', 'quit', '--onfinish', 'quit', '--log', 'simulate-native.log'])
        if 'PDM_PCM_FILTER_ALL_PASS' not in (run/'simulate-native.log').read_text():
            raise RuntimeError('Simulator ended without the all-pass marker')
        execute('verify', [sys.executable, vectors, 'verify', '--directory', run/'vectors', '--trace', run/'pcm-trace.csv'])
        report['vectors'] = json.loads((run/'vectors/vector-report.json').read_text())
        report['verification'] = json.loads((run/'vectors/verification-report.json').read_text())
        report['status'] = 'pass'
    except Exception as error:
        report['status'] = 'fail'
        report['error'] = str(error)
        print('ERROR='+str(error), flush=True)
    finally:
        report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        (run/'simulation-report.json').write_text(json.dumps(report, indent=2)+'\n')
    print('RESULT='+report['status'], flush=True)
    return int(report['status'] != 'pass')


if __name__ == '__main__':
    sys.exit(main())
