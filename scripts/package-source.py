#!/usr/bin/env python3
"""Archive the current Picline working files, including uncommitted changes."""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    build_script = (root / "scripts/build-picline.sh").read_text(encoding="utf-8")
    match = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", build_script)
    if not match:
        raise SystemExit("Could not find the Picline build version.")
    version = match[1]
    destination = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else root / "build" / f"Picline-{version}-Source.zip"
    if len(sys.argv) > 2:
        raise SystemExit("Usage: scripts/package-source.py [output.zip]")

    # Include current file contents, rather than archiving the upstream HEAD.
    # Original upstream branding artwork is not part of the Picline package.
    candidates = [root / name for name in ["Package.swift", "README.md", "LICENSE", "NOTICE", ".gitignore"]]
    for name in ["Sources", "Tests", "scripts", "docs/design/Picline-Icons-v1"]:
        candidates.extend((root / name).rglob("*"))
    candidates.append(root / "docs/Picline.zh-Hans.md")
    excluded_parts = {".git", ".build", "build", ".swiftpm", "__pycache__", "node_modules", ".DS_Store"}
    excluded_artwork = {"scripts/make-icon.swift", "scripts/make-readme-art.swift"}
    files = []
    for path in sorted(set(candidates)):
        relative = path.relative_to(root)
        if path.is_symlink() or not path.is_file() or excluded_parts.intersection(relative.parts):
            continue
        if relative.as_posix() in excluded_artwork:
            continue
        if path.name.startswith(".env") or path.suffix.lower() in {".p12", ".pfx", ".pem", ".key", ".mobileprovision", ".log", ".pyc"}:
            continue
        if path.resolve() == destination:
            continue
        files.append((path, relative.as_posix()))
    included = {relative for _, relative in files}
    required = {"Package.swift", "LICENSE", "NOTICE", "Sources/Tendedero/OpenSourceNotices.swift",
                "Sources/Tendedero/Resources/Artwork/Picline-AppIcon.png",
                "scripts/build-picline.sh", "scripts/make-picline-icon.swift", "scripts/package-source.py"}
    if not required.issubset(included):
        raise SystemExit(f"Source files are missing: {sorted(required - included)}")
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True)
    manifest = {
        "format_version": 1,
        "project": "Picline",
        "version": version,
        "base_revision": revision.stdout.strip() if revision.returncode == 0 else None,
        "contents": "Current working files, including local modifications and new files.",
        "files": [],
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = destination.with_name(destination.name + ".tmp")
    prefix = f"Picline-{version}-Source"
    try:
        with zipfile.ZipFile(staging, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
            for path, relative in files:
                data = path.read_bytes()
                info = zipfile.ZipInfo.from_file(path, arcname=f"{prefix}/{relative}")
                info.compress_type = zipfile.ZIP_DEFLATED
                package.writestr(info, data)
                manifest["files"].append({"path": relative, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            package.writestr(f"{prefix}/SOURCE_MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        staging.replace(destination)
    finally:
        staging.unlink(missing_ok=True)
    print(f"Packaged {len(files)} source files: {destination}")


if __name__ == "__main__":
    main()
