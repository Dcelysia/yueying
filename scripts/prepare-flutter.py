#!/usr/bin/env python3
"""Apply PiliPlus Android SDK patches only to this project's private Flutter SDK."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
sdk = root / 'toolchains/flutter'
patches = ['modal_barrier', 'text_selection', 'mouse_cursor', 'image_anim',
           'layout_builder', 'navigation_drawer', 'popup_menu', 'fab',
           'null_safety_for_selectable_region', 'selectable_region', 'editable_text',
           'text_field', 'scroll_position', 'scrollable', 'scrollable_gesture',
           'draggable_scrollable_sheet', 'scaffold', 'text', 'text_painter', 'sliver',
           'refresh_indicator', 'double_tap_gesture', 'bottom_sheet_android',
           'scroll_view', 'navigator']
if not (sdk / 'bin/flutter').is_file():
    raise SystemExit('Install Flutter 3.47.7 at toolchains/flutter first (see README).')
for name in patches:
    patch = root / 'apps/mobile/lib/scripts' / (name + '.patch')
    check = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=sdk,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode == 0:
        continue
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=sdk, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=sdk, check=True)
print('PiliPlus Android Flutter patches ready.')
