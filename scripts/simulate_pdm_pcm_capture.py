#!/usr/bin/env python3
"""Native XSim integration checks: atomic frame FIFO, PCM/RAW and AXI-Lite."""
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
    hw=Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',choices=['stream','registers'],default='stream')
    parser.add_argument('--vivado-bin',type=Path,default=Path('/home/siriricomun/tools/Xilinx/Vivado/2024.2/bin'))
    args=parser.parse_args()
    run=hw.parent/'evidence/phase-04-step-04'/(datetime.now(timezone.utc).strftime('run-%Y%m%dT%H%M%SZ-')+uuid.uuid4().hex[:8])
    source=run/'source'; source.mkdir(parents=True)
    print('SIMULATION_RUN='+str(run),flush=True)
    report=dict(status='running',suite=args.suite,inputs=[],commands=[],synthesis_run=False,bitstream_generated=False,board_accessed=False)
    def snap(path):
        dest=source/path.name; shutil.copyfile(path,dest)
        report['inputs'].append(dict(path=str(path),sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
        return dest
    def execute(label,command):
        print('STAGE='+label,flush=True)
        command=list(map(str,command))
        with (run/(label+'.log')).open('w') as log:
            result=subprocess.run(command,cwd=run,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        report['commands'].append(dict(stage=label,argv=command,exit_code=result.returncode))
        if result.returncode: raise RuntimeError(f'{label} failed: {run/(label+".log")}')
    try:
        names=['acoustic_pdm_clock','acoustic_pcm_filter_pkg','acoustic_pdm_pcm_filter','acoustic_pdm_pcm_capture','acoustic_pdm_pcm_registers','acoustic_pdm_pcm_control']
        files=[snap(hw/'src/hdl'/(n+'.vhd')) for n in names]
        benchname='tb_pdm_pcm_capture' if args.suite=='stream' else 'tb_pdm_pcm_registers'
        bench=snap(hw/'sim'/(benchname+'.vhd'))
        glbl=snap(args.vivado_bin.parent/'data/verilog/src/glbl.v')
        execute('compile',[args.vivado_bin/'xvhdl','--2008','--work','xil_defaultlib',*files,bench])
        execute('compile-glbl',[args.vivado_bin/'xvlog','--work','xil_defaultlib',glbl])
        execute('elaborate',[args.vivado_bin/'xelab','--relax','--mt','2','-L','unisim','-L','unisims_ver','-L','secureip','-L','xpm','xil_defaultlib.'+benchname,'xil_defaultlib.glbl','--snapshot','pcm_capture_tb'])
        execute('simulate',[args.vivado_bin/'xsim','pcm_capture_tb','--runall','--onerror','quit','--onfinish','quit','--log','simulate-native.log'])
        marker='PDM_PCM_STREAM_ALL_PASS' if args.suite=='stream' else 'PDM_PCM_REGISTERS_ALL_PASS'
        if marker not in (run/'simulate-native.log').read_text(): raise RuntimeError('Missing all-pass marker')
        if args.suite=='stream':
            import csv
            expected={1:4,2:8,3:68,4:16384,5:262144,6:68,7:68,8:8,9:68,10:4,11:4,12:1,13:2,14:17,15:4096,16:65536,17:17}
            counts={k:0 for k in expected}
            with (run/'stream-trace.csv').open() as f:
                for row in csv.DictReader(f):
                    cid=int(row['case_id']); index=int(row['index']); word=int(row['word'])
                    if index!=counts[cid]: raise AssertionError('Trace index differs')
                    want=16*(index//4)+index%4 if cid<12 else index
                    if cid==6: want=-8388608 if index%2==0 else 8388607
                    if cid==17: want=10
                    if word!=want or int(row['keep'])!=15 or int(row['last'])!=int(index==expected[cid]-1): raise AssertionError('Trace content/TLAST differs')
                    counts[cid]+=1
            if counts!=expected: raise AssertionError('Trace lengths differ')
            report['successful_cases']=counts
            report['words_checked']=sum(counts.values())
            report['fifo_depth_frames']=2048
        report['status']='pass'
    except Exception as error:
        report['status']='fail';report['error']=str(error);print('ERROR='+str(error),flush=True)
    finally:
        (run/'simulation-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('RESULT='+report['status'],flush=True)
    return int(report['status']!='pass')


if __name__=='__main__': sys.exit(main())
