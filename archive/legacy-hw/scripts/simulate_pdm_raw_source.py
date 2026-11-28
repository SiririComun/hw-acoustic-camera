#!/usr/bin/env python3
"""Run the step-3.2 digital sampler checks with native Vivado XSim.

Each invocation snapshots its inputs into a fresh evidence directory. No Vivado
project, synthesis, bitstream, PYNQ import, network or board operation is used.
"""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_info(repo):
    def read(*args):
        return subprocess.run(["git", "-C", str(repo), *args], check=True,
                              capture_output=True, text=True).stdout.strip()
    return {"head": read("rev-parse", "HEAD"), "branch": read("branch", "--show-current"),
            "status_porcelain": read("status", "--porcelain")}


def main():
    hw = Path(__file__).resolve().parents[1]
    workspace = hw.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("source", "stream", "registers"), default="source")
    parser.add_argument("--vivado-bin", type=Path,
                        default=Path("/home/siriricomun/tools/Xilinx/Vivado/2024.2/bin"))
    parser.add_argument("--reference-tool", type=Path,
                        default=workspace / "sw-acoustic-camera/tools/phase3_raw_reference.py")
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    args.vivado_bin = args.vivado_bin.resolve()
    step = {"source": "3.2", "stream": "3.3", "registers": "3.4"}[args.suite]
    output_root = args.output_root or workspace / "evidence" / ("phase-03-step-" + {"source": "02", "stream": "03", "registers": "04"}[args.suite])
    run = output_root.resolve() / (datetime.now(timezone.utc).strftime("run-%Y%m%dT%H%M%SZ-")
                                        + uuid.uuid4().hex[:8])
    run.mkdir(parents=True, exist_ok=False)
    (run / "source").mkdir()
    print("SIMULATION_RUN=" + str(run), flush=True)
    metadata = {"phase": 3, "step": step, "status": "running", "scope": "digital_" + args.suite,
                "started_at_utc": datetime.now(timezone.utc).isoformat(),
                "hw_repository": git_info(hw), "inputs": [], "commands": [],
                "synthesis_run": False, "bitstream_generated": False, "board_accessed": False,
                "microphones_connected": False, "runner_sha256": sha(Path(__file__).resolve())}

    def snapshot(path):
        path = path.resolve()
        target = run / "source" / path.name
        shutil.copyfile(path, target)
        metadata["inputs"].append({"original_path": str(path), "snapshot": str(target.relative_to(run)),
                                   "size_bytes": target.stat().st_size, "sha256": sha(target)})
        return target

    def execute(label, command, timeout=300):
        command = [str(arg) for arg in command]
        print("STAGE=" + label, flush=True)
        started = time.monotonic()
        entry = {"stage": label, "argv": command, "timeout_seconds": timeout,
                 "console_log": label + "-console.log"}
        metadata["commands"].append(entry)
        with (run / entry["console_log"]).open("w") as handle:
            process = subprocess.Popen(command, cwd=run, stdout=handle, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                entry["exit_code"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                entry["timeout"] = True
                raise RuntimeError("{} exceeded {} seconds".format(label, timeout))
            finally:
                entry["elapsed_seconds"] = round(time.monotonic() - started, 3)
        if entry["exit_code"]:
            raise RuntimeError("{} failed; see {}".format(label, run / entry["console_log"]))

    try:
        clock = snapshot(hw / "src/hdl/acoustic_pdm_clock.vhd")
        control = snapshot(hw / "src/hdl/acoustic_pdm_clock_control.vhd")
        source = snapshot(hw / "src/hdl/acoustic_pdm_raw_source.vhd")
        bench_name = {"source": "tb_pdm_raw_source", "stream": "tb_pdm_raw_capture", "registers": "tb_pdm_raw_registers"}[args.suite]
        bench = snapshot(hw / "sim" / (bench_name + ".vhd"))
        extra_sources = []
        if args.suite != "source":
            extra_sources.append(snapshot(hw / "src/hdl/acoustic_pdm_raw_capture.vhd"))
        if args.suite == "registers":
            extra_sources += [snapshot(hw / "src/hdl/acoustic_pdm_raw_registers.vhd"),
                              snapshot(hw / "src/hdl/acoustic_pdm_raw_control.vhd")]
        reference = snapshot(args.reference_tool) if args.suite == "source" else None
        glbl = snapshot(args.vivado_bin.resolve().parent / "data/verilog/src/glbl.v")
        for tool in ("xvhdl", "xvlog", "xelab", "xsim"):
            if not (args.vivado_bin / tool).is_file():
                raise FileNotFoundError("Missing simulator tool: " + tool)
        execute("version", [args.vivado_bin / "xsim", "--version"], timeout=30)
        if reference is not None:
            execute("generate-vectors", [sys.executable, reference, "generate", "--directory", run / "vectors"], 30)
        execute("compile-vhdl", [args.vivado_bin / "xvhdl", "--2008", "--work", "xil_defaultlib",
                                 "--log", "compile-vhdl.log", clock, control, source, *extra_sources, bench])
        execute("compile-glbl", [args.vivado_bin / "xvlog", "--work", "xil_defaultlib",
                                 "--log", "compile-glbl.log", glbl])
        execute("elaborate", [args.vivado_bin / "xelab", "--relax", "--mt", "2",
                              "-L", "unisim", "-L", "unisims_ver", "-L", "secureip", "-L", "xpm",
                              "xil_defaultlib." + bench_name, "xil_defaultlib.glbl",
                              "--snapshot", "pdm_raw_source_tb", "--log", "elaborate.log"])
        execute("simulate", [args.vivado_bin / "xsim", "pdm_raw_source_tb", "--runall",
                             "--onerror", "quit", "--onfinish", "quit", "--stats",
                             "--log", "simulate.log"])
        marker = {"source": "PDM_RAW_SOURCE_ALL_PASS", "stream": "PDM_RAW_STREAM_ALL_PASS", "registers": "PDM_RAW_REGISTERS_ALL_PASS"}[args.suite]
        if marker not in (run / "simulate.log").read_text():
            raise RuntimeError("Simulation ended without the all-pass marker")
        for suite in (("unit", "clock") if args.suite == "source" else ()):
            command = [sys.executable, reference, "verify", "--directory", run / "vectors",
                       "--trace", run / (suite + "-trace.csv"), "--suite", suite,
                       "--report", run / (suite + "-report.json")]
            if suite == "clock":
                command += ["--phase-trace", run / "clock-phase.csv"]
            execute("verify-" + suite, command, timeout=30)
        metadata["status"] = "pass"
        if args.suite == "source":
            metadata["reports"] = [json.loads((run / (suite + "-report.json")).read_text())
                                   for suite in ("unit", "clock")]
        elif args.suite == "registers":
            metadata["reports"] = [{"result": "pass", "scope": "AXI-Lite adapter plus native XPM capture core",
                                    "successful_captures": 3, "words_checked": 20}]
        else:
            expected = {1: 1, 2: 2, 3: 17, 4: 4096, 5: 65536, 6: 17,
                        7: 17, 8: 2, 9: 17, 10: 1, 11: 1}
            observed = {case: 0 for case in expected}
            with (run / "stream-trace.csv").open(newline="") as handle:
                for row in csv.DictReader(handle):
                    case, index, word, last, keep = (int(row[k]) for k in ("case_id", "index", "word", "last", "keep"))
                    if case not in expected or index != observed[case] or word != (10 if case == 6 else index):
                        raise ValueError("Stream trace order/content mismatch")
                    if keep != 15 or last != int(index == expected[case] - 1):
                        raise ValueError("Stream trace TKEEP/TLAST mismatch")
                    observed[case] += 1
            if observed != expected:
                raise ValueError("Stream trace length mismatch")
            metadata["reports"] = [{"result": "pass", "successful_cases": observed,
                                     "words_checked": sum(observed.values()), "fifo_depth": 8192,
                                     "protocol_and_errors": "VHDL assertions passed"}]
    except Exception as error:
        metadata["status"] = "fail"
        metadata["error"] = str(error)
        print("ERROR=" + str(error), file=sys.stderr)
    finally:
        metadata["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        (run / "simulation-report.json").write_text(json.dumps(metadata, indent=2) + "\n")
        paths = list((run / "source").glob("*")) + list((run / "vectors").glob("*"))
        paths += list(run.glob("*.csv")) + list(run.glob("*.json")) + list(run.glob("*.log"))
        paths = sorted(set(p for p in paths if p.name != "artifact-manifest.json"))
        manifest = {"hash_algorithm": "sha256", "self_excluded": True,
                    "scope": "sources_vectors_traces_reports_logs_not_simulator_cache",
                    "files": [{"path": str(p.relative_to(run)), "size_bytes": p.stat().st_size,
                               "sha256": sha(p)} for p in paths]}
        (run / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print("RESULT=" + metadata["status"], flush=True)
        print("REPORT=" + str(run / "simulation-report.json"), flush=True)
    return 0 if metadata["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
