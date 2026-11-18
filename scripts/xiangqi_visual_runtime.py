"""Record rendering dependencies on the Actions runner; no secrets or live service requests."""
import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
from pathlib import Path


def file_hash(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def linked_libraries(tester):
    libraries = {}
    output = subprocess.check_output(['ldd', str(tester)], text=True)
    for line in output.splitlines():
        entry = line.strip()
        if entry.startswith('linux-vdso.'):
            continue
        match = re.fullmatch(r'(?:(\S+) => )?(/.+?) \(0x[0-9a-fA-F]+\)', entry)
        if not match:
            raise ValueError(f'Unresolved Flutter test library: {entry}')
        name, path = match.groups()
        libraries[name or Path(path).name] = file_hash(Path(path))
    if not libraries:
        raise ValueError('Missing Flutter test libraries')
    return libraries


def runtime(root, font_dir):
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("Rendering dependency collection only runs on Actions")
    flutter = json.loads(subprocess.check_output(["flutter", "--version", "--machine"], text=True))
    manifest = json.loads((root / "scripts/desktop-test-fonts.json").read_text())
    fonts = {font["file"]: hashlib.sha256((font_dir / font["file"]).read_bytes()).hexdigest()
             for font in manifest["fonts"]}
    for font in manifest["fonts"]:
        if fonts[font["file"]] != font["sha256"]:
            raise ValueError("The screenshot font is not the pinned font")
    sdk = Path(os.environ["FLUTTER_ROOT"])
    for name in ("Roboto-Regular.ttf", "Roboto-Medium.ttf", "Roboto-Bold.ttf", "MaterialIcons-Regular.otf"):
        fonts[name] = hashlib.sha256((sdk / "bin/cache/artifacts/material_fonts" / name).read_bytes()).hexdigest()
    engine = sdk / 'bin/cache/artifacts/engine/linux-x64'
    tester = engine / 'flutter_tester'
    # Actions can allocate different VM image builds within one batch. Compare the userland
    # that runs the test and retain each VM label in the separate provenance file.
    return {
        "engineFiles": {path.name: file_hash(path) for path in (tester, engine / 'icudtl.dat')},
        "linkedLibraries": linked_libraries(tester),
        "flutter": flutter, "fonts": fonts, "python": platform.python_version(),
        "os": platform.system(), "arch": platform.machine(),
        "workflowSha": os.environ.get("GITHUB_WORKFLOW_SHA"),
        "lockfile": hashlib.sha256((root / "pubspec.lock").read_bytes()).hexdigest(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--verify")
    args = parser.parse_args()
    result = runtime(Path.cwd(), Path(os.environ["XIANGQI_VISUAL_FONT_DIR"]))
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, sort_keys=True))
    target.with_suffix('.host.json').write_text(json.dumps({
        'image': os.environ.get('ImageOS'), 'version': os.environ.get('ImageVersion'),
    }, sort_keys=True))
    if args.verify:
        expected = json.loads(Path(args.verify).read_text())
        changed = [key for key in sorted(expected.keys() | result.keys()) if expected.get(key) != result.get(key)]
        if changed:
            raise SystemExit('Renderer differs from the batch planner: ' + ', '.join(changed))
