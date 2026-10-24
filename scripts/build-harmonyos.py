#!/usr/bin/env python3
"""Build the native HarmonyOS market APP in a private staging directory."""
import argparse
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlparse
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'apps/harmony'
KEYS = ('BILI_REMOTE_OPERATOR', 'BILI_REMOTE_CONTACT_EMAIL', 'BILI_REMOTE_SOURCE_URL',
        'BILI_REMOTE_PRIVACY_URL', 'BILI_REMOTE_TERMS_URL')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path, help='Private publication metadata JSON; no signing passwords')
    parser.add_argument('--bundle-name', default='com.dcelysia.yueying')
    parser.add_argument('--product', default='default', help='Product configured with market release signing')
    parser.add_argument('--deveco-home', type=Path, default=Path(os.environ.get('DEVECO_HOME', '/Applications/DevEco-Studio.app/Contents')))
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    metadata = json.loads(args.config.read_text())
    for key in KEYS:
        value = metadata.get(key, '')
        if not isinstance(value, str) or not value.strip() or re.search(r'待填|TODO|placeholder|example', value, re.I):
            raise SystemExit(f'{key}: real publication information required')
        if key.endswith('_URL'):
            u = urlparse(value)
            if u.scheme != 'https' or not u.hostname or u.username or u.password or u.hostname == 'localhost' or re.fullmatch(r'[0-9.]+', u.hostname):
                raise SystemExit(f'{key}: public HTTPS URL required')
        if key.endswith('_EMAIL') and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
            raise SystemExit(f'{key}: valid contact email required')
    identity = json.loads((APP / 'AppScope/app.json5').read_text())['app']
    if identity['bundleName'] != args.bundle_name or args.bundle_name.startswith(('com.example.', 'org.example.')):
        raise SystemExit('Registered bundle does not match AppScope/app.json5')
    profile = APP / 'build-profile.json5'
    if not profile.is_file():
        raise SystemExit('Copy build-profile.example.json5 to build-profile.json5 and configure release signing in DevEco')
    node = args.deveco_home / 'tools/node/bin/node'
    hvigor = args.deveco_home / 'tools/hvigor/bin/hvigorw.js'
    json5 = args.deveco_home / 'tools/hvigor/hvigor-ohos-plugin/node_modules/json5'
    # The bundled parser supports the same JSON5 syntax as DevEco, without a Python dependency.
    config = json.loads(subprocess.check_output([str(node), '-e',
        'process.stdout.write(JSON.stringify(require(process.argv[1]).parse(require("fs").readFileSync(process.argv[2],"utf8"))))',
        str(json5), str(profile)], text=True))
    product = next((p for p in config['app']['products'] if p['name'] == args.product), None)
    signing = next((s for s in config['app'].get('signingConfigs', []) if product and s['name'] == product.get('signingConfig')), None)
    if not signing:
        raise SystemExit('Selected product is not associated with a signing configuration')
    for item in config['app'].get('signingConfigs', []):
        for key in ('certpath', 'profile', 'storeFile'):
            value = Path(item['material'][key]).expanduser()
            value = value if value.is_absolute() else APP / value
            if not value.is_file():
                raise SystemExit(f'Signing material is missing: {key}')
            item['material'][key] = str(value.resolve())
    print('Metadata, application identity and signing association checks passed.')
    print('Confirm this profile authorizes MARKET release, not a development-device installation.')
    if args.check_only:
        return
    replacements = {'operator': metadata[KEYS[0]], 'contact_email': metadata[KEYS[1]],
                    'source_url': metadata[KEYS[2]], 'privacy_url': metadata[KEYS[3]],
                    'terms_url': metadata[KEYS[4]], 'policy_version': '1.0.2-native'}
    with tempfile.TemporaryDirectory(prefix='yueying-market-') as folder:
        stage = Path(folder) / 'harmony'
        shutil.copytree(APP, stage, ignore=shutil.ignore_patterns('build', '.hvigor', 'oh_modules', 'node_modules', '.idea', 'release-metadata.json'))
        private_config = stage / 'build-profile.json5'
        private_config.write_text(json.dumps(config, indent=2))
        private_config.chmod(0o600)
        for name in ('privacy-policy.md', 'user-agreement.md', 'NOTICE.md'):
            path = stage / 'entry/src/main/resources/rawfile' / name
            body = path.read_text()
            for key, value in replacements.items():
                body = body.replace('{{' + key + '}}', value)
            if re.search(r'\{\{\w+\}\}', body):
                raise SystemExit('Policy template contains unfilled publication fields')
            path.write_text(body)
        env = os.environ.copy()
        env.update(HOS_SDK_HOME=str(args.deveco_home / 'sdk'), JAVA_HOME=str(args.deveco_home / 'jbr'), NODE_HOME=str(args.deveco_home / 'tools/node'))
        subprocess.run([str(node), str(hvigor), '--mode', 'project', '-p', f'product={args.product}', '-p',
                        'buildMode=release', 'assembleApp', '--no-daemon'], cwd=stage, env=env, check=True)
        artifacts = list((stage / 'build/outputs').glob('**/*-signed.app'))
        if len(artifacts) != 1:
            raise SystemExit('Expected exactly one signed market APP')
        artifact = artifacts[0]
        with ZipFile(artifact) as bundle:
            modules = [n for n in bundle.namelist() if n.endswith('.hap')]
            if not modules:
                raise SystemExit('APP contains no HAP modules')
            for module in modules:
                with ZipFile(io.BytesIO(bundle.read(module))) as hap:
                    app = json.loads(hap.read('module.json'))['app']
                    if app.get('debug') is not False or app['bundleName'] != args.bundle_name or app['versionCode'] != identity['versionCode']:
                        raise SystemExit('Built APP contains a debug, mismatched or stale module; do not upload')
        output = ROOT / 'dist/harmonyos' / f'yueying-harmony-{identity["versionName"]}-release.app'
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(artifact, output)
        print(f'Native release APP identity/debug checks passed: {output}')
        print('An APP file is not a submitted or approved AppTest version.')


if __name__ == '__main__':
    main()
