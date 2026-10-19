# Escaque — CI/CD con GitHub Actions

Cinco workflows en `.github/workflows/`:

| Workflow | Cuándo | Qué hace |
| --- | --- | --- |
| `ci.yml` | Cada push y cada pull request | Analiza y prueba motor, servidor y app; prueba las reglas de Firestore en el emulador; compila la landing (con el catálogo de problemas); valida los JSON de Firebase; ejecuta `verify_repo.py` (sintaxis de Dart, imports, traducciones) y `audit_wiring.py` (conexiones y documentos). No despliega nada |
| `integration.yml` | Manual y cada noche | Test de integración de la app en un emulador Android (flujo offline completo) |
| `load.yml` | Manual | Prueba de carga con k6 contra qa (OPERACION.md, 4) |
| `screenshots.yml` | Manual | Capturas de Play Store en teléfono y tablet, en español e inglés (8 pantallas cada una), como artefactos |
| `deploy.yml` | Push a `main` → **qa** · etiqueta `vX.Y.Z` → **prod** · manual → dev, qa o prod | Ejecuta el CI; compila y despliega el servidor en Cloud Run y comprueba `/healthz`; despliega reglas, índices, landing y API en Firebase; compila la app y la entrega a testers (dev/qa, App Distribution) o a la prueba interna de Google Play (prod), subiendo los símbolos de Dart a Crashlytics |

Autenticación con Google Cloud por **Workload Identity Federation**: GitHub demuestra su identidad con
un token OIDC de corta duración y no hay claves JSON de Google Cloud guardadas en GitHub. La única
clave que queda es la de la API de Google Play (paso 5), que no admite este método en la acción usada.

Requisito previo: los tres entornos creados según [ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md) y
la carpeta `tablero_app/android/` generada y configurada con `tablero_app/tool/bootstrap_android.py`
(guía, paso 3; incluye los flavors del paso 4 de entornos).

---

## 1. Repositorio

```bash
cd escaque
git init -b main
git add .
git commit -m "Escaque: motor, servidor, app, landing, Firebase y CI/CD"
git remote add origin git@github.com:TU_USUARIO/escaque.git
git push -u origin main
```

Comprueba antes de subir que no van secretos: `git status` no debe listar `key.properties`, `*.jks`,
`config/*.json` (solo los `.example`) ni `variables*.sh`. El `.gitignore` de la raíz los excluye.

Sí deben subirse: `tablero_app/android/` (con los tres `google-services.json` por flavor),
`.firebaserc` y `landing/package-lock.json`.

Para generar `android/` sin editar Gradle a mano:

```bash
cd tablero_app
flutter create --platforms=android --org com.tuempresa --project-name tablero_app .
python3 tool/bootstrap_android.py --package com.tuempresa.escaque --admob-app-id ca-app-pub-XXXX~YYYY
```

### Comprobaciones sin compilar

- `tool/verify_repo.py`: sintaxis de todo el Dart (tree-sitter), imports, traducciones, versiones,
  problemas y otras reglas del proyecto.
- `tool/audit_wiring.py`: que todo esté conectado. Cada llamada de la app tiene ruta en el
  servidor con los campos que exige, cada ruta tiene quien la llame, cada navegación tiene pantalla,
  no hay símbolos ni métodos públicos sin usar, cada colección de Firestore tiene regla, cada campo
  que la app lee lo escribe el servidor, la landing no tiene enlaces rotos y los workflows no citan
  archivos inexistentes. También revisa los documentos (archivos, enlaces, rutas y variables que
  citan; códigos de error y eventos documentados), las traducciones sin uso y que cada ajuste y
  cada campo de partida se guarde y se lea completo.

### Primera ejecución

1. Sube el repositorio y abre la pestaña Actions: corre `CI` sin necesitar `android/` ni secretos.
2. Si `flutter analyze` falla, el error suele estar en una API de un plugin (las versiones se
   comprobaron en sus repositorios, pero nada se había compilado). Corrígelo antes de configurar
   los despliegues.
3. Con `android/` subido y los entornos configurados: `Deploy` manual en `dev`.

---

## 2. Entornos de GitHub

Repositorio → Settings → **Environments** → crea `dev`, `qa` y `prod`.

En `prod`:

- **Required reviewers**: tú (y quien apruebe publicaciones).
- **Deployment branches and tags**: solo etiquetas `v*.*.*`.

