#!/usr/bin/env python3
"""Build a market APP only after real public release metadata is configured."""
import argparse
import json
import os
import re
import io
from zipfile import ZipFile
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'ohos-poc'
PUBLIC_KEYS = (
    'BILI_REMOTE_OPERATOR', 'BILI_REMOTE_CONTACT_EMAIL',
    'BILI_REMOTE_SOURCE_URL', 'BILI_REMOTE_PRIVACY_URL', 'BILI_REMOTE_TERMS_URL',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path,
                        help='JSON with public Dart defines; never signing passwords')
    parser.add_argument('--bundle-name', required=True,
                        help='Actual bundle registered in Huawei Developer Center')
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    problems = []
    for key in PUBLIC_KEYS:
        value = config.get(key, '')
        if not isinstance(value, str) or not value.strip():
            problems.append(f'{key}: missing public information')
            continue
        if re.search(r'待填|待补|TODO|example|placeholder', value, re.I):
            problems.append(f'{key}: placeholder is not publication information')
        if key.endswith('_URL'):
            url = urlparse(value)
            host = url.hostname or ''
            if (url.scheme != 'https' or not host or url.username or url.password
                    or host == 'localhost' or host.endswith('.invalid')
                    or re.fullmatch(r'[0-9.]+', host)):
                problems.append(f'{key}: public HTTPS URL required')
        if key.endswith('_EMAIL') and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
            problems.append(f'{key}: valid public contact email required')
    native_app = json.loads((APP / 'ohos/AppScope/app.json5').read_text())['app']
    if native_app['bundleName'] != args.bundle_name:
        problems.append('Registered bundle does not match ohos/AppScope/app.json5')
    if args.bundle_name.startswith(('com.example.', 'org.example.')):
        problems.append('Development example bundle cannot be used for publication')
    if native_app.get('vendor') in ('', 'example', None):
        problems.append('AppScope vendor is still an example value')
    if not (APP / 'ohos/build-profile.json5').is_file():
        problems.append('Configure release signing in DevEco before building')
    if problems:
        raise SystemExit('Release preflight failed:\n- ' + '\n- '.join(problems))
    print('Public metadata and native identity checks passed.')
    print('Verify DevEco signing uses a RELEASE certificate/profile before uploading.')
    if args.check_only:
        return
    sdk = Path(os.environ.get('FLUTTER_OHOS_HOME',
                             str(Path.home() / 'development/flutter-ohos')))
    subprocess.run([str(sdk / 'bin/flutter'), 'build', 'app', '--release',
                    '--target-platform', 'ohos-arm64',
                    '--dart-define-from-file', str(args.config.resolve())],
                   cwd=APP, check=True)
    artifact = APP / 'ohos/build/outputs/default/ohos-default-signed.app'
    with ZipFile(artifact) as bundle:
        identity = json.loads(bundle.read('pack.info'))['summary']['app']
        if identity['bundleName'] != args.bundle_name:
            raise SystemExit('Built APP identity differs from the registered bundle; do not upload.')
        modules = [name for name in bundle.namelist() if name.endswith('.hap')]
        if not modules:
            raise SystemExit('Built APP contains no HAP modules; do not upload.')
        for module in modules:
            with ZipFile(io.BytesIO(bundle.read(module))) as hap:
                app = json.loads(hap.read('module.json'))['app']
                if app.get('debug') or app['bundleName'] != args.bundle_name:
                    raise SystemExit('APP contains a debug or mismatched module; do not upload.')
    print(f'Release APP identity/debug checks passed: {artifact}')
    print('An APP file is not a submitted or approved test version.')


if __name__ == '__main__':
    main()
