"""Record rendering dependencies on the Actions runner; no secrets or live service requests."""
import argparse
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path


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
    return {
        "flutter": flutter, "fonts": fonts, "python": platform.python_version(),
        "runnerImage": os.environ.get("ImageVersion"), "os": platform.system(),
        "workflowSha": os.environ.get("GITHUB_WORKFLOW_SHA"),
        "lockfile": hashlib.sha256((root / "pubspec.lock").read_bytes()).hexdigest(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--verify")
    args = parser.parse_args()
    result = runtime(Path.cwd(), Path(os.environ["XIANGQI_VISUAL_FONT_DIR"]))
    if args.verify and result != json.loads(Path(args.verify).read_text()):
        raise SystemExit("Renderer/font/dependency fingerprint differs from the batch planner")
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, sort_keys=True))
