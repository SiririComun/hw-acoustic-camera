#!/usr/bin/env python3
"""Validate and stage the phase-1 XADC candidate without running Vivado."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[1]
ASSETS = ('pynq_z2.bit', 'pynq_z2.hwh', 'build-manifest.json',
          'implementation-review.json', 'SHA256SUMS.txt')
PACKAGING = {'.gitignore', 'README.md', '.github/workflows/release.yml',
             '.github/workflows/lint.yml', 'scripts/validate_release.py'}


def git(*args):
    return subprocess.check_output(['git', '-C', str(REPO), *args], text=True).strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(tag, output):
    require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+-rc\.[1-9][0-9]*', tag),
            'Expected a candidate tag such as v0.1.0-rc.1')
    require(not git('status', '--porcelain=v1', '--untracked-files=all',
                    '--ignore-submodules=all'), 'Release checkout must be clean')
    head = git('rev-parse', 'HEAD')
    require(git('rev-parse', tag + '^{commit}') == head, 'Tag does not identify HEAD')
    folder = REPO / 'bin'
    manifest = json.loads((folder / 'build-manifest.json').read_text())
    require(manifest['schema_version'] == 1 and manifest['source_clean'] is True,
            'Unsupported or dirty build manifest')
    require(manifest['repository'] == 'SiririComun/hw-acoustic-camera', 'Wrong repository')
    require((manifest['board'], manifest['part'], manifest['top'], manifest['interface_id']) ==
            ('pynq_z2', 'xc7z020clg400-1', 'xadc_wrapper', 'legacy-xadc-reference/1'),
            'Unexpected phase-1 hardware identity')
    require(manifest['build_id_128'] is None and manifest['physical_validation'] == 'not_run',
            'Phase-1 candidate must not claim runtime PDM identity or physical validation')
    require(manifest['vivado_version_observed'] == '2024.2.2', 'Unexpected Vivado version')
    require(manifest['implementation_report']['run_status'] == 'write_bitstream Complete!',
            'Build did not complete bitstream generation')
    source = manifest['source_commit']
    require(re.fullmatch('[0-9a-f]{40}', source), 'Invalid source commit')
    subprocess.run(['git', '-C', str(REPO), 'merge-base', '--is-ancestor', source, head], check=True)
    changes = git('diff', '--name-only', '-z', source, head).split('\0')
    for name in filter(None, changes):
        require(name in PACKAGING or name.startswith(('docs/', 'bin/')),
                'Non-packaging source changed since build: ' + name)
    modules = []
    for line in git('ls-tree', 'HEAD').splitlines():
        attrs, name = line.split('\t', 1)
        mode, _, commit = attrs.split()
        if mode == '160000':
            modules.append({'path': name, 'commit': commit})
    require(sorted(modules, key=lambda x: x['path']) ==
            sorted(manifest['submodules'], key=lambda x: x['path']), 'Submodule pins differ')
    records = manifest['files']
    require(len(records) == 2 and {x['name'] for x in records} == {'pynq_z2.bit', 'pynq_z2.hwh'},
            'Expected exactly one BIT/HWH pair')
    for record in records:
        path = folder / record['name']
        require(path.is_file() and not path.is_symlink(), 'Missing or linked artifact')
        require(path.stat().st_size == record['size_bytes'] > 0 and
                sha(path) == record['sha256'], 'Artifact integrity mismatch: ' + record['name'])
    root = ET.parse(folder / 'pynq_z2.hwh').getroot()
    instances = {m.get('INSTANCE') for m in root.findall('.//MODULE')}
    require({'axi_dma_0', 'axi_dma_1', 'axi_dma_2'} <= instances, 'Wrong root HWH')
    review = json.loads((folder / 'implementation-review.json').read_text())
    require(review['source_commit'] == source and
            review['build_run_id'] == manifest['build_run_id'] and
            review['physical_validation'] == 'not_run' and review['clock_hz'] == 100000000,
            'Implementation review does not match build')
    timing = review['timing']
    require(timing['wns_ns'] >= 0 and timing['whs_ns'] >= 0 and
            timing['tns_ns'] == 0 and timing['ths_ns'] == 0 and
            timing['wpws_ns'] >= 0, 'Implementation review records failing timing')
    require(review['drc']['errors'] == 0, 'Review records DRC errors')
    require(review['artifact_files'] == records, 'Reviewed artifacts differ from manifest')
    expected = {name: sha(folder / name) for name in ASSETS if name != 'SHA256SUMS.txt'}
    observed = {}
    for line in (folder / 'SHA256SUMS.txt').read_text().splitlines():
        digest, name = line.split('  ', 1)
        require(name not in observed, 'Duplicate checksum entry')
        observed[name] = digest
    require(observed == expected, 'Checksum manifest mismatch')
    require(not output.exists(), 'Output already exists; choose a fresh staging directory')
    require(REPO != output and REPO not in output.parents, 'Stage assets outside checkout')
    output.mkdir(parents=True)
    for name in ASSETS:
        shutil.copyfile(folder / name, output / name)
    print(json.dumps({'tag': tag, 'packaging_commit': head, 'source_commit': source,
                      'build_run_id': manifest['build_run_id'], 'assets': expected,
                      'physical_validation': 'not_run'}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        validate(args.tag, args.output_dir.resolve())
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError,
            subprocess.CalledProcessError) as error:
        print('Release validation failed: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
