#!/usr/bin/env python3
"""Configura android/ tras `flutter create` (Flutter 3.47+, Gradle Kotlin DSL).

    flutter create --platforms=android --org com.tuempresa --project-name tablero_app .
    python3 tool/bootstrap_android.py --package com.tuempresa.escaque \\
        --admob-app-id ca-app-pub-XXXX~YYYY

Aplica, de forma idempotente (se puede ejecutar varias veces):
  - namespace/applicationId, minSdk 24, desugaring, firma con android/key.properties;
  - flavors dev / qa / prod (sufijos .dev/.qa, nombre visible y host de invitaciones);
  - AndroidManifest: permisos, etiqueta, atrás predictivo, AdMob, canal de avisos,
    Analytics desactivado hasta el consentimiento y App Links (/j/CÓDIGO);
  - MainActivity en el paquete nuevo.
Lo que NO hace: google-services.json por flavor (FlutterFire) ni el plugin de
Crashlytics (lo añade FlutterFire); ver ENTORNOS_Y_DOMINIOS.md.
"""
import argparse, os, re, shutil, sys

MARK = '// escaque:bootstrap'
HOSTS = {'dev': 'escaque-qa.system-failed-tech.com', 'qa': 'escaque-qa.system-failed-tech.com',
         'prod': 'escaque.system-failed-tech.com'}
NAMES = {'dev': 'Escaque DEV', 'qa': 'Escaque QA', 'prod': 'Escaque'}
TEST_ADMOB = 'ca-app-pub-3940256099942544~3347511713'

def fail(msg):
    sys.exit(f'bootstrap_android: {msg}')

def patch_gradle(src, package):
    if MARK in src:
        return src, False
    if 'android {' not in src or 'defaultConfig {' not in src:
        fail('build.gradle.kts no tiene el formato esperado de Flutter')
    src = re.sub(r'namespace = "[^"]+"', f'namespace = "{package}"', src)
    src = re.sub(r'applicationId = "[^"]+"', f'applicationId = "{package}"', src)
    src = re.sub(r'minSdk = [^\n]+', 'minSdk = 24 // Firebase, notificaciones locales y Flutter 3.47', src)
    # Desugaring (flutter_local_notifications)
    src = src.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    # Firma: android/key.properties si existe; si no, la de depuración
    header = f'''{MARK}
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties().apply {{
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}}

'''
    src = header + src
    signing = '''    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("storeFile")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

'''
    flavors = '''    flavorDimensions += "env"
    productFlavors {
''' + ''.join(f'''        create("{e}") {{
            dimension = "env"
{'            applicationIdSuffix = ".' + e + '"' + chr(10) if e != 'prod' else ''}            resValue("string", "app_name", "{NAMES[e]}")
            manifestPlaceholders["inviteHost"] = "{HOSTS[e]}"
        }}
''' for e in ('dev', 'qa', 'prod')) + '''    }

'''
    src = src.replace('    buildTypes {', signing + flavors + '    buildTypes {', 1)
    src = re.sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
                 'signingConfig = if (keystoreProperties.containsKey("storeFile")) '
                 'signingConfigs.getByName("release") else signingConfigs.getByName("debug")', src)
    deps = '''
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
'''
    src = src.rstrip() + '\n' + deps
    return src, True

def patch_manifest(src, admob):
    if 'escaque:bootstrap' in src:
        return src, False
    perms = ('    <!-- escaque:bootstrap -->\n'
             '    <uses-permission android:name="android.permission.INTERNET"/>\n'
             '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n')
    src = src.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + perms, 1)
    src = re.sub(r'android:label="[^"]*"', 'android:label="@string/app_name"', src, count=1)
    src = src.replace('android:icon="@mipmap/ic_launcher">',
                      'android:icon="@mipmap/ic_launcher"\n        android:enableOnBackInvokedCallback="true">', 1)
    meta = f'''        <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="{admob}"/>
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="turnos"/>
        <!-- Google Play Games (logros y clasificaciones) -->
        <meta-data android:name="com.google.android.gms.games.APP_ID" android:value="@string/game_services_project_id"/>
        <!-- Analytics: nada se envía hasta el consentimiento (OPERACION.md, 5) -->
        <meta-data android:name="firebase_analytics_collection_enabled" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_analytics_storage" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_storage" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_user_data" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_personalization_signals" android:value="false"/>
'''
    src = src.replace('        <activity\n', meta + '        <activity\n', 1)
    links = '''            <!-- Enlaces de invitación: https://<web del entorno>/j/CÓDIGO -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="${inviteHost}" android:pathPrefix="/j/"/>
            </intent-filter>
        </activity>'''
    if src.count('        </activity>') != 1:
        fail('AndroidManifest.xml no tiene una sola <activity>')
    src = src.replace('        </activity>', links, 1)
    return src, True

def move_activity(app_dir, package):
    kotlin = os.path.join(app_dir, 'src', 'main', 'kotlin')
    found = [os.path.join(r, f) for r, _, fs in os.walk(kotlin) for f in fs if f == 'MainActivity.kt']
    if len(found) != 1:
        fail(f'se esperaba un MainActivity.kt, hay {len(found)}')
    target_dir = os.path.join(kotlin, *package.split('.'))
    target = os.path.join(target_dir, 'MainActivity.kt')
    src = open(found[0]).read()
    src = re.sub(r'^package [\w.]+', f'package {package}', src, count=1, flags=re.M)
    os.makedirs(target_dir, exist_ok=True)
    open(target, 'w').write(src)
    if os.path.abspath(found[0]) != os.path.abspath(target):
        os.remove(found[0])
        d = os.path.dirname(found[0])
        while d != kotlin and not os.listdir(d):
            os.rmdir(d); d = os.path.dirname(d)
    return target

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--package', required=True, help='applicationId base, p. ej. com.tuempresa.escaque')
    ap.add_argument('--admob-app-id', default=TEST_ADMOB, help='ID de app de AdMob (por defecto, el de prueba)')
    ap.add_argument('--play-games-project-id', default='',
                    help='ID de proyecto de Play Games (número; Play Console → Play Games Services → Configuración)')
    ap.add_argument('--root', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    a = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+', a.package):
        fail('paquete no válido')
    app_dir = os.path.join(a.root, 'android', 'app')
    gradle = os.path.join(app_dir, 'build.gradle.kts')
    manifest = os.path.join(app_dir, 'src', 'main', 'AndroidManifest.xml')
    if not os.path.exists(gradle):
        fail('no existe android/app/build.gradle.kts: ejecuta antes flutter create (Flutter 3.47+, Kotlin DSL)')
    # Recurso con el ID de proyecto de Play Games («0» = sin configurar).
    values = os.path.join(app_dir, 'src', 'main', 'res', 'values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'games-ids.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                f'    <string name="game_services_project_id" translatable="false">{a.play_games_project_id or "0"}</string>\n'
                '</resources>\n')
    for path, fn in ((gradle, lambda s: patch_gradle(s, a.package)), (manifest, lambda s: patch_manifest(s, a.admob_app_id))):
        s, changed = fn(open(path).read())
        if changed:
            shutil.copy(path, path + '.orig')
            open(path, 'w').write(s)
        print(('configurado ' if changed else 'ya estaba ') + os.path.relpath(path, a.root))
    print('MainActivity:', os.path.relpath(move_activity(app_dir, a.package), a.root))
    print('Siguiente: google-services.json por flavor (ENTORNOS_Y_DOMINIOS.md, 4.2) y dart run flutter_launcher_icons')

if __name__ == '__main__':
    main()
