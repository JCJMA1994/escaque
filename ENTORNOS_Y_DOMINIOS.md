# Escaque — entornos (dev, qa, prod) y subdominios

Tres entornos completamente separados, cada uno con su proyecto de Firebase, su servidor, su app
instalable en paralelo y sus subdominios en `system-failed-tech.com`.

Requisito previo: haber seguido [GUIA_CONFIGURACION.md](GUIA_CONFIGURACION.md) al menos una vez.
Aquí se indica qué repetir por entorno y qué cambia.

---

## 1. Lo que comprobé del dominio

| Comprobación | Resultado |
| --- | --- |
| `https://system-failed-tech.com` | Responde y sirve **LaunchPulse** (tu plataforma de landings), con `/admin`, `/status` y panel de clientes |
| Consecuencia | La raíz del dominio **no se toca**. Escaque va solo en subdominios |
| DNS y subdominios existentes | No puedo consultarlos desde aquí: revísalos en tu proveedor DNS antes de crear registros (paso 6) |

La única excepción es `app-ads.txt` en la raíz (paso 8), que LaunchPulse tiene que servir como archivo
estático.

---

## 2. Mapa de entornos

| | dev | qa | prod |
| --- | --- | --- | --- |
| Para qué | Desarrollo diario, datos de prueba | Pruebas de testers antes de publicar | Usuarios reales |
| Proyecto de Firebase | `escaque-dev` | `escaque-qa` | `escaque-prod` |
| `applicationId` | `com.tuempresa.escaque.dev` | `com.tuempresa.escaque.qa` | `com.tuempresa.escaque` |
| Nombre en el teléfono | Escaque DEV | Escaque QA | Escaque |
| Landing | — (local: `npm run dev`) | `escaque-qa.system-failed-tech.com` (no indexable) | `escaque.system-failed-tech.com` |
| API | `api-escaque-dev.system-failed-tech.com` | `api-escaque-qa.system-failed-tech.com` | `api-escaque.system-failed-tech.com` |
| AdMob | IDs de prueba | IDs de prueba | IDs reales |
| App Check | `monitor` + tokens de depuración | `monitor` | `monitor` → `enforce` |
| Distribución | Firebase App Distribution | Firebase App Distribution | Google Play |
| Despliegue (CI) | Manual | Cada push a `main` | Etiqueta `vX.Y.Z` con aprobación |
| `config/` de la app | `dev.json` | `qa.json` | `prod.json` |
| Crashlytics | Desactivado en depuración; activo en las APK de testers | Activo | Activo, con símbolos subidos por el CI |
| Remote Config | Mismos parámetros que prod (paso 8.2 de la guía), para probar cambios antes | Igual | Valores reales |

Los IDs de proyecto de Firebase son únicos en todo el mundo: si `escaque-prod` está ocupado, usa
otro (por ejemplo `escaque-prod-sft`) y ajusta `.firebaserc`.

### Por qué proyectos separados

Es la recomendación de Firebase: cada entorno tiene sus propios usuarios, datos, reglas, cuotas y
permisos. Un error en qa no puede borrar ni leer datos de producción, y las cuentas de prueba no se
mezclan con las reales.

### Por qué subdominios de un solo nivel

`api-escaque-qa.system-failed-tech.com` en vez de `api.qa.escaque.system-failed-tech.com`. Si tu DNS
está en Cloudflare (u otro proxy con certificado comodín), el certificado universal solo cubre un
nivel (`*.system-failed-tech.com`). Con nombres planos, cualquier subdominio sigue cubierto aunque un
día actives el proxy.

---

## 3. Crear los tres proyectos

Repite para `dev`, `qa` y `prod` los pasos de la guía principal, con estas diferencias:

