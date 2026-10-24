#!/usr/bin/env python3
"""Install the Flutter-OH (OpenHarmony) SDK into ~/development.

Separate from setup-flutter.py: the official SDK in <project>/toolchains/flutter
carries PiliPlus SDK patches and must not be replaced. This SDK cannot be
obtained with `flutter upgrade`, which would pull the upstream channel and
break the OpenHarmony adaptation.
"""
import argparse
import hashlib
import os
import platform
import shutil
import subprocess
from pathlib import Path

# The version tag is one patch ahead of the upstream baseline it adapts.
DEFAULT_VERSION = '3.41.9+ohos-1.0.2'
BASE_URL = 'https://repo.huaweicloud.com/flutter-ohos/flutter_infra_release/flutter/releases/stable'

# This is a general-purpose SDK, not a project dependency, so it lives outside
# the repository next to the Android SDK rather than inside toolchains/.
sdk_root = Path(os.environ.get(
    'FLUTTER_OHOS_HOME',
    Path.home() / 'development/flutter-ohos',
)).expanduser()


def archive_name(version: str) -> str:
    if platform.system() != 'Darwin':
        raise SystemExit('Only macOS is supported here; download the matching archive manually.')
    machine = platform.machine()
    if machine == 'arm64':
        return f'flutter_macos_arm64_{version}.zip'
    if machine == 'x86_64':
        return f'flutter_macos_{version}.zip'
    raise SystemExit(f'Unsupported architecture: {machine}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default=DEFAULT_VERSION)
    parser.add_argument('--sha256', help='Expected archive checksum; no official one is published.')
    args = parser.parse_args()

    if (sdk_root / 'bin/flutter').exists():
        print(f'Flutter-OH {args.version} already present at {sdk_root}')
        return

    name = archive_name(args.version)
    url = f'{BASE_URL}/macos/{name}'

    # Keep the archive next to the SDK, not in a temp dir: a failed extraction
    # would otherwise discard a multi-gigabyte download.
    staging_root = sdk_root.parent / 'flutter-ohos-staging'
    staging_root.mkdir(parents=True, exist_ok=True)
    archive = staging_root / name

    if not archive.exists():
        print(f'Downloading {url}')
        subprocess.run(['curl', '-fL', '--retry', '2', url, '-o', str(archive)], check=True)
    else:
        print(f'Reusing downloaded archive {archive}')

    with archive.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if args.sha256 and actual != args.sha256:
        raise SystemExit(f'Checksum mismatch: expected {args.sha256}, got {actual}')
    print(f'Archive sha256: {actual}')

    # The archive extracts to a top-level "flutter" directory.
    staging = staging_root / 'extracted'
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    subprocess.run(['unzip', '-q', str(archive), '-d', str(staging)], check=True)
    extracted = staging / 'flutter'
    if not (extracted / 'bin/flutter').exists():
        raise SystemExit(f'Unexpected archive layout: {sorted(staging.iterdir())}')
    if sdk_root.exists():
        shutil.rmtree(sdk_root)
    shutil.move(str(extracted), str(sdk_root))
    shutil.rmtree(staging_root)

    print(f'Flutter-OH installed at {sdk_root}')
    print('Run: source ~/.zshrc && flutter doctor -v')


if __name__ == '__main__':
    main()
