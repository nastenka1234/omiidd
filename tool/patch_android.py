"""بعد از `flutter create` اجرا می‌شود: مجوزها، سرویس پخش، AudioServiceActivity، desugaring و اپ‌بلاکر (Kotlin بومی)."""
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
man = root / 'android/app/src/main/AndroidManifest.xml'
s = man.read_text(encoding='utf8')

perms = ['INTERNET', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK',
         'WAKE_LOCK', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'ACCESS_NETWORK_STATE',
         # اپ‌بلاکر (۱E): نمایش صفحه‌ی بلاک روی اپ‌های دیگر، سرویس پیش‌زمینه و استثنای باتری
         'SYSTEM_ALERT_WINDOW', 'FOREGROUND_SERVICE_SPECIAL_USE', 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n'
              for p in perms if f'android.permission.{p}"' not in s)
s = re.sub(r'(<manifest[^>]*>\n)', lambda m: m.group(1) + add, s, count=1)
if 'xmlns:tools' not in s:
    s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="امید"', s, count=1)
# امنیت: بدون بکاپ ابری/adb (توکن و صف ارسال داخل بکاپ نمی‌رود) و فقط HTTPS.
# (آپدیت اپ از روی نسخه‌ی قبلی داده را نگه می‌دارد؛ این‌ها به آپدیت ربطی ندارند.)
if 'android:allowBackup' not in s:
    s = s.replace('<application', '<application android:allowBackup="false" android:usesCleartextTraffic="false"', 1)
# پخش موزیک (LockCachingAudioSource) از یک پروکسی HTTP روی 127.0.0.1 می‌گذرد؛ cleartext کلی
# بسته است و بدون این استثنا پخش بی‌صدا شکست می‌خورد. فقط localhost مجاز است، بقیه HTTPS.
xml_dir = root / 'android/app/src/main/res/xml'
xml_dir.mkdir(parents=True, exist_ok=True)
(xml_dir / 'network_security_config.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false"/>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
''', encoding='utf8')
if 'android:networkSecurityConfig' not in s:
    s = s.replace('<application', '<application android:networkSecurityConfig="@xml/network_security_config"', 1)

extra = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
s = s.replace('</application>', extra + '    </application>', 1)

# ───────────── اپ‌بلاکر (۱E) ─────────────
# PACKAGE_USAGE_STATS مجوز «ویژه» است (کاربر در تنظیمات می‌دهد)؛ tools:ignore برای هشدار لینت.
usage_perm = '    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions"/>\n'
if 'PACKAGE_USAGE_STATS' not in s:
    s = s.replace('<application', usage_perm + '    <application', 1)

# دیدن اپ‌های لانچردار بدون QUERY_ALL_PACKAGES (فقط با intent)
q_intents = (
    '<intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent>'
    '<intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.HOME"/></intent>'
    '<intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>'
    '<intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="smsto"/></intent>'
    '<intent><action android:name="android.media.action.IMAGE_CAPTURE"/></intent>'
    '<intent><action android:name="android.intent.action.SHOW_ALARMS"/></intent>'
)
if 'android.intent.action.SHOW_ALARMS' not in s:
    if '<queries>' in s:
        s = s.replace('<queries>', '<queries>' + q_intents, 1)
    else:
        s = s.replace('<application', '<queries>' + q_intents + '</queries>\n    <application', 1)

blocker_components = '''
        <service android:name="com.jojo.study_companion.blocker.BlockerService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="student_self_control_app_blocker"/>
        </service>
        <activity android:name="com.jojo.study_companion.blocker.BlockActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Material.NoActionBar"
            android:launchMode="singleTask"
            android:taskAffinity=""
            android:excludeFromRecents="true"
            android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|smallestScreenSize"/>
        <receiver android:name="com.jojo.study_companion.blocker.BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
if 'com.jojo.study_companion.blocker.BlockerService' not in s:
    s = s.replace('</application>', blocker_components + '    </application>', 1)
man.write_text(s, encoding='utf8')

for f in (root / 'android/app/src/main').rglob('MainActivity.*'):
    t = f.read_text(encoding='utf8')
    t = t.replace('io.flutter.embedding.android.FlutterActivity',
                  'com.ryanheise.audioservice.AudioServiceActivity')
    t = t.replace('FlutterActivity', 'AudioServiceActivity')
    f.write_text(t, encoding='utf8')

# ───────────── اپ‌بلاکر: فایل‌های Kotlin ─────────────
src = pathlib.Path(__file__).resolve().parent.parent / 'android_src'
main_dir = root / 'android/app/src/main'
mains = sorted(main_dir.rglob('MainActivity.kt'))
if not mains:
    sys.exit('patch_android: MainActivity.kt پیدا نشد (اپ‌بلاکر به Kotlin نیاز دارد)')
mk = mains[0]
pkg_m = re.search(r'^package\s+([\w.]+)', mk.read_text(encoding='utf8'), re.M)
if not pkg_m:
    sys.exit('patch_android: package در MainActivity.kt پیدا نشد')
mk.write_text((src / 'kotlin' / 'MainActivity.kt').read_text(encoding='utf8').replace('__PKG__', pkg_m.group(1)), encoding='utf8')
bdir = main_dir / 'kotlin' / 'com' / 'jojo' / 'study_companion' / 'blocker'
bdir.mkdir(parents=True, exist_ok=True)
for kf in sorted((src / 'kotlin' / 'blocker').glob('*.kt')):
    (bdir / kf.name).write_text(kf.read_text(encoding='utf8'), encoding='utf8')
ddir = main_dir / 'res' / 'drawable'
ddir.mkdir(parents=True, exist_ok=True)
for xf in sorted((src / 'res' / 'drawable').glob('*.xml')):
    (ddir / xf.name).write_text(xf.read_text(encoding='utf8'), encoding='utf8')
print('blocker sources copied')

app = root / 'android/app'
kts, groovy = app / 'build.gradle.kts', app / 'build.gradle'

# ---- قوانین R8: بدون این‌ها اعلان‌ها و پخش‌کننده بعد از کوچک‌سازی می‌شکنند ----
(app / 'proguard-rules.pro').write_text("""-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.google.gson.** { *; }
-keep class androidx.work.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }
-keep class com.jojo.study_companion.blocker.** { *; }
-dontwarn com.google.android.play.core.**
""", encoding='utf8')

if kts.exists():
    g = kts.read_text(encoding='utf8')
    g = re.sub(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', g, count=1)
    # امضا: key.properties
    g = 'import java.util.Properties\nimport java.io.FileInputStream\n' + g
    g = re.sub(r'^android\s*\{', """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
""", g, count=1, flags=re.M)
    g, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', """signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")""", g, count=1)
    if n != 1 or 'signingConfigs.getByName("release")' not in g:
        sys.exit('patch_android: بلوک release در build.gradle.kts پیدا نشد؛ امضا اعمال نشد')
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n    implementation("androidx.core:core:1.12.0")\n}\n'
    kts.write_text(g, encoding='utf8')
else:
    g = groovy.read_text(encoding='utf8')
    g = re.sub(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', g, count=1)
    g = re.sub(r'^android\s*\{', """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
""", g, count=1, flags=re.M)
    g, n = re.subn(r'signingConfig\s*=?\s*signingConfigs\.debug', """signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'""", g, count=1)
    if n != 1 or 'signingConfigs.release' not in g:
        sys.exit('patch_android: بلوک release در build.gradle پیدا نشد؛ امضا اعمال نشد')
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n    implementation 'androidx.core:core:1.12.0'\n}\n"
    groovy.write_text(g, encoding='utf8')
print('android patched')
