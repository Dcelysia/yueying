#!/usr/bin/env python3
"""Install the pinned Flutter SDK into this project, without changing shell profiles."""
import hashlib
import platform
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
archive = root / 'toolchains/flutter-sdk.zip'
expected = 'dd9da574c3168460550117eb0e8dd0313ae934fabf64a82a6d557fff5fd1422e'
archive.parent.mkdir(exist_ok=True)
if not (root / 'toolchains/flutter/bin/flutter').exists():
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('Install Flutter 3.47.7 in toolchains/flutter for your platform, then rerun this script.')
    if not archive.exists():
        subprocess.run(['curl', '-fL', '--retry', '2', 'https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.7-stable.zip', '-o', str(archive)], check=True)
    with archive.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != expected:
        raise SystemExit('Flutter SDK checksum mismatch; the archive was not extracted.')
    subprocess.run(['unzip', '-q', str(archive), '-d', str(archive.parent)], check=True)
subprocess.run(['python3', str(root / 'scripts/prepare-flutter.py')], check=True)
