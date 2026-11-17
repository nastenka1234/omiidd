"""بعد از `flutter pub get` اجرا می‌شود: build.gradle پلاگین‌ها را بدون وابستگی به نسخه‌شان درست می‌کند.

۱) flutter.compileSdkVersion / minSdkVersion / targetSdkVersion / ndkVersion → عدد ثابت
   (خطای «Could not get unknown property 'flutter'» و «compileSdkVersion is not specified»)
۲) اگر پلاگین قدیمی namespace نداشت، از package مانیفست ساخته می‌شود (AGP 8 اجبار می‌کند).
فقط پلاگین‌های داخل pub-cache تغییر می‌کنند؛ پروژه‌ی خودمان دست نمی‌خورد. چند بار اجرا شود مشکلی نیست.
"""
import json, pathlib, re, sys, urllib.parse

COMPILE, MIN, TARGET = '34', '21', '34'
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
cfg = root / '.dart_tool' / 'package_config.json'
if not cfg.exists():
    sys.exit('fix_plugins: .dart_tool/package_config.json نیست؛ اول flutter pub get بزن')

subs = [
    (r'flutter\.compileSdkVersion', COMPILE),
    (r'flutter\.minSdkVersion', MIN),
    (r'flutter\.targetSdkVersion', TARGET),
]
patched, ns_added = 0, 0
for pkg in json.loads(cfg.read_text(encoding='utf8'))['packages']:
    uri = pkg['rootUri']
    base = pathlib.Path(urllib.parse.unquote(uri[7:])) if uri.startswith('file://') \
        else (cfg.parent / uri).resolve()
    adir = base / 'android'
    if not adir.is_dir() or root in base.parents or base == root:
        continue
    for name in ('build.gradle', 'build.gradle.kts'):
        f = adir / name
        if not f.exists():
            continue
        s = orig = f.read_text(encoding='utf8')
        for pat, val in subs:
            s = re.sub(pat, val, s)
        s = re.sub(r'^[ \t]*ndkVersion\s*=?\s*flutter\.ndkVersion[ \t]*\r?\n', '', s, flags=re.M)
        if not re.search(r'\bnamespace\b', s) and re.search(r'^android\s*\{', s, re.M):
            man = adir / 'src' / 'main' / 'AndroidManifest.xml'
            m = re.search(r'package\s*=\s*"([^"]+)"', man.read_text(encoding='utf8')) if man.exists() else None
            if m:
                eq = ' = ' if name.endswith('.kts') else ' '
                s = re.sub(r'^(android\s*\{)', lambda x: f'{x.group(1)}\n    namespace{eq}"{m.group(1)}"', s, count=1, flags=re.M)
                ns_added += 1
        if s != orig:
            f.write_text(s, encoding='utf8')
            patched += 1
            print(f'patched {pkg["name"]}/{name}')
print(f'fix_plugins: {patched} فایل اصلاح شد، {ns_added} namespace اضافه شد')
