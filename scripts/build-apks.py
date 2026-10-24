#!/usr/bin/env python3
"""Build both companion APKs and copy them into dist/. No publishing or device installation."""
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--only', choices=['mobile', 'tv', 'all'], default='all')
parser.add_argument('--test', action='store_true', help='Also run the focused protocol tests')
parser.add_argument('--tv-build-type', choices=['debug', 'release'], default='debug')
args = parser.parse_args()
dist = root / 'dist'
dist.mkdir(exist_ok=True)
source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
source_dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip())
built_apks = set()
manifest_path = dist / 'build-manifest.json'
previous = json.loads(manifest_path.read_text()).get('apks', {}) if manifest_path.exists() else {}
environment = os.environ.copy()
sdk = environment.get('ANDROID_HOME') or environment.get('ANDROID_SDK_ROOT')
if not sdk and platform.system() == 'Darwin':
    sdk = str(Path.home() / 'Library/Android/sdk')
if sdk:
    environment['ANDROID_HOME'] = sdk
    environment['ANDROID_SDK_ROOT'] = sdk
if platform.system() == 'Darwin' and not environment.get('JAVA_HOME'):
    environment['JAVA_HOME'] = subprocess.check_output(['/usr/libexec/java_home', '-v', '17'], text=True).strip()

def run(command, cwd=root):
    subprocess.run(list(map(str, command)), cwd=cwd, env=environment, check=True)

if args.only in ['mobile', 'all']:
    run(['python3', root / 'scripts/setup-flutter.py'])
    flutter = root / 'toolchains/flutter/bin/flutter'
    mobile = root / 'apps/mobile'
    run([flutter, 'pub', 'get'], mobile)
    if args.test:
        run([flutter, 'test', '--no-pub', 'test/remote_playback_test.dart'], mobile)
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    run([flutter, 'build', 'apk', '--release', '--target-platform=android-arm64', '--split-per-abi', '--no-pub', '--dart-define=pili.name=0.1.0', '--dart-define=pili.hash=' + sha, '--dart-define=pili.time=' + str(int(time.time()))], mobile)
    shutil.copy2(mobile / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk', dist / 'bili-remote-mobile.apk')
    built_apks.add('bili-remote-mobile.apk')

if args.only in ['tv', 'all']:
    run(['python3', root / 'scripts/prepare-native-grpc.py'])
    tv = root / 'apps/tv'
    variant = 'Default' + args.tv_build_type.title()
    command = ['./gradlew', ':app:assemble' + variant, '--console=plain', '--max-workers=4', '--no-configuration-cache', '--no-daemon']
    plugin = root / 'toolchains/protoc-gen-grpc-java'
    if plugin.exists():
        command.append('-PgrpcJavaPlugin=' + str(plugin))
    if args.test:
        command += [':app:test' + variant + 'UnitTest', '--tests', 'dev.aaa1115910.bv.cast.RemoteMediaTest']
    run(command, tv)
    apk_dir = tv / 'app/build/outputs/apk/default' / args.tv_build_type
    metadata = json.loads((apk_dir / 'output-metadata.json').read_text())
    apk = apk_dir / metadata['elements'][0]['outputFile']
    apk_name = 'bili-remote-tv-release.apk' if args.tv_build_type == 'release' else 'bili-remote-tv.apk'
    shutil.copy2(apk, dist / apk_name)
    built_apks.add(apk_name)

manifest = {'gitCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), 'apks': {}}
for apk in sorted(dist.glob('*.apk')):
    with apk.open('rb') as stream:
        record = {'bytes': apk.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
        if apk.name in built_apks:
            record.update(gitCommit=source_commit, sourceDirty=source_dirty)
        elif previous.get(apk.name, {}).get('sha256') == record['sha256']:
            record.update({key: value for key, value in previous[apk.name].items() if key not in ['bytes', 'sha256']})
        manifest['apks'][apk.name] = record
(dist / 'build-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print('APKs and checksums:', dist)