| Paso de la guía | dev | qa | prod |
| --- | --- | --- | --- |
| 5.1 Proyecto, Blaze, presupuesto | Presupuesto bajo (p. ej. 5 USD) | Igual | El real |
| 5.3 FlutterFire | Package `…escaque.dev` | Package `…escaque.qa` | Package `…escaque` |
| 6 Authentication | Igual | Igual | Igual + dominio propio de correo (paso 7) |
| 7 Firestore (misma región) | Sí | Sí | Sí |
| 9 Cloud Run (`APP_CHECK`) | `monitor` | `monitor` | `monitor` y luego `enforce` |
| 10 Cloud Scheduler | Opcional | Sí | Sí |
| 11 AdMob | No (IDs de prueba) | No (IDs de prueba) | Sí |
| 14 Play Console | No | No | Sí |
| 15 App Check | Token de depuración | Play Integrity no aplica fuera de Play: usa token de depuración por tester | Play Integrity |

Variables por entorno, en archivos separados (`variables.dev.sh`, `variables.qa.sh`,
`variables.prod.sh`) para no mezclarlos:

```bash
# variables.qa.sh
export ENV_NAME="qa"
export PROJECT_ID="escaque-qa"
export PROJECT_NUMBER="..."
export REGION="southamerica-east1"
export APP_ID_ANDROID="com.tuempresa.escaque.qa"
export API_DOMAIN="api-escaque-qa.system-failed-tech.com"
export LANDING_DOMAIN="escaque-qa.system-failed-tech.com"
```

---

## 4. App: un *flavor* por entorno

Las tres apps conviven en el mismo teléfono (identificadores distintos) y cada una apunta a su
proyecto de Firebase y su servidor.

### 4.1 Gradle

`tablero_app/tool/bootstrap_android.py` aplica este paso (y el host de invitaciones de cada
flavor). A mano, en Kotlin (`android/app/build.gradle.kts`), dentro de `android { }`:

```kotlin
flavorDimensions += "env"
productFlavors {
    create("dev") {
        dimension = "env"
        applicationIdSuffix = ".dev"
        resValue("string", "app_name", "Escaque DEV")
    }
    create("qa") {
        dimension = "env"
        applicationIdSuffix = ".qa"
        resValue("string", "app_name", "Escaque QA")
    }
    create("prod") {
        dimension = "env"
        resValue("string", "app_name", "Escaque")
    }
}
```

Groovy (`android/app/build.gradle`):

```groovy
flavorDimensions "env"
productFlavors {
    dev  { dimension "env"; applicationIdSuffix ".dev"; resValue "string", "app_name", "Escaque DEV" }
    qa   { dimension "env"; applicationIdSuffix ".qa";  resValue "string", "app_name", "Escaque QA" }
    prod { dimension "env"; resValue "string", "app_name", "Escaque" }
}
```

En `AndroidManifest.xml`, la etiqueta pasa a ser el recurso: `android:label="@string/app_name"`.

### 4.2 `google-services.json` por entorno

Cada proyecto de Firebase tiene su archivo. Colócalos así (y borra el de `android/app/`):

```
android/app/src/dev/google-services.json    ← de escaque-dev
android/app/src/qa/google-services.json     ← de escaque-qa
android/app/src/prod/google-services.json   ← de escaque-prod
```

Con FlutterFire, una vez por entorno:

```bash
flutterfire configure --project=escaque-qa --platforms=android \
  --android-package-name=com.tuempresa.escaque.qa \
  --android-out=android/app/src/qa/google-services.json
```

Estos archivos no son secretos (las claves de API de Firebase identifican el proyecto, no dan
acceso): súbelos al repositorio para que el CI pueda compilar.

### 4.3 Configuración Dart

```bash
cp config/dev.json.example config/dev.json
cp config/qa.json.example  config/qa.json
cp config/prod.json.example config/prod.json   # con los IDs reales de AdMob
```

Cada archivo fija `ENV` (la app muestra una franja «DEV» o «QA» fuera de producción) y `TABLERO_API`
(el subdominio de la API de ese entorno).

### 4.4 Ejecutar y compilar

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.json
flutter build apk --release --flavor qa --dart-define-from-file=config/qa.json
flutter build appbundle --release --flavor prod --dart-define-from-file=config/prod.json \
  --obfuscate --split-debug-info=build/symbols
