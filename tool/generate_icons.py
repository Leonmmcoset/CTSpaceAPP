"""Regenerate native icons from the community's existing logo (Pillow >= 9)."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Image.open(ROOT / 'assets/branding/logo.png').convert('RGBA')

def render(size):
    canvas = Image.new('RGBA', (size, size), '#F5F2FF')
    side = round(size * .79)
    mark = SOURCE.resize((side, side), Image.LANCZOS)
    canvas.alpha_composite(mark, ((size - side) // 2, (size - side) // 2))
    return canvas.convert('RGB')

for platform in ['ios', 'macos']:
    folder = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    data = json.loads((folder / 'Contents.json').read_text())
    for entry in data['images']:
        if 'filename' not in entry:
            continue
        side = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
        render(side).save(folder / entry['filename'])

for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    render(size).save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
render(256).save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
render(512).save(ROOT / 'assets/branding/app-icon.png')
folder = ROOT / 'android/app/src/main/res/drawable-nodpi'
folder.mkdir(exist_ok=True)
canvas = Image.new('RGBA', (432, 432))
canvas.alpha_composite(SOURCE.resize((260, 260), Image.LANCZOS), (86, 86))
canvas.save(folder / 'ic_launcher_foreground.png')
folder = ROOT / 'android/app/src/main/res/mipmap-anydpi-v26'
folder.mkdir(exist_ok=True)
(folder / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''')
(ROOT / 'android/app/src/main/res/values/colors.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="launcher_background">#F5F2FF</color></resources>
''')
