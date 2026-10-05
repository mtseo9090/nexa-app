"""Prepares the Android part of the freshly created Flutter project: name, permissions, plain-http to the laptop, icon."""
import re, shutil, sys
from pathlib import Path

app = Path(sys.argv[1])
man = app / "android/app/src/main/AndroidManifest.xml"
s = man.read_text(encoding="utf-8")
extra = '''    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <queries>
        <intent><action android:name="android.speech.RecognitionService"/></intent>
    </queries>
'''
if "RECORD_AUDIO" not in s: s = s.replace("<application", extra + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="NEXA AI"', s, count=1)
if "usesCleartextTraffic" not in s: s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
man.write_text(s, encoding="utf-8")

for name in ("build.gradle.kts", "build.gradle"):          # Android 7 or newer
    g = app / "android/app" / name
    if g.exists():
        t = g.read_text(encoding="utf-8")
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
        t = re.sub(r"minSdkVersion\s*=\s*flutter\.minSdkVersion", "minSdkVersion = 24", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
        t = re.sub(r"minSdk\s+flutter\.minSdkVersion", "minSdk 24", t)
        g.write_text(t, encoding="utf-8")

res = app / "android/app/src/main/res"
for d in (Path(__file__).parent / "icons").iterdir():
    if d.is_dir():
        (res / d.name).mkdir(parents=True, exist_ok=True)
        for f in d.iterdir(): shutil.copy(f, res / d.name / f.name)
test = app / "test/widget_test.dart"
if test.exists(): test.unlink()
print("android project prepared")
