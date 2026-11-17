#!/usr/bin/env python3
"""Native XSim checks for phase-7 continuous PCM transport and register ABI."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


def main():
    hw = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['stream', 'registers'], default='stream')
    parser.add_argument('--vivado-bin', type=Path, default=Path('/home/siriricomun/tools/Xilinx/Vivado/2024.2/bin'))
    args = parser.parse_args()
    run = hw.parent / 'evidence/phase-07-step-02' / (
        datetime.now(timezone.utc).strftime('run-%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:8])
    source = run / 'source'
    source.mkdir(parents=True)
    print('SIMULATION_RUN=' + str(run), flush=True)
    report = dict(status='running', suite=args.suite, inputs=[], commands=[],
                  synthesis_run=False, bitstream_generated=False, board_accessed=False)

    def snap(path):
        dest = source / path.name
        shutil.copyfile(path, dest)
        report['inputs'].append(dict(path=str(path), sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
        return dest

    def execute(label, command):
        print('STAGE=' + label, flush=True)
        command = list(map(str, command))
        with (run / (label + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=run, stdout=log, stderr=subprocess.STDOUT, timeout=2400)
        report['commands'].append(dict(stage=label, argv=command, exit_code=result.returncode))
        if result.returncode:
            raise RuntimeError(f'{label} failed: {run / (label + ".log")}')

    try:
        if args.suite == 'stream':
            names = ['acoustic_pcm_filter_pkg', 'acoustic_pdm_pcm_filter', 'acoustic_pdm_pcm_continuous_capture']
            bench_name = 'tb_pdm_pcm_continuous_capture'
            marker = 'CONTINUOUS_PCM_ALL_PASS'
        else:
            names = ['acoustic_pdm_pcm_continuous_registers']
            bench_name = 'tb_pdm_pcm_continuous_registers'
            marker = 'PDM_PCM_CONTINUOUS_REGISTERS_ALL_PASS'
        files = [snap(hw / 'src/hdl' / (name + '.vhd')) for name in names]
        bench = snap(hw / 'sim' / (bench_name + '.vhd'))
        glbl = snap(args.vivado_bin.parent / 'data/verilog/src/glbl.v')
        execute('compile', [args.vivado_bin / 'xvhdl', '--2008', '--work', 'xil_defaultlib', *files, bench])
        execute('compile-glbl', [args.vivado_bin / 'xvlog', '--work', 'xil_defaultlib', glbl])
        execute('elaborate', [args.vivado_bin / 'xelab', '--relax', '--mt', '2', '-L', 'unisim',
                              '-L', 'unisims_ver', '-L', 'secureip', '-L', 'xpm',
                              'xil_defaultlib.' + bench_name, 'xil_defaultlib.glbl',
                              '--snapshot', 'pcm_continuous_tb'])
        execute('simulate', [args.vivado_bin / 'xsim', 'pcm_continuous_tb', '--runall', '--onerror', 'quit',
                             '--onfinish', 'quit', '--log', 'simulate-native.log'])
        sim_log = run / 'simulate-native.log'
        if not sim_log.exists() or marker not in sim_log.read_text(errors='replace'):
            raise RuntimeError('Missing all-pass marker in XSim output')
        report['status'] = 'pass'
    except Exception as error:
        report['status'] = 'fail'
        report['error'] = str(error)
        print('ERROR=' + str(error), flush=True)
    finally:
        (run / 'simulation-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('RESULT=' + report['status'], flush=True)
    return int(report['status'] != 'pass')


if __name__ == '__main__':
    sys.exit(main())
