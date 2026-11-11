#!/usr/bin/env python3
"""Build and package the legacy XADC reference; Python 3.8+ standard library.

Each invocation uses a fresh independent clone for Hog's Projects/ directory.
This is not an installer or release publisher. See docs/BUILD_REFERENCE.md.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
import zipfile


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"})
    if result.returncode:
        raise RuntimeError("Git {} failed (exit {})".format(args[0], result.returncode))
    return result.stdout.decode("utf-8")


def clean(repo):
    if git(repo, "status", "--porcelain=v1", "--untracked-files=all",
           "--ignore-submodules=none").strip():
        raise RuntimeError("Source repository or submodule is not clean: " + str(repo))


def submodules(repo, prefix=Path()):
    records = []
    for entry in git(repo, "ls-tree", "-rz", "HEAD").split("\0"):
        if not entry:
            continue
        attributes, name = entry.split("\t", 1)
        mode, _, commit = attributes.split()
        if mode != "160000":
            continue
        module = repo / name
        if git(module, "rev-parse", "HEAD").strip() != commit:
            raise RuntimeError("Uninitialized or mismatched module: " + str(module))
        clean(module)
        relative = prefix / name
        records.append({"path": relative.as_posix(), "commit": commit})
        records.extend(submodules(module, relative))
    return records


def write_json(path, data):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def file_record(path, relative_to):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    size = path.stat().st_size
    if not size:
        raise RuntimeError("Empty output: " + str(path))
    return {"name": path.relative_to(relative_to).as_posix(),
            "size_bytes": size, "sha256": digest.hexdigest()}


def run_logged(command, cwd, log, env):
    print("Running {} (log: {})".format(command[0], log), flush=True)
    with log.open("x", encoding="utf-8") as stream:
        result = subprocess.run([str(arg) for arg in command], cwd=str(cwd), env=env,
                                stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError("Command failed (exit {}); inspect {}".format(result.returncode, log))


def inside(path, parent):
    return parent.resolve() in path.resolve().parents


def package(run, checkout, request):
    export, staging = run / "export", run / ".artifacts-stage"
    receipt = {}
    for line in (export / "export-receipt.tsv").read_text().splitlines():
        key, value = line.split("\t", 1)
        if key in receipt:
            raise RuntimeError("Duplicate export receipt field")
        receipt[key] = value
    required = {"project_file", "bit_file", "hwh_file", "part", "top", "implementation_status", "vivado_version"}
    if set(receipt) != required:
        raise RuntimeError("Unexpected export receipt fields")
    project = checkout / "Projects/pynq_z2/pynq_z2.xpr"
    if Path(receipt["project_file"]).resolve() != project.resolve():
        raise RuntimeError("Export belongs to another generated project")
    if (receipt["part"] != "xc7z020clg400-1" or receipt["top"] != "xadc_wrapper"
            or receipt["vivado_version"] != request["expected_vivado_version"]):
        raise RuntimeError("Exported part, top or tool version mismatch")
    if not re.search(r"write_bitstream.*complete", receipt["implementation_status"], re.I):
        raise RuntimeError("Export does not record a completed bitstream")
    original_bit = Path(receipt["bit_file"])
    if not inside(original_bit, checkout / "Projects/pynq_z2"):
        raise RuntimeError("Bitstream is outside the isolated generated project")
    archive = export / "reference.xsa"
    with zipfile.ZipFile(archive) as xsa:
        for suffix, output in [(".bit", "pynq_z2.bit")]:
            members = [info for info in xsa.infolist()
                       if not info.is_dir() and info.filename.lower().endswith(suffix)]
            if len(members) != 1 or not 0 < members[0].file_size <= 128 * 1024 * 1024:
                raise RuntimeError("XSA must contain exactly one nonempty, bounded " + suffix)
            # Fixed output names, never filesystem paths supplied by a ZIP member.
            with xsa.open(members[0]) as source, (staging / output).open("xb") as dest:
                shutil.copyfileobj(source, dest)
            receipt["xsa_member" + suffix] = members[0].filename
    extracted = file_record(staging / "pynq_z2.bit", staging)
    produced = file_record(original_bit, original_bit.parent)
    if (extracted["sha256"], extracted["size_bytes"]) != (produced["sha256"], produced["size_bytes"]):
        raise RuntimeError("XSA bitstream differs from completed implementation")
    generated_hwh = checkout / "src/bd/hw_handoff/xadc.hwh"
    if Path(receipt["hwh_file"]).resolve() != generated_hwh.resolve():
        raise RuntimeError("HWH is not the isolated root BD handoff")
    if git(checkout, "ls-files", "--", "src/bd/hw_handoff/xadc.hwh").strip():
        raise RuntimeError("HWH must be generated, not a tracked historical artifact")
    if not generated_hwh.is_file() or not 0 < generated_hwh.stat().st_size <= 128 * 1024 * 1024:
        raise RuntimeError("Root BD HWH missing, empty or oversized")
    ET.parse(generated_hwh)
    shutil.copyfile(generated_hwh, staging / "pynq_z2.hwh")
    clean(checkout)
    if git(checkout, "rev-parse", "HEAD").strip() != request["source_commit"]:
        raise RuntimeError("Build changed source HEAD")
    if submodules(checkout) != request["submodules"]:
        raise RuntimeError("Build changed pinned submodules")
    reports = [file_record(staging / "reports" / name, staging)
               for name in ["timing_summary.rpt", "utilization.rpt", "drc.rpt"]]
    manifest = {
        "schema_version": 1, "repository": "SiririComun/hw-acoustic-camera",
        "source_commit": request["source_commit"], "source_clean": True,
        "submodules": request["submodules"], "build_run_id": request["build_run_id"],
        "generated_output_exclusions": request["generated_output_exclusions"],
        "built_at_utc": utc(), "vivado_version_observed": receipt["vivado_version"],
        "board": "pynq_z2", "part": receipt["part"], "top": receipt["top"],
        "interface_id": "legacy-xadc-reference/1", "build_id_128": None,
        "implementation_report": {"run_status": receipt["implementation_status"],
                                  "review_status": "not_performed_by_packager", "files": reports},
        "pair_provenance": {"method": "implemented XSA bit and root BD HWH from the same fresh isolated run",
                            "archive": file_record(archive, run),
                            "bit_member": receipt["xsa_member.bit"],
                            "generated_hwh": file_record(generated_hwh, checkout)},
        "files": [file_record(staging / name, staging)
                  for name in ["pynq_z2.bit", "pynq_z2.hwh"]],
        "physical_validation": "not_run",
    }
    write_json(staging / "build-manifest.json", manifest)
    checksum_records = manifest["files"] + [file_record(staging / "build-manifest.json", staging)]
    with (staging / "SHA256SUMS.txt").open("x") as stream:
        for record in checksum_records:
            stream.write("{}  {}\n".format(record["sha256"], record["name"]))
    # Only complete packages get the artifacts/ name; never update bin/ here.
    staging.rename(run / "artifacts")


def build(args):
    repo = Path(__file__).resolve().parents[1]
    for variable in ["HOG_EXTERNAL_PATH", "HOG_IP_PATH"]:
        if os.environ.get(variable):
            raise RuntimeError(variable + " is not supported by this pinned-reference flow")
    clean(repo)
    commit = git(repo, "rev-parse", "HEAD").strip()
    modules = submodules(repo)
    executable = shutil.which(args.vivado)
    if not executable:
        raise RuntimeError("Vivado executable not found")
    # Keep the launcher path; symlink resolution may change its installation root.
    vivado = Path(os.path.abspath(executable))
    builds = Path(args.builds_dir).expanduser().resolve()
    if builds == repo or inside(builds, repo):
        raise RuntimeError("Build outputs must be outside the working source repository")
    builds.mkdir(parents=True, exist_ok=True)
    identifier = "{}-{}-{}".format(
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        commit[:12], uuid.uuid4().hex[:8])
    run = builds / identifier
    run.mkdir()
    print("Build directory: " + str(run), flush=True)
    request = {"source_commit": commit, "source_clean": True, "submodules": modules,
               "build_run_id": identifier, "started_at_utc": utc(),
               "expected_vivado_version": "2024.2.2"}
    request["generated_output_exclusions"] = ["Hog/Tcl/NA/ps7_summary.html"]
    write_json(run / "build-request.json", request)
    env = {**os.environ, "PATH": str(vivado.parent) + os.pathsep + os.environ.get("PATH", ""),
           "GIT_TERMINAL_PROMPT": "0"}
    try:
        version = subprocess.run([str(vivado), "-version"], cwd=str(run), env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=True)
        (run / "vivado-version.txt").write_text(version.stdout)
        match = re.search(r"Vivado\s+v([0-9.]+)", version.stdout, re.IGNORECASE)
        if not match or match.group(1) != request["expected_vivado_version"]:
            raise RuntimeError("Expected Vivado 2024.2.2; see vivado-version.txt")
        checkout = run / "source"
        run_logged(["git", "clone", "--no-hardlinks", "--no-checkout", repo, checkout],
                   run, run / "clone.log", env)
        git(checkout, "checkout", "--detach", commit)
        # Local independent module clones avoid network credentials and shared stores.
        for index, module in enumerate(modules):
            target = checkout / module["path"]
            run_logged(["git", "clone", "--no-hardlinks", "--no-checkout",
                        repo / module["path"], target],
                       run, run / "module-{}.log".format(index), env)
            git(target, "checkout", "--detach", module["commit"])
        git(checkout, "submodule", "init")
        git(checkout, "submodule", "absorbgitdirs")
        # The PS7 IP writes its HTML summary relative to Hog's Tcl cwd. This
        # exact generated report is not an HDL/config input; keep the exception
        # explicit and local, without modifying the Hog submodule or ignoring
        # any tracked changes. All other untracked source changes still fail.
        hog_git = Path(git(checkout / "Hog", "rev-parse", "--absolute-git-dir").strip())
        with (hog_git / "info/exclude").open("a") as stream:
            stream.write("\n/Tcl/NA/ps7_summary.html\n")
        clean(checkout)
        if submodules(checkout) != modules:
            raise RuntimeError("Isolated clone does not match pinned modules")
        for directive in ["CREATE", "WORK"]:
            run_logged([checkout / "Hog/Do", directive, "pynq_z2"], checkout,
                       run / (directive.lower() + ".log"), env)
            clean(checkout)
        (run / "export").mkdir()
        (run / ".artifacts-stage/reports").mkdir(parents=True)
        run_logged([vivado, "-mode", "batch", "-source", checkout / "scripts/export_reference.tcl",
                    "-log", run / "export-vivado.log", "-journal", run / "export-vivado.jou",
                    "-tclargs", checkout / "Projects/pynq_z2/pynq_z2.xpr",
                    run / "export", run / ".artifacts-stage/reports"],
                   run, run / "export.log", env)
        clean(repo)
        if git(repo, "rev-parse", "HEAD").strip() != commit or submodules(repo) != modules:
            raise RuntimeError("Working source changed while building")
        package(run, checkout, request)
    except Exception as error:
        write_json(run / "failure.json", {"failed_at_utc": utc(), "error": str(error),
                                         "artifact_package_complete": False})
        raise
    print("Artifacts: {}. Reports require phase-1.4 review.".format(run / "artifacts"))


def main():
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds-dir", default=str(repo.parent / "builds"))
    parser.add_argument("--vivado", default="vivado", help="Vivado launcher path or executable name")
    args = parser.parse_args()
    try:
        build(args)
    except (OSError, ValueError, RuntimeError, ET.ParseError,
            subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print("Build failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