```

### 4.5 Huellas SHA por entorno

Añade la SHA-1 y SHA-256 en la app de **cada** proyecto (guía, paso 5.4): la de debug en dev, la de
subida en qa y prod, y la de la clave de firma de Play solo en prod.

---

## 5. Hosting: sitios por entorno

Cada proyecto sirve dos sitios de Firebase Hosting: la **landing** (el sitio por defecto, con el
mismo nombre que el proyecto) y la **API** (un sitio extra que reenvía todo a Cloud Run). Firebase
Hosting admite reenviar a Cloud Run en `southamerica-east1`, así que no hace falta balanceador de
carga.

### 5.1 Crear el sitio de la API

```bash
firebase hosting:sites:create escaque-dev-api  --project escaque-dev
firebase hosting:sites:create escaque-qa-api   --project escaque-qa
firebase hosting:sites:create escaque-prod-api --project escaque-prod
```

### 5.2 `.firebaserc`

```bash
cp .firebaserc.example .firebaserc
```

Ajusta IDs de proyecto y de sitio si cambiaste alguno, y súbelo al repositorio. Relaciona cada alias
(`dev`, `qa`, `prod`) con su proyecto y cada destino (`landing`, `api`) con su sitio.

### 5.3 Desplegar

```bash
# Landing (qa y prod)
cd landing && npm ci && npm run build:qa && cd ..
firebase deploy --project qa --only hosting

# API y reglas
firebase deploy --project qa --only firestore:rules,firestore:indexes,hosting:api
```

✅ Firebase muestra las URL por defecto (`https://escaque-qa.web.app` y
`https://escaque-qa-api.web.app`). Comprueba `https://escaque-qa-api.web.app/healthz` → `ok`.

---

## 6. Subdominios y DNS

### 6.1 Registros a crear

En la consola de Firebase → Hosting → elige el sitio → **Agregar dominio personalizado** → escribe el
subdominio → «Continuar». Firebase muestra los registros exactos para ese dominio. Normalmente son:

- un registro **TXT** de verificación de propiedad, y
- uno o varios registros **A** que apuntan a los servidores de Firebase Hosting.

Usa siempre los valores que muestre la consola: pueden cambiar.

| Subdominio | Sitio de Hosting | Proyecto |
| --- | --- | --- |
| `escaque.system-failed-tech.com` | `escaque-prod` | escaque-prod |
| `api-escaque.system-failed-tech.com` | `escaque-prod-api` | escaque-prod |
| `escaque-qa.system-failed-tech.com` | `escaque-qa` | escaque-qa |
| `api-escaque-qa.system-failed-tech.com` | `escaque-qa-api` | escaque-qa |
| `api-escaque-dev.system-failed-tech.com` | `escaque-dev-api` | escaque-dev |

### 6.2 En tu proveedor DNS

1. Crea los registros con el **nombre del subdominio** (por ejemplo `api-escaque-qa`) y los valores
   de la consola.
2. **Si usas Cloudflare: estado del proxy «Solo DNS» (nube gris).** Con el proxy activo, Firebase no
   puede emitir el certificado.
3. Comprueba que no exista ya un registro con ese nombre ni un comodín `*` que lo tape (LaunchPulse
   podría usar comodines para los subdominios de clientes).
4. TTL automático o 300 s mientras configuras.

### 6.3 Verificar

```bash
dig +short escaque.system-failed-tech.com A
dig +short escaque.system-failed-tech.com TXT
curl -sI https://escaque.system-failed-tech.com | head -1
curl -s https://api-escaque-qa.system-failed-tech.com/healthz
```

✅ La consola de Firebase pasa el dominio a «Conectado». El certificado HTTPS puede tardar hasta
24 horas tras verificar.

### 6.4 La app usa el subdominio

`config/<entorno>.json` ya apunta a `https://api-escaque[-entorno].system-failed-tech.com`. Ventaja:
si un día mueves el servidor (otra región, otro proyecto), cambias el destino en Hosting y las apps
ya instaladas siguen funcionando.