En Settings → Branches → regla para `main`: exigir pull request y que pasen los checks de `CI`.

---

## 3. Workload Identity Federation (una vez por proyecto)

Ejecuta este bloque **tres veces**, con las variables de `dev`, `qa` y `prod`:

```bash
source variables.qa.sh                     # PROJECT_ID, PROJECT_NUMBER…
export GH_REPO="TU_USUARIO/escaque"

# Pool y proveedor de identidades de GitHub (solo tu repositorio puede usarlos)
gcloud iam workload-identity-pools create github \
  --project=$PROJECT_ID --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc github \
  --project=$PROJECT_ID --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='${GH_REPO}'"

# Cuenta de servicio que usa el CI para desplegar
gcloud iam service-accounts create github-deploy --project=$PROJECT_ID --display-name="GitHub deploy"
export DEPLOY_SA="github-deploy@${PROJECT_ID}.iam.gserviceaccount.com"

for ROLE in \
  roles/run.admin \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/storage.admin \
  roles/serviceusage.serviceUsageConsumer \
  roles/viewer \
  roles/firebasehosting.admin \
  roles/firebaserules.admin \
  roles/datastore.indexAdmin \
  roles/firebaseappdistro.admin \
  roles/firebasecrashlytics.admin
do
  gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$DEPLOY_SA" --role=$ROLE
done

# Desplegar Cloud Run «como» la cuenta del servidor
gcloud iam service-accounts add-iam-policy-binding "tablero-api@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project=$PROJECT_ID --member="serviceAccount:$DEPLOY_SA" --role=roles/iam.serviceAccountUser

# Permitir que el repositorio use la cuenta de despliegue
gcloud iam service-accounts add-iam-policy-binding $DEPLOY_SA --project=$PROJECT_ID \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${GH_REPO}"

# Valor para la variable GCP_WIF_PROVIDER
echo "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github/providers/github"
```

`roles/viewer` permite que `gcloud builds submit` muestre el registro del build en el CI.

---

## 4. Variables y secretos por entorno

GitHub → Settings → Environments → (dev / qa / prod) → **Environment variables** y
**Environment secrets**.

### Variables

| Variable | dev | qa | prod |
| --- | --- | --- | --- |
| `GCP_PROJECT_ID` | `escaque-dev` | `escaque-qa` | `escaque-prod` |
| `GCP_WIF_PROVIDER` | Salida del paso 3 | Igual | Igual |
| `GCP_DEPLOY_SA` | `github-deploy@escaque-dev.iam.gserviceaccount.com` | `…@escaque-qa…` | `…@escaque-prod…` |
| `SITE_URL` | — | `https://escaque-qa.system-failed-tech.com` | `https://escaque.system-failed-tech.com` |
| `FIREBASE_ANDROID_APP_ID` | App ID de la app `.dev` (Firebase → Configuración → tu app, «ID de la app» `1:…:android:…`) | De la app `.qa` | De la app de prod (para los símbolos de Crashlytics) |
| `ANDROID_PACKAGE` | — (sin compras en dev) | `com.tuempresa.escaque.qa` | `com.tuempresa.escaque` |
| `ANDROID_SHA256` | — | SHA-256 de la clave de subida | SHA-256 de la **clave de firma de Play** (y la de subida, separadas por comas) |
| `PLAY_RELEASE_STATUS` | — | — | `draft` mientras la app no esté publicada; luego `completed` |

`ANDROID_PACKAGE` se usa dos veces: en `assetlinks.json` (App Links) y como `PLAY_PACKAGE` del
servidor para verificar las compras (`deploy.yml`).

### Secretos

| Secreto | Contenido | Entornos |
| --- | --- | --- |
| `APP_CONFIG_JSON` | El contenido completo de `config/<entorno>.json` | Los tres |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 escaque-upload.jks` (en macOS: `base64 -i escaque-upload.jks`) | Los tres |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del almacén | Los tres |
| `ANDROID_KEY_ALIAS` | `upload` | Los tres |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave | Los tres |
| `PLAY_SERVICE_ACCOUNT_JSON` | Clave JSON de la cuenta del paso 5 | Solo prod |
| `LOAD_TEST_SECRET` | El secreto de las pruebas de carga (OPERACION.md, 4) | Solo qa |

Variable adicional en qa: `API_URL` = `https://api-escaque-qa.system-failed-tech.com` (para `load.yml`).
El despliegue fija `ENVIRONMENT` (dev, qa o prod) en Cloud Run en cada ejecución.

