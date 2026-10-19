# Escaque — guía de configuración completa

De cero a la app publicada: herramientas, proyecto Android, Firebase, servidor en Cloud Run,
notificaciones, App Check, AdMob y Google Play. Sigue las secciones en orden: varias dependen de
datos que se obtienen en una anterior.

Esta guía monta **un entorno**. Para dev, qa y prod con tus subdominios, sigue después
[ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md), y para automatizar pruebas y despliegues,
[CI_CD.md](CI_CD.md).

Convenciones:

- `$VARIABLE` es un valor que defines tú en el paso 0.3 y reutilizas en la misma terminal.
- Los bloques `bash` se ejecutan tal cual (en Windows, usa Git Bash o WSL).
- ✅ marca una comprobación: no sigas si falla.

---

## Índice

0. [Antes de empezar](#0-antes-de-empezar)
1. [Herramientas](#1-herramientas)
2. [Código y verificación local](#2-código-y-verificación-local)
3. [Proyecto Android](#3-proyecto-android)
4. [Firma de la app](#4-firma-de-la-app)
5. [Firebase: proyecto y app Android](#5-firebase-proyecto-y-app-android)
6. [Firebase Authentication](#6-firebase-authentication)
7. [Cloud Firestore](#7-cloud-firestore)
8. [Cloud Messaging (notificaciones)](#8-cloud-messaging-notificaciones)
9. [Servidor en Cloud Run](#9-servidor-en-cloud-run)
10. [Cloud Scheduler (plazos, recordatorios y clasificaciones)](#10-cloud-scheduler-plazos-recordatorios-y-clasificaciones)
11. [AdMob y consentimiento](#11-admob-y-consentimiento)
12. [Compilar la app](#12-compilar-la-app)
13. [Prueba completa](#13-prueba-completa)
14. [Google Play Console](#14-google-play-console)
15. [App Check](#15-app-check)
16. [Activar App Check en modo estricto](#16-activar-app-check-en-modo-estricto)
17. [Mantenimiento](#17-mantenimiento)
18. [Problemas frecuentes](#18-problemas-frecuentes)

---

## 0. Antes de empezar

### 0.1 Cuentas

| Cuenta | Para qué | Coste |
| --- | --- | --- |
| Cuenta de Google | Firebase, Google Cloud, AdMob, Play Console | Gratis |
| Facturación de Google Cloud (plan **Blaze** de Firebase) | Cloud Run, Cloud Build, Artifact Registry, Cloud Scheduler | De pago por uso, con nivel gratuito; con pocos usuarios suele ser casi cero |
| Google Play Console | Publicar la app | Pago único de registro |
| AdMob | Anuncios | Gratis |

Necesitas además una **web** (aunque sea una página sencilla) para: política de privacidad,
solicitud de borrado de cuenta y el archivo `app-ads.txt` de AdMob.

### 0.2 Qué vas a montar

```
App Android (Flutter + Flame)
  ├─ Firebase Auth ............ cuentas (Google y correo)
  ├─ Firestore (solo lectura) . partidas, perfil, amigos, valoración, clasificaciones
  ├─ FCM ...................... notificaciones
  ├─ App Check ................ verifica que las peticiones vienen de tu app
  ├─ AdMob + UMP .............. anuncios y consentimiento
  ├─ Google Play Billing ...... compra «quitar anuncios»
  ├─ Google Play Games ........ logros y clasificaciones (opcional)
  ├─ Hosting (landing) ........ invitaciones /j/CÓDIGO y catálogo de problemas
  └─ HTTPS ──► tablero_server (Cloud Run, Dart)
                 ├─ valida jugadas con tablero_engine
                 ├─ amigos, retos, frases y valoraciones Glicko-2
                 ├─ verifica compras con la Google Play Developer API
                 ├─ escribe en Firestore
                 └─ envía notificaciones FCM
Cloud Scheduler ─(cada 15 min)─► plazos, recordatorios y valoraciones pendientes
Cloud Scheduler ─(a diario)────► clasificaciones
Google Play ─(Pub/Sub, push)───► reembolsos de compras
```

### 0.3 Variables

Elige los valores y guárdalos en un archivo `variables.sh` fuera del repositorio. Al empezar cada
sesión de terminal, ejecuta `source variables.sh`.

```bash
# variables.sh
export ENV_NAME="dev"                           # dev, qa o prod (ver ENTORNOS_Y_DOMINIOS.md)
export PROJECT_ID="escaque-app"                 # id del proyecto de Firebase/Google Cloud (único en el mundo)
export REGION="southamerica-east1"              # São Paulo: Firestore, Cloud Run y Scheduler en la misma región
export APP_ID_ANDROID="com.tuempresa.escaque"   # applicationId de Android; no se puede cambiar tras publicar
# Se rellenan más adelante:
export PROJECT_NUMBER=""                        # paso 5.1
export URL=""                                   # paso 9.7
```

> La ubicación de Firestore **no se puede cambiar** después. Si prefieres otra región, cambia
> `REGION` ahora y úsala igual en todos los pasos.

---

## 1. Herramientas

| Herramienta | Versión | Comprobación |
| --- | --- | --- |
| Flutter (canal stable) | **3.47** o superior (Dart 3.11+). Necesario: apunta a Android 16 (API 36), que Google Play exige desde el 31/08/2026 | `flutter --version` |
| Android Studio | Reciente, con Android SDK Platform **36**, Build-Tools y Command-line Tools | `flutter doctor` |
| JDK | 17 (el que trae Android Studio sirve) | `java -version` |
| Git | Cualquiera reciente | `git --version` |
| Node.js | LTS | `node -v` |
| Firebase CLI | Última | `firebase --version` |
| FlutterFire CLI | Última | `flutterfire --version` |
| Google Cloud CLI | Última | `gcloud --version` |
| Python 3 + cairosvg | Opcional: solo para regenerar iconos | `python3 -c "import cairosvg"` |

Instalación de las CLI:

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
# Google Cloud CLI: https://cloud.google.com/sdk/docs/install (instalador de tu sistema)
```

Asegúrate de que `~/.pub-cache/bin` está en el `PATH` (FlutterFire lo indica al instalarse).

✅ `flutter doctor` sin errores en «Flutter», «Android toolchain» y «Android Studio».

```bash
flutter doctor --android-licenses   # acepta todas
```

---

## 2. Código y verificación local

### 2.1 Estructura

Es un monorepo: un único repositorio Git. El servidor y la app dependen del motor por ruta
relativa (`../tablero_engine`).

```
escaque/
├─ .github/workflows/   CI y despliegues
├─ firebase/            reglas e índices de Firestore
├─ firebase.json        Firestore + Hosting (landing y API)
├─ landing/             web en Astro
├─ tablero_engine/
├─ tablero_server/
└─ tablero_app/
```

Donde la guía dice `proyectos/`, entiende la raíz `escaque/`.

### 2.2 Motor

```bash
cd proyectos/tablero_engine
dart pub get
dart analyze
dart test
```

✅ Cero errores en `dart analyze` y todos los tests en verde (incluye perft de ajedrez y damas).

### 2.3 Servidor

```bash
cd ../tablero_server
dart pub get
dart analyze
dart test
```

✅ Todos los tests en verde. No necesitan red ni Firebase.

### 2.4 App (solo Dart, todavía sin Android)

```bash
cd ../tablero_app
flutter pub get
flutter analyze
flutter test
```

✅ Si `flutter analyze` muestra errores, corrígelos antes de seguir (son los únicos pasos donde
puede aparecer algún desajuste de API entre versiones de paquetes).

---

## 3. Proyecto Android

### 3.1 Generar la carpeta `android/`

Desde `tablero_app/`. No toca `lib/`, `assets/` ni `pubspec.yaml`:

```bash
flutter create --platforms=android --org com.tuempresa --project-name tablero_app .
```

### Atajo: configuración automática

Los pasos 3.2 a 3.4 (y los flavors de [ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md), paso 4.1)
los aplica un script, probado con las plantillas de Flutter 3.47.7:

```bash
python3 tool/bootstrap_android.py --package $APP_ID_ANDROID --admob-app-id ca-app-pub-XXXX~YYYY
```

Es idempotente (puedes ejecutarlo de nuevo) y guarda una copia `.orig` de cada archivo que cambia.
Si lo usas, salta al paso 3.5; los pasos manuales quedan como referencia de lo que hace.

### 3.2 Identificador de la app

Según la versión de Flutter, el archivo es `android/app/build.gradle.kts` (Kotlin) o
`android/app/build.gradle` (Groovy). Cambia `namespace` y `applicationId` al valor de
`$APP_ID_ANDROID`:

Kotlin (`build.gradle.kts`):

```kotlin
android {
    namespace = "com.tuempresa.escaque"
    defaultConfig {
        applicationId = "com.tuempresa.escaque"
        minSdk = 24
        // targetSdk y compileSdk: los de Flutter 3.47 (36). Play exige API 36.
    }
}
```

Groovy (`build.gradle`):

```groovy
android {
    namespace "com.tuempresa.escaque"
    defaultConfig {
        applicationId "com.tuempresa.escaque"
        minSdkVersion 24
    }
}
```

Mueve también `MainActivity.kt` a la carpeta del nuevo paquete y actualiza su línea `package`:

```bash
OLD=android/app/src/main/kotlin/com/tuempresa/tablero_app
NEW=android/app/src/main/kotlin/com/tuempresa/escaque
mkdir -p "$NEW" && git mv "$OLD/MainActivity.kt" "$NEW/" 2>/dev/null || mv "$OLD/MainActivity.kt" "$NEW/"
sed -i.bak 's/^package .*/package com.tuempresa.escaque/' "$NEW/MainActivity.kt" && rm "$NEW/MainActivity.kt.bak"
```

`minSdk 24` (Android 7.0) lo exigen las versiones actuales de Firebase, de las notificaciones locales y de Flutter. Comprueba también que `targetSdk` y `compileSdk` valen 36 (`flutter.targetSdkVersion` en Flutter 3.47).

### 3.3 Desugaring (lo necesita `flutter_local_notifications`)

Kotlin:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Groovy:

```groovy
android {
    compileOptions {
        coreLibraryDesugaringEnabled true
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

### 3.4 `AndroidManifest.xml`

Archivo `android/app/src/main/AndroidManifest.xml`. Añade los permisos antes de `<application>`,
cambia la etiqueta y añade los `meta-data` dentro de `<application>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <application
        android:label="Escaque"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:enableOnBackInvokedCallback="true">

        <!-- AdMob: ID de prueba de Google. Cámbialo por el tuyo en el paso 11.2 -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-3940256099942544~3347511713"/>

        <!-- Analytics: nada se envía hasta que la app decide según el
             consentimiento (OPERACION.md, 5) -->
        <meta-data android:name="firebase_analytics_collection_enabled" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_analytics_storage" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_storage" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_user_data" android:value="false"/>
        <meta-data android:name="google_analytics_default_allow_ad_personalization_signals" android:value="false"/>

        <!-- Canal de las notificaciones de partida (la app lo crea al arrancar) -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="turnos"/>

        <!-- Dentro de la <activity> que generó Flutter, añade los enlaces de
             invitación (Android App Links). El host es la web del entorno. -->
        <!--
        <intent-filter android:autoVerify="true">
            <action android:name="android.intent.action.VIEW"/>
            <category android:name="android.intent.category.DEFAULT"/>
            <category android:name="android.intent.category.BROWSABLE"/>
            <data android:scheme="https" android:host="escaque.system-failed-tech.com" android:pathPrefix="/j/"/>
        </intent-filter>
        -->
    </application>
</manifest>
```

Android 16 obliga a dibujar de borde a borde y usa el gesto «atrás predictivo»: la app ya usa
áreas seguras en todas las pantallas y la partida intercepta «atrás» para guardar antes de salir.

### 3.5 Icono del lanzador

```bash
dart run flutter_launcher_icons
```

Genera el icono adaptativo (fondo, primer plano y monocromo) desde `assets/icon/`. Para cambiar el
diseño, edita `tablero_app/tool/brand/appicon.py` y ejecuta `python3 tool/brand/appicon.py` desde `tablero_app` antes.

✅ `flutter run` en un emulador arranca la app y muestra la presentación inicial. El modo online
dirá que no está configurado: es lo esperado hasta el paso 12.

---

## 4. Firma de la app

### 4.1 Clave de subida

Guárdala fuera del repositorio y haz una copia de seguridad: sin ella no podrás actualizar la app
(Play App Signing permite recuperarla, pero con un trámite).

```bash
keytool -genkey -v -keystore ~/claves/escaque-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 4.2 `android/key.properties`

```properties
storePassword=LA_CONTRASEÑA_DEL_ALMACÉN
keyPassword=LA_CONTRASEÑA_DE_LA_CLAVE
keyAlias=upload
storeFile=/ruta/absoluta/a/claves/escaque-upload.jks
```

Ya está en `.gitignore`.

### 4.3 Usarla en Gradle

Kotlin (`android/app/build.gradle.kts`), al principio del archivo:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
```

Dentro de `android { }`:

```kotlin
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

Groovy (`android/app/build.gradle`): antes de `android { }`:

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Dentro de `android { }`:

```groovy
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

### 4.4 Huellas SHA-1 y SHA-256

Las necesita Firebase para el acceso con Google y para App Check.

```bash
cd android && ./gradlew signingReport && cd ..
```

Anota SHA-1 y SHA-256 de la variante `debug` y de la `release` (clave de subida). La tercera pareja
(clave de firma de Play) se obtiene en el paso 14.3.

---

## 5. Firebase: proyecto y app Android

### 5.1 Proyecto

1. Entra en la consola de Firebase → **Agregar proyecto** → nombre «Escaque».
   - Si usas `PROJECT_ID` propio, edítalo en la pantalla de nombre.
   - Google Analytics: opcional (la app no lo usa todavía).
2. **Configuración del proyecto** (rueda dentada) → General: copia el **Número de proyecto** a
   `PROJECT_NUMBER` en `variables.sh`.
3. Abajo a la izquierda, **Actualizar** → plan **Blaze** y vincula una cuenta de facturación.
4. Google Cloud Console → Facturación → **Presupuestos y alertas** → crea un presupuesto mensual
   (por ejemplo, 10 USD) con alertas al 50 %, 90 % y 100 %.

### 5.2 Iniciar sesión en las CLI

```bash
source variables.sh
firebase login
gcloud auth login
gcloud config set project $PROJECT_ID
gcloud auth application-default login   # solo si vas a ejecutar el servidor en tu ordenador
```

### 5.3 Registrar la app Android con FlutterFire

Desde `tablero_app/`:

```bash
flutterfire configure --project=$PROJECT_ID --platforms=android \
  --android-package-name=$APP_ID_ANDROID
```

Hace tres cosas: registra la app en Firebase, descarga `android/app/google-services.json` y añade el
plugin de Google Services a Gradle. También crea `lib/firebase_options.dart`, que la app no necesita
(se inicializa con `google-services.json`); puedes dejarlo o borrarlo.

✅ Existe `android/app/google-services.json` y su `package_name` es `$APP_ID_ANDROID`.

FlutterFire añade también el plugin de Gradle de **Crashlytics** (porque `firebase_crashlytics` está
en `pubspec.yaml`). Compruébalo; si falta, añádelo a mano:

```kotlin
// android/settings.gradle.kts, dentro de plugins { }
id("com.google.gms.google-services") version "4.4.3" apply false
id("com.google.firebase.crashlytics") version "3.0.6" apply false

// android/app/build.gradle.kts, dentro de plugins { }
id("com.google.gms.google-services")
id("com.google.firebase.crashlytics")
```

Usa las versiones que escriba FlutterFire si son más recientes.

### 5.4 Añadir las huellas

Consola de Firebase → Configuración del proyecto → General → tu app Android →
**Agregar huella digital**: añade **SHA-1 y SHA-256** de debug y de release (paso 4.4).

Después, **vuelve a descargar `google-services.json`** desde esa misma pantalla y sustituye el de
`android/app/`. Cada vez que añadas huellas hay que descargarlo de nuevo: el acceso con Google
depende de los clientes OAuth que van dentro.

---

## 6. Firebase Authentication

Consola → **Authentication** → Comenzar.

### 6.1 Proveedores

Pestaña **Método de acceso**:

1. **Google** → Habilitar → nombre público del proyecto «Escaque» → correo de asistencia → Guardar.
2. **Correo electrónico/contraseña** → Habilitar (solo la primera opción; «Vínculo de correo
   electrónico» no) → Guardar.
3. **Anónimo**: debe quedar **deshabilitado**. El servidor y las reglas rechazan sesiones anónimas.

### 6.2 Configuración

Pestaña **Configuración**:

1. **Política de contraseñas** → exigir → longitud mínima 8 → Guardar.
2. **Protección contra la enumeración de correos electrónicos** → activada (viene activada en
   proyectos nuevos).
3. **Dominios autorizados**: deja los que vienen.

### 6.3 Plantillas de correo

Pestaña **Plantillas**:

1. Abajo, **Idioma de la plantilla** → Español.
2. Revisa «Verificación de dirección de correo electrónico» y «Restablecimiento de contraseña»:
   nombre del remitente «Escaque».

### 6.4 Pantalla de consentimiento de OAuth

Google Cloud Console → APIs y servicios → **Pantalla de consentimiento de OAuth**: nombre de la app
«Escaque», correo de asistencia, logotipo (`store/play_icon_512.png`) y enlace a la política de
privacidad. Publícala en producción para que cualquiera pueda entrar con Google.

La app usa `google_sign_in` 7, que en Android funciona con **Credential Manager**. Necesita que
`google-services.json` contenga un cliente OAuth **web** (`client_type: 3`): se crea al activar el
proveedor de Google. Si activaste Google después de descargar el archivo, descárgalo otra vez.

✅ En la app (en un emulador con Google Play), «Continuar con Google» abre el selector de cuentas y
termina en «Elige tu nombre de usuario». Si dice «El acceso con Google no está bien configurado», o
se cancela solo tras elegir la cuenta, revisa las huellas (5.4) y el cliente web.

---

## 7. Cloud Firestore

### 7.1 Crear la base de datos

Consola → **Firestore Database** → Crear base de datos → ubicación **`$REGION`**
(southamerica-east1) → **modo de producción**.

### 7.2 Reglas e índices

Desde la raíz del monorepo (donde están `firebase.json` y `.firebaserc`; ver
[ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md) para los tres entornos):

```bash
cp .firebaserc.example .firebaserc   # pon tus IDs de proyecto y de sitio
firebase deploy --project dev --only firestore:rules,firestore:indexes
```

✅ Consola → Firestore → **Reglas**: muestra las publicadas (solo lectura de partidas, `usernames`
cerrado). **Índices**: tres compuestos sobre `games`; espera a que pasen de «Compilando» a
«Habilitado» (unos minutos).

---

## 8. Cloud Messaging (notificaciones)

1. Consola → Configuración del proyecto → **Cloud Messaging**: comprueba que **API de Firebase
   Cloud Messaging (V1)** aparece **Habilitada**. La API heredada no hace falta.
2. No hay que copiar ninguna clave de servidor: el servidor envía con su cuenta de servicio (paso 9.4).
3. El canal «Turnos» lo crea la app al arrancar y el `meta-data` del paso 3.4 lo hace canal por defecto.

---

### 8.1 Crashlytics (errores de la app)

1. Consola → **Crashlytics** → Habilitar.
2. Compila en modo release e instala (en depuración los informes están desactivados a propósito).
3. Fuerza un error de prueba, por ejemplo con un botón temporal que ejecute
   `FirebaseCrashlytics.instance.crash()`, ábrela de nuevo y espera unos minutos.

✅ El error aparece en Crashlytics con la clave `env` y el uid de la cuenta (solo el uid: ni correo
ni nombre). La persona puede desactivar los informes en Ajustes → Privacidad.

Las versiones de producción salen ofuscadas: el CI sube los símbolos de Dart a Crashlytics para que
las trazas sean legibles (ver `CI_CD.md`). A mano:

```bash
firebase crashlytics:symbols:upload --app=ID_DE_LA_APP_ANDROID build/symbols
```

### 8.2 Remote Config (ajustes sin publicar versión)

Consola → **Remote Config** → crea estos parámetros y publica:

| Clave | Tipo | Valor inicial | Para qué |
| --- | --- | --- | --- |
| `min_supported_build` | Número | `0` | Versiones con número de compilación menor deben actualizar (pantalla bloqueante con actualización desde Play). Súbelo solo si cambias el servidor de forma incompatible |
| `online_enabled` | Booleano | `true` | Interruptor de emergencia: `false` oculta el modo online con el mensaje de abajo, al momento (tiempo real) |
| `online_message` | Cadena | «El modo online está en mantenimiento. Vuelve en un rato.» | Texto del interruptor |
| `interstitial_every_games` | Número | `2` | Cada cuántas partidas terminadas se puede mostrar un intersticial (1–10) |

El número de compilación de cada versión lo pone el CI (`1000 + ejecución`) y se ve en Play Console.

### 8.3 Operación: alertas, copias, carga y estadísticas

Cuando el servidor esté desplegado (paso 9), sigue [OPERACION.md](OPERACION.md): alertas de
Cloud Monitoring, copias de Firestore, pruebas de carga y Analytics con consentimiento.

## 9. Servidor en Cloud Run

Todo desde la carpeta `proyectos/` (la que contiene los tres proyectos), con `source variables.sh`.

### 9.1 APIs

```bash
gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  firestore.googleapis.com fcm.googleapis.com cloudscheduler.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com \
  firebaseappcheck.googleapis.com playintegrity.googleapis.com
```

### 9.2 Repositorio de imágenes

```bash
gcloud artifacts repositories create tablero \
  --repository-format=docker --location=$REGION \
  --description="Imágenes de tablero_server"
```

### 9.3 Permisos de Cloud Build

En proyectos recientes, Cloud Build usa la cuenta de servicio de Compute Engine. Dale permiso para
escribir imágenes y registros:

```bash
BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for ROLE in roles/artifactregistry.writer roles/logging.logWriter roles/storage.objectViewer; do
  gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$BUILD_SA" --role=$ROLE
done
```

### 9.4 Cuentas de servicio

```bash
# Servidor: lee/escribe Firestore y envía FCM
gcloud iam service-accounts create tablero-api --display-name="Escaque API"
export API_SA="tablero-api@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$API_SA" --role=roles/datastore.user
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$API_SA" --role=roles/firebasecloudmessaging.admin
# Revocación de tokens en operaciones sensibles (OPERACION.md, 3)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$API_SA" --role=roles/firebaseauth.viewer

# Cloud Scheduler: solo firma el token OIDC con el que llama al servidor
gcloud iam service-accounts create tablero-scheduler --display-name="Escaque Scheduler"
export SCHED_SA="tablero-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
# Tu usuario necesita poder «actuar como» esa cuenta para crear el trabajo (paso 10)
gcloud iam service-accounts add-iam-policy-binding $SCHED_SA \
  --member="user:$(gcloud config get-value account)" --role=roles/iam.serviceAccountUser
```

Añade `API_SA` y `SCHED_SA` a `variables.sh`.

### 9.5 Compilar la imagen

```bash
gcloud builds submit --config tablero_server/cloudbuild.yaml \
  --substitutions=_REGION=$REGION .
```

El build ejecuta `dart test` antes de compilar: si un test falla, no se publica la imagen.

✅ Termina con `SUCCESS` y la imagen aparece en Artifact Registry → `tablero` → `tablero-api`.

### 9.6 Desplegar

Primero en modo App Check `monitor` (registra, pero no bloquea):

```bash
gcloud run deploy tablero-api \
  --image=$REGION-docker.pkg.dev/$PROJECT_ID/tablero/tablero-api:latest \
  --region=$REGION --service-account=$API_SA \
  --allow-unauthenticated --min-instances=0 --max-instances=5 \
  --memory=512Mi --cpu=1 --concurrency=40 --timeout=30 \
  --set-env-vars=PROJECT_ID=$PROJECT_ID,PROJECT_NUMBER=$PROJECT_NUMBER,APP_CHECK=monitor,SCHEDULER_SA=$SCHED_SA,SERVICE_URL=pendiente,MOVE_TIME_HOURS=72,ENVIRONMENT=$ENV_NAME
```

`--allow-unauthenticated` es correcto: el servidor verifica él mismo el token de Firebase de cada
jugador, el de App Check y el OIDC de Scheduler.

### 9.7 URL del servicio

```bash
export URL=$(gcloud run services describe tablero-api --region=$REGION --format='value(status.url)')
echo $URL      # guárdala en variables.sh
gcloud run services update tablero-api --region=$REGION --update-env-vars=SERVICE_URL=$URL
```

### 9.8 Comprobar

```bash
curl -s $URL/healthz
# ok
curl -s -X POST $URL/v1/games -H 'content-type: application/json' -d '{}'
# {"error":"unauthorized","message":"Tu sesión no es válida. Vuelve a abrir la app."}
curl -s -X POST $URL/v1/tasks/deadlines
# {"error":"unauthorized",...}
```

Registros:

```bash
gcloud run services logs read tablero-api --region=$REGION --limit=50
```

---

## 10. Cloud Scheduler (plazos, recordatorios y clasificaciones)

```bash
gcloud scheduler jobs create http tablero-deadlines \
  --location=$REGION --schedule='*/15 * * * *' --time-zone='America/Lima' \
  --uri=$URL/v1/tasks/deadlines --http-method=POST \
  --oidc-service-account-email=$SCHED_SA --oidc-token-audience=$URL

# Clasificaciones (Glicko-2): las 100 mejores de cada juego, cada día a las 4:00
gcloud scheduler jobs create http tablero-leaderboards \
  --location=$REGION --schedule='0 4 * * *' --time-zone='America/Lima' \
  --uri=$URL/v1/tasks/leaderboards --http-method=POST \
  --oidc-service-account-email=$SCHED_SA --oidc-token-audience=$URL
```

El trabajo de plazos también recoge las partidas valoradas que hubieran quedado sin aplicar
(«barrido»), así que ninguna valoración se pierde aunque el servidor caiga al terminar una partida.

Probarlo sin esperar:

```bash
gcloud scheduler jobs run tablero-deadlines --location=$REGION
gcloud run services logs read tablero-api --region=$REGION --limit=10
```

✅ En los registros aparece `POST /v1/tasks/deadlines` con estado 200.

Cada 15 minutos: recordatorio 24 h antes de que venza el plazo (72 h por jugada), derrota por tiempo
al vencer (en ajedrez, tablas si el rival no puede dar mate) y cancelación de partidas en espera de
más de 7 días.

---

## 11. AdMob y consentimiento

### 11.1 App y bloques de anuncios

1. AdMob → Apps → **Añadir app** → Android → «¿Está publicada?» No (la vincularás tras publicar) →
   nombre «Escaque».
2. Copia el **ID de app** (`ca-app-pub-…~…`).
3. **Bloques de anuncios** → crea tres:

| Bloque | Formato | Ajustes |
| --- | --- | --- |
| Banner Inicio | Banner (la app usa el tamaño adaptativo anclado) | Por defecto |
| Entre partidas | Intersticial | Por defecto |
| Pista | Bonificado | Recompensa: 1 «pista» |

### 11.2 IDs en la app

1. El **ID de app** va en el `meta-data` del paso 3.4 (sustituye el de prueba).
2. Los tres **IDs de bloque** van en `config/prod.json` (paso 12.1). Sin ellos, la app usa los IDs
   de prueba de Google.

### 11.3 Privacidad y mensajes

AdMob → **Privacidad y mensajes**:

1. **Mensaje del RGPD** (normativas europeas) → crear → selecciona la app → idioma español →
   socios publicitarios (los de Google por defecto) → **Publicar**.
2. **Mensaje de normativas de estados de EE. UU.** → crear y publicar igual.

Sin mensaje publicado, UMP no muestra formulario y en el EEE no se piden anuncios.

### 11.4 Dispositivos de prueba

AdMob → Configuración → **Dispositivos de prueba** → añade tu teléfono (el ID de publicidad está en
Ajustes de Android → Google → Anuncios). Nunca toques anuncios reales propios.

Para probar el consentimiento como si estuvieras en Europa, en `lib/ads/ads_service.dart`, dentro de
`init()`, sustituye temporalmente `ConsentRequestParameters()` por:

```dart
ConsentRequestParameters(
  consentDebugSettings: ConsentDebugSettings(
    debugGeography: DebugGeography.debugGeographyEea,
    testIdentifiers: ['EL_ID_QUE_SALE_EN_LOGCAT'],
  ),
)
```

El ID aparece en `flutter logs` la primera vez. Quítalo antes de publicar.

### 11.5 `app-ads.txt`

AdMob → Apps → tu app → **app-ads.txt**: copia la línea y publícala en
`https://tu-web/app-ads.txt`. La web debe ser la misma que pongas como «sitio web del desarrollador»
en Play Console (paso 14.4).

---

## 12. Compilar la app

### 12.1 Archivos de configuración

```bash
cp config/dev.json.example config/dev.json     # pon tu $URL
cp config/prod.json.example config/prod.json   # $URL y los tres IDs de AdMob
```

### 12.2 Desarrollo

```bash
flutter run --dart-define-from-file=config/dev.json
```

### 12.3 Versión para Play

1. Sube la versión en `pubspec.yaml` en cada entrega: `version: 1.0.0+1` → `1.0.1+2` (el número tras
   `+` debe crecer siempre).
2. Compila:

```bash
flutter build appbundle --release \
  --dart-define-from-file=config/prod.json \
  --obfuscate --split-debug-info=build/symbols
```

✅ `build/app/outputs/bundle/release/app-release.aab`. Guarda `build/symbols` de cada versión para
poder leer errores ofuscados.

---

## 13. Prueba completa

Con dos dispositivos (o uno y un emulador con Google Play), compilando con `config/dev.json`:

| # | Prueba | Resultado esperado |
| --- | --- | --- |
| 1 | Primer arranque | Presentación de 3 páginas |
| 2 | «Jugar sin cuenta» → ajedrez contra IA nivel 5 | La IA responde en 3 s o menos |
| 3 | Arrastrar una pieza a una casilla no válida | Vuelve a su sitio |
| 4 | Cerrar la app a mitad de partida y volver | «Continuar» en Inicio |
| 5 | Ajustes → Cuenta → crear cuenta con correo | Pide nombre de usuario y luego verificar el correo |
| 6 | Abrir el enlace del correo y volver | La app lo detecta sola |
| 7 | Segundo dispositivo: entrar con Google | Pide nombre de usuario; uno ya usado aparece como ocupado |
| 8 | Dispositivo A: crear partida online | Código de 6 caracteres; aviso de permiso de notificaciones |
| 9 | Dispositivo B: unirse con el código | A recibe «@b se unió a tu partida» |
| 10 | Mover en B con la app de A cerrada | A recibe «Te toca contra @b»; al tocarla abre la partida |
| 11 | Ofrecer tablas y rechazar; volver a ofrecer enseguida | El segundo intento indica que hay que esperar |
| 12 | Rendirse | El rival recibe «Has ganado» |
| 13 | Plazos: `gcloud run services update tablero-api --region=$REGION --update-env-vars=MOVE_TIME_HOURS=1`, esperar y ejecutar el trabajo de Scheduler | Recordatorio y derrota por tiempo. **Vuelve a 72** al terminar |
| 14 | Anuncios | Banner en Inicio; intersticial cada 2 partidas al salir del resultado; «Pista» con anuncio bonificado. Antes, la tarjeta «¿Nos ayudas a mejorar Escaque?» aparece una vez en Inicio |
| 15 | Ajustes → Eliminar cuenta | Partidas online cerradas, el nombre de usuario queda libre |
| 16 | Modo avión durante una partida online | Aviso de error; al volver la conexión, se sincroniza |
| 17 | Damas chinas online (2 jugadores) | Crear, unirse y mover como en ajedrez |
| 18 | Al terminar una partida online, «Revancha» | Se abre una partida nueva con los colores cambiados; el rival recibe el aviso |
| 19 | Damas internacionales con dos capturas posibles al mismo destino | La app pregunta por dónde capturar |
| 20 | Con TalkBack activo, mover | Se anuncia la jugada («Blancas: caballo a f3») |
| 21 | Ajustes de Android → Accesibilidad → Quitar animaciones | Las piezas cambian de casilla sin animación |
| 22 | Remote Config `online_enabled = false` | El lobby muestra el mensaje de mantenimiento sin reiniciar la app |
| 23 | Remote Config `min_supported_build` mayor que tu versión | Pantalla «Actualiza Escaque» (la actualización real solo funciona instalada desde Play; usa *Uso compartido interno de apps* para probarla) |
| 24 | Crear una partida online, copiar la invitación y abrir el enlace en el otro teléfono | Se abre Escaque y entra directamente en la partida; sin la app, la web muestra el código y el enlace a Play. Comprueba la verificación con `adb shell pm get-app-links com.tuempresa.escaque` (dominio en `verified`) |
| 25 | Ajustes → Idioma → English | Toda la app en inglés sin perder la pantalla; una notificación de turno llega en inglés |
| 26 | Inicio → «Aprende a jugar» → una lección | Al hacer la jugada pedida, texto de acierto y «Siguiente lección» |
| 27 | Problemas → un golpe de damas | Tras la jugada correcta responde el motor; capturando se resuelve |
| 28 | Historial → una partida de ajedrez terminada → «Analizar la partida» | Barra de progreso, gráfica, errores marcados y «Jugada clave»; al volver, el análisis sigue ahí. En otra partida, «Detener» lo para al momento |
| 29 | Sala online → Amigos: A añade a B por @usuario; B acepta | B recibe el aviso de solicitud; al aceptar, A recibe «aceptó tu solicitud» |
| 30 | A reta a B a ajedrez valorado; jugáis al menos 10 jugadas cada uno y uno abandona | La partida empieza sin código; tras terminar, Clasificación muestra la valoración de cada uno (provisional) |
| 31 | En una partida online, «Frases» → «¡Suerte!» | El rival ve la frase unos segundos (y TalkBack la lee) |
| 32 | Ajustes → Sin anuncios → comprar con una cuenta de pruebas de licencia | «Gracias»; sin banners ni intersticiales; `users/{uid}.adFree` en `true` (paso 14.8) |
| 33 | Damas chinas a dos contra la IA en nivel 1 y en nivel 5 | El nivel 5 juega claramente mejor (antes de esta versión el nivel no cambiaba nada) |
| 34 | B reta a A; A, sin mover, toca «Rechazar reto» | La partida se cierra para los dos («reto rechazado»); B recibe el aviso. En Amigos, cada amigo muestra si te toca en alguna partida |
| 35 | Ajustes → «Frases del rival» desactivado | Las frases que te envían ya no aparecen en ninguna partida |

---

## 14. Google Play Console

### 14.1 Crear la app

Play Console → **Crear aplicación**:

- Nombre: **Escaque: Ajedrez y Damas**
- Idioma predeterminado: Español (Latinoamérica) o (España)
- App o juego: **Juego** · Gratuita
- Acepta las declaraciones.

### 14.2 Prueba interna

Prueba → **Prueba interna** → crear versión → acepta **Firma de aplicaciones de Play** → sube el
`.aab` del paso 12.3 → añade testers por correo → publica la versión.

### 14.3 Huellas de la clave de firma de Play

Configuración → **Integridad de la aplicación** → Firma de aplicaciones: copia **SHA-1 y SHA-256 de
la clave de firma de la app**.

1. Añádelas en Firebase (paso 5.4) y **vuelve a descargar `google-services.json`**.
2. Recompila (paso 12.3) y sube la nueva versión. Sin esto, el acceso con Google falla en las
   instalaciones desde Play aunque funcione en tu ordenador.

### 14.4 Ficha de Play Store

Crecer → **Ficha de Play Store**:

| Campo | Contenido |
| --- | --- |
| Textos (título, descripción breve y completa) | `tablero_app/store/listing.md`, en español e inglés. Añade el inglés en «Gestionar traducciones» |
| Icono | `store/play_icon_512.png` |
| Gráfico destacado | `store/feature_graphic_1024x500.png` (español) y `store/feature_graphic_en_1024x500.png` (inglés) |
| Capturas de teléfono | 2 a 8 por idioma (Ajustes → Idioma), por ejemplo Inicio, partida de ajedrez, damas con captura obligatoria, online, problema del día |
| Capturas de tablet de 7" y 10" | Recomendadas: la app tiene diseño para tablet (partida a dos columnas) |
| Categoría | Juegos → Tablero |
| Datos de contacto | Correo y sitio web (el del `app-ads.txt`) |

### 14.5 Contenido de la aplicación

Política → **Contenido de la aplicación**. Rellena todas las secciones:

1. **Política de privacidad**: URL pública. Debe mencionar: cuenta (correo, nombre de usuario),
   partidas online, notificaciones (token del dispositivo), anuncios de AdMob (ID de publicidad,
   consentimiento), y cómo borrar la cuenta.
2. **Anuncios**: sí, contiene anuncios.
3. **Acceso a la aplicación**: algunas funciones requieren iniciar sesión → crea una cuenta de
   prueba con correo verificado y nombre de usuario, y escribe sus credenciales e instrucciones
   («Inicio → Jugar online con un amigo»).
4. **Clasificación de contenido**: cuestionario IARC (categoría juego de mesa; sin violencia; con
   interacción entre usuarios: los rivales ven el nombre de usuario).
5. **Público objetivo**: la política exige **14 años** para crear una cuenta (Ley 29733 de Perú;
   menores de 14 necesitan consentimiento de madre, padre o tutor). En Play Console elige los
   tramos **16-17** y **18 o más** para no entrar en los programas de familias; si eliges 13-15,
   Google aplicará requisitos adicionales a anuncios y datos. Es una decisión a confirmar con la
   asesoría legal.
6. **Seguridad de los datos**:

| Dato | Se recoge | Se comparte | Para qué | Opcional |
| --- | --- | --- | --- | --- |
| Correo electrónico | Sí | No | Gestión de la cuenta | Sí (solo online) |
| ID de usuario (uid, nombre de usuario) | Sí | No | Funcionalidad, gestión de la cuenta | Sí |
| Interacciones en la app (partidas online) | Sí | No | Funcionalidad | Sí |
| ID de dispositivo u otros (token FCM, ID de publicidad) | Sí | Sí (AdMob) | Publicidad, funcionalidad | No (publicidad), sí (avisos) |
| Interacciones en la app (estadísticas de uso) | Sí | No | Estadísticas | Sí (desactivadas hasta aceptar) |
| Diagnóstico (informes de errores, sin identificador de usuario) | Sí | No | Funcionalidad | Sí (se desactivan en Ajustes) |
| Información financiera: historial de compras («quitar anuncios») | Sí | No | Funcionalidad de la app | Sí (solo si se compra) |

   Cifrado en tránsito: sí. El usuario puede pedir el borrado: sí, con la URL del punto 7 de esta lista.

7. **Eliminación de cuenta**: URL de una página web donde se pueda pedir el borrado sin la app
   (formulario o correo), además de la opción dentro de la app (Ajustes → Cuenta → Eliminar cuenta).
8. **Gobierno, financieras, salud, noticias**: no aplica.

### 14.6 Prueba cerrada y producción

Las cuentas de desarrollador personales nuevas deben completar una **prueba cerrada** con un mínimo
de testers durante 14 días seguidos antes de pedir acceso a producción. Comprueba el requisito
vigente en Play Console → Panel. Después: Producción → crear versión → países → enviar a revisión.

### 14.7 Logros y clasificaciones (Google Play Games)

Opcional: sin estos IDs, la app oculta los botones de logros y no hace nada.

1. Play Console → **Crecer → Play Games Services → Configuración** → crea el proyecto de juegos
   y enlaza las credenciales de Android (paquete y SHA-1 de la clave de firma de Play; añade también
   la de subida para probar).
2. **Logros** → crea estos diez (nombre, descripción e icono propio):

| Clave en `config/prod.json` | Logro |
| --- | --- |
| `PG_ACH_FIRST_WIN_CHESS` / `_DRAUGHTS` / `_CHINESE` | Primera victoria en cada juego |
| `PG_ACH_BEAT_LEVEL5` | Ganar a la IA de nivel 5 |
| `PG_ACH_STREAK7` / `PG_ACH_STREAK30` | Racha de 7 y de 30 días de problemas |
| `PG_ACH_PUZZLES50` | 50 problemas resueltos |
| `PG_ACH_FIRST_ONLINE` | Primera partida online terminada |
| `PG_ACH_FIRST_REMATCH` | Primera revancha |
| `PG_ACH_ALL_LESSONS` | Todas las lecciones completadas |

3. **Clasificaciones** → tres, ordenadas de mayor a menor: problemas resueltos (`PG_LB_PUZZLES`),
   mejor racha (`PG_LB_STREAK`) y victorias contra el nivel 5 (`PG_LB_LEVEL5`).
4. Copia cada ID (`CgkI…`) en `config/prod.json` y el **ID de proyecto** (número) en el script de
   Android: `python3 tool/bootstrap_android.py … --play-games-project-id 1234567890`.
5. Publica los recursos (Play Games Services → Publicación) y añade testers en Play Games para
   probar antes de publicar.

### 14.8 Compra «quitar anuncios»

1. Play Console → **Monetizar → Productos → Productos de compra única** → crear con el ID
   **`remove_ads`** (no se puede cambiar), nombre, descripción y precio → **Activar**. Necesita un
   perfil de pagos configurado.
2. **Permisos de la cuenta del servidor.** Play Console → Usuarios y permisos → Invitar usuario →
   `tablero-api@escaque-prod.iam.gserviceaccount.com` → en la app Escaque: **Ver información
   financiera** y **Gestionar pedidos y suscripciones**. Además, en Configuración → Acceso a API,
   vincula el proyecto `escaque-prod` (paso de CI_CD.md, 5).
3. **Variable del servidor:** el despliegue (`deploy.yml`) pone `PLAY_PACKAGE` con la variable
   `ANDROID_PACKAGE` del entorno de GitHub, la misma de `assetlinks.json`. Sin despliegue por CI:
   `gcloud run services update tablero-api --region=$REGION --update-env-vars=PLAY_PACKAGE=$APP_ID_ANDROID`.
   Sin ella, la verificación responde `purchases_unavailable` y la app conserva la compra en el
   teléfono y reintenta más tarde.
4. **Reembolsos (notificaciones en tiempo real):**

```bash
gcloud pubsub topics create play-rtdn --project=$PROJECT_ID
gcloud pubsub topics add-iam-policy-binding play-rtdn --project=$PROJECT_ID \
  --member=serviceAccount:google-play-developer-notifications@system.gserviceaccount.com \
  --role=roles/pubsub.publisher
gcloud pubsub subscriptions create play-rtdn-push --project=$PROJECT_ID --topic=play-rtdn \
  --push-endpoint=$URL/v1/tasks/play-rtdn \
  --push-auth-service-account=$SCHED_SA --push-auth-token-audience=$URL
```

   Play Console → Monetizar → Configuración de monetización → **Notificaciones en tiempo real** →
   tema `projects/$PROJECT_ID/topics/play-rtdn` → «Enviar mensaje de prueba» (el servidor responde
   200 y no hace nada con él). La suscripción usa la misma cuenta que Scheduler, así que el servidor
   ya la acepta.
5. **Probar sin pagar:** Play Console → Configuración → **Pruebas de licencias** → añade tu cuenta de
   Google. Instala la app desde la prueba interna y compra: verás «Pedido de prueba».

✅ Tras comprar con cuenta: Ajustes muestra «Gracias por apoyar Escaque», el documento
`users/{uid}` tiene `adFree: true` y existe `purchases/{hash}`. Un reembolso desde Play Console
(Gestión de pedidos) lo retira en unos minutos.

### 14.9 Vincular AdMob

Cuando la app esté publicada: AdMob → tu app → **Configuración de la app** → vincular con Google Play.

---

## 15. App Check

### 15.1 Play Integrity

1. Play Console → Configuración → **Integridad de la aplicación** → API Play Integrity →
   **Vincular un proyecto de Cloud** → elige `$PROJECT_ID`.
2. Consola de Firebase → **App Check** → Apps → tu app Android → **Play Integrity** → pega la
   **SHA-256 de la clave de firma de Play** (paso 14.3) → Guardar.

### 15.2 Token de depuración (emuladores y compilaciones de desarrollo)

1. Ejecuta la app en modo debug y busca en los registros:

```bash
flutter logs | grep -i "debug secret"
```

   Aparece una línea como «Enter this debug secret into the allow list in the Firebase Console…».
2. Firebase → App Check → Apps → menú ⋮ de tu app → **Administrar tokens de depuración** → añade ese
   valor con un nombre («Pixel de Joao»).

✅ Firebase → App Check → **APIs** → Cloud Firestore: las peticiones aparecen como «verificadas».
En Cloud Run, los registros dejan de mostrar «Petición sin App Check válido».

---

## 16. Activar App Check en modo estricto

Cuando la versión con App Check lleve unos días en Play y las métricas muestren casi todas las
peticiones verificadas:

```bash
gcloud run services update tablero-api --region=$REGION --update-env-vars=APP_CHECK=enforce
```

Y en Firebase → App Check → APIs → **Cloud Firestore** → **Aplicar**.

Si se activa antes de tiempo, las versiones antiguas de la app o los dispositivos sin Google Play
dejan de funcionar online.

---

## 17. Mantenimiento

| Tarea | Cómo |
| --- | --- |
| Actualizar el servidor | Paso 9.5 y `gcloud run deploy tablero-api --image=…:latest --region=$REGION` (conserva variables y cuenta de servicio) |
| Volver a la versión anterior del servidor | Cloud Run → tablero-api → Revisiones → enviar el 100 % del tráfico a la anterior |
| Cambiar reglas o índices | Editar `firebase/` y `firebase deploy --only firestore:rules,firestore:indexes` |
| Nueva versión de la app | Subir `version` en `pubspec.yaml`, paso 12.3, subir a Play |
| Ver errores del servidor | `gcloud run services logs read tablero-api --region=$REGION` o Cloud Logging |
| Costes | Facturación → Informes; el presupuesto del paso 5.1 avisa |
| Copias de Firestore | `gcloud firestore export gs://UN_BUCKET/fecha` (programable con Scheduler) |
| Rotar la clave de subida | Play Console → Integridad de la aplicación → solicitar actualización de la clave de subida |
| Revisar dependencias | `dart pub outdated` / `flutter pub outdated` cada trimestre. Cada agosto Google Play sube el nivel de API obligatorio: actualiza Flutter antes |
| Errores de la app | Crashlytics (alertas por correo con errores nuevos o en aumento) |
| Errores del servidor | Cloud Error Reporting: agrupa los errores del registro estructurado; activa las notificaciones |
| Desactivar el online durante un incidente | Remote Config `online_enabled = false` |
| Alertas, copias, simulacro de restauración y pruebas de carga | [OPERACION.md](OPERACION.md) |
| Añadir problemas sin publicar versión | Generarlos y desplegar la landing: [OPERACION.md](OPERACION.md), 6 |
| Cambiar la ficha de Play | Editar `tablero_app/tool/store/listing.py` y ejecutarlo (comprueba los límites de caracteres) |
| Antes de subir cambios | `python3 tool/verify_repo.py` y `python3 tool/audit_wiring.py` (también en el CI) |

---

## 18. Problemas frecuentes

| Síntoma | Causa probable | Solución |
| --- | --- | --- |
| Acceso con Google: «no está bien configurado» o se cancela solo tras elegir la cuenta | Falta la SHA-1 de esa compilación, `google-services.json` antiguo o sin cliente web | Paso 5.4 (y 14.3 para instalaciones desde Play); descargar de nuevo el JSON |
| Play rechaza el AAB por el nivel de API | `targetSdk` menor que 36 | Flutter 3.47+ y `targetSdk = flutter.targetSdkVersion` |
| Servidor responde `rate_limited` (429) | Más de 60 peticiones seguidas de una cuenta | Normal ante bucles; si es legítimo, sube `RateLimiter(capacity)` |
| «El modo online no está configurado» | Falta `google-services.json` o compilaste sin `--dart-define-from-file` | Pasos 5.3 y 12 |
| Servidor responde `app_check` (401) | Token de App Check ausente o inválido con `APP_CHECK=enforce` | Paso 15; usar `monitor` mientras tanto |
| `account_required` o `email_not_verified` (403) | Sesión anónima de una versión vieja o correo sin verificar | Cerrar sesión y entrar con cuenta; verificar el correo |
| `username_required` (403) | La cuenta no tiene nombre de usuario | La app lo pide; si no, Ajustes → Cuenta |
| Firestore `PERMISSION_DENIED` en el lobby | Reglas sin publicar o cuenta no verificada | Paso 7.2; verificar el correo |
| Error del servidor con enlace a «create index» en los registros | Índices sin crear o aún compilándose | Paso 7.2 y esperar «Habilitado» |
| `gcloud builds submit` falla con permisos | Cuenta de Cloud Build sin roles | Paso 9.3 |
| Scheduler: 401 en los registros | `SCHEDULER_SA` o `SERVICE_URL` no coinciden con el trabajo | Paso 9.7 y revisar `--oidc-*` del paso 10 |
| No llegan notificaciones | Permiso denegado, sin token o ajustes de avisos desactivados | Ajustes de Android → Escaque → Notificaciones; Ajustes de la app → Partidas online; ver `users/{uid}/devices` en Firestore |
| Llegan notificaciones sin sonido | Canal creado antes con importancia baja | Desinstalar y reinstalar, o subir la importancia del canal «Turnos» en Android |
| No se ven anuncios | Mensaje de consentimiento sin publicar, sin consentimiento o cuenta nueva sin inventario | Paso 11.3; con IDs de prueba siempre debe salir un anuncio |
| `flutter build` falla por desugaring | Falta el paso 3.3 | Añadir `coreLibraryDesugaring` |
| La IA tarda en gama baja | Nivel 5 con 3 s de límite | Normal; los niveles 1–3 responden antes |