Cloud Scheduler sigue llamando a la URL `run.app` (paso 10 de la guía): el token OIDC lleva esa URL
como audiencia (`SERVICE_URL`).

---

## 7. Correo y enlaces de Authentication con tu dominio (prod)

### 7.1 Remitente propio

Firebase → Authentication → **Plantillas** → editar cualquier plantilla → **Personalizar dominio** →
`escaque.system-failed-tech.com`. Firebase muestra registros DNS (verificación y firma de correo):
créalos igual que en el paso 6 y espera la verificación. Los correos llegan desde
`noreply@escaque.system-failed-tech.com` y caen menos en spam.

### 7.2 Enlaces de acción en tu dominio

En la misma pantalla de plantillas → **Personalizar la URL de acción** →
`https://escaque.system-failed-tech.com/__/auth/action` (en qa,
`https://escaque-qa.system-failed-tech.com/__/auth/action`). Funciona porque el Hosting del mismo
proyecto sirve esa ruta reservada.

### 7.3 Dominios autorizados

Authentication → Configuración → **Dominios autorizados** → añade el subdominio de la landing de ese
entorno.

---

## 8. `app-ads.txt`

1. Copia la línea que te da AdMob en `landing/public/app-ads.txt` (la plantilla ya existe) y despliega
   la landing de prod: queda en `https://escaque.system-failed-tech.com/app-ads.txt`.
2. Publica **el mismo archivo en la raíz**, `https://system-failed-tech.com/app-ads.txt`, como
   archivo estático de LaunchPulse. El rastreador de AdMob puede buscarlo en el dominio raíz del sitio
   web del desarrollador; con los dos no hay duda.
3. En Play Console, el **sitio web del desarrollador** es `https://escaque.system-failed-tech.com`.

---

## 9. Enlaces de invitación

Al crear una partida online, «Copiar» pega un enlace `https://<landing>/j/CÓDIGO`. Si la app está
instalada, Android la abre directamente (App Links) y entra en la partida; si no, la web muestra el
código y el botón de Play.

| Pieza | Dónde |
| --- | --- |
| Página `/j/CÓDIGO` | `landing/src/pages/j.astro` (Hosting reescribe `/j/**`) |
| Verificación del dominio | `https://<landing>/.well-known/assetlinks.json`, generado en la compilación con `ANDROID_PACKAGE` y `ANDROID_SHA256` (variables del entorno en GitHub) |
| App | `intent-filter` con `autoVerify` y el host de la landing del entorno (guía, paso 3.4); ruta `/j/:code` |
| Base del enlace | `INVITE_BASE_URL` en `config/<entorno>.json` |

dev no tiene landing: sus invitaciones usan la de qa (y abren la app QA). Para probar los enlaces,
usa qa.

En `assetlinks.json` de prod pon **dos** huellas: la de la clave de firma de Play (instalaciones
desde la tienda) y la de subida (pruebas locales).

## 10. Comprobación final por entorno

| Comprobación | dev | qa | prod |
| --- | --- | --- | --- |
| `https://<api>/healthz` → `ok` | ☐ | ☐ | ☐ |
| Landing abre con HTTPS y certificado válido | — | ☐ | ☐ |
| Landing de qa muestra la franja «Entorno: QA» y `robots.txt` con `Disallow: /` | — | ☐ | — |
| `https://escaque.system-failed-tech.com/robots.txt` permite indexar y enlaza el sitemap | — | — | ☐ |
| App del entorno crea cuenta, elige nombre de usuario y juega online | ☐ | ☐ | ☐ |
| Notificación de turno con la app cerrada | ☐ | ☐ | ☐ |
| Correo de verificación con remitente propio | — | — | ☐ |
| `app-ads.txt` en el subdominio y en la raíz | — | — | ☐ |
| Scheduler ejecuta `/v1/tasks/deadlines` con 200 | — | ☐ | ☐ |
| `/.well-known/assetlinks.json` con el paquete y las huellas correctas | — | ☐ | ☐ |
| Un enlace `/j/CÓDIGO` abre la app y entra en la partida | — | ☐ | ☐ |