Puedes usar la misma clave de subida para los tres flavors, o una distinta para dev/qa.

---

## 5. Google Play (solo prod)

1. Play Console → Configuración → **Acceso a API** → vincula el proyecto `escaque-prod`.
2. Crea una cuenta de servicio en ese proyecto (`play-publisher`) y genera una clave JSON:

```bash
gcloud iam service-accounts create play-publisher --project=escaque-prod
gcloud iam service-accounts keys create play-publisher.json \
  --iam-account=play-publisher@escaque-prod.iam.gserviceaccount.com
```

3. Play Console → **Usuarios y permisos** → invita el correo de esa cuenta con permiso para
   **publicar versiones en canales de prueba** de la app Escaque.
4. Pega el contenido de `play-publisher.json` en el secreto `PLAY_SERVICE_ACCOUNT_JSON` y **borra el
   archivo** de tu ordenador.
5. **La primera versión se sube a mano** (guía, paso 14.2): la API de Play no puede crear la primera
   versión de una app.

---

## 6. Firebase App Distribution (dev y qa)

1. Firebase (escaque-dev y escaque-qa) → **App Distribution** → Comenzar.
2. Pestaña Testers y grupos → crea el grupo con alias **`testers`** y añade los correos.
3. Los testers reciben un correo para instalar «Escaque QA» o «Escaque DEV».

---

## 7. Uso diario

| Quiero… | Hago… |
| --- | --- |
| Probar un cambio | Rama + pull request: corre el CI |
| Subir a qa | Merge a `main`: se despliegan servidor, Firebase, landing de qa y la app QA a testers |
| Desplegar en dev | Actions → Deploy → Run workflow → `dev` |
| Publicar en producción | Sube `version` en `tablero_app/pubspec.yaml`, merge a `main` y `git tag v1.2.0 && git push origin v1.2.0`; aprueba el despliegue en el entorno `prod`; la app queda en la prueba interna de Play y la promocionas desde Play Console |
| Volver atrás el servidor | Cloud Run → `tablero-api` → Revisiones → 100 % del tráfico a la anterior (cada imagen lleva el commit como etiqueta) |
| Volver atrás la landing | Firebase → Hosting → historial de versiones → Revertir |

El número de compilación de Android es `1000 + número de ejecución del workflow`: siempre crece, que
es lo que exige Play. La versión visible (`1.2.0`) sale de `pubspec.yaml`.

Los símbolos de depuración de cada versión de prod se guardan como artefacto del workflow durante
un año (para leer errores de la app ofuscada).

---

## 8. Versiones fijadas

| Herramienta | Versión | Por qué |
| --- | --- | --- |
| Flutter | 3.47.7 | Apunta a Android 16 (API 36), obligatorio en Play desde el 31/08/2026; motor y servidor usan su Dart |
| Node | 22 | Landing y herramientas de Firebase |
| firebase-tools | 15.32.1 | Despliegues, emulador, App Distribution y símbolos |
| Java | 17 (Android) y 21 (emulador de Firestore) | Requisitos de cada herramienta |

Para actualizar Flutter, cambia `FLUTTER_VERSION` en los tres workflows a la vez.

## 9. Si algo falla

| Error | Causa | Solución |
| --- | --- | --- |
| `Permission 'iam.serviceAccounts.getAccessToken' denied` | Falta el enlace `workloadIdentityUser` o el repositorio no coincide con `attribute-condition` | Paso 3, revisar `GH_REPO` |
| `gcloud builds submit`: no puede mostrar el registro | Falta `roles/viewer` | Paso 3 |
| `PERMISSION_DENIED` al desplegar Cloud Run | Falta `iam.serviceAccountUser` sobre `tablero-api` | Paso 3 |
| Firebase deploy: `Falta .firebaserc` | No se subió el archivo | `cp .firebaserc.example .firebaserc`, editar y subir |
| Firebase deploy: sitio `api` no encontrado | No se creó el sitio o el destino | Entornos, paso 5 |
| Play: `Package not found` | Primera versión no subida a mano o la cuenta sin permisos en la app | Paso 5 |
| Play: `Only releases with status draft may be created on draft app` | La app aún no está publicada | `PLAY_RELEASE_STATUS=draft` |
| Build Android: falta `google-services.json` | No está en `android/app/src/<flavor>/` | Entornos, paso 4.2 |
