# Escaque — operación (fase A)

Cómo activar y usar lo que implementa la fase A de [PLAN.md](PLAN.md): alertas, copias de
Firestore, revocación de tokens, pruebas de carga y estadísticas de uso. Requiere los entornos de
[ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md).

---

## 1. Alertas (O1)

Las políticas están en `infra/monitoring/policy-*.yaml` y se aplican por entorno:

```bash
infra/monitoring/apply.sh qa   escaque-qa   api-escaque-qa.system-failed-tech.com tu@correo.com
infra/monitoring/apply.sh prod escaque-prod api-escaque.system-failed-tech.com    tu@correo.com
```

El script crea el canal de correo, la comprobación de disponibilidad de `/healthz` (cada minuto, desde
varias regiones) y cuatro alertas. Se puede ejecutar otra vez: sustituye las políticas del mismo
nombre.

| Alerta | Se dispara si |
| --- | --- |
| `/healthz` no responde | Falla durante 2 minutos |
| Errores 5xx > 2 % | Durante 5 minutos |
| Latencia p95 > 1,5 s | Durante 10 minutos |
| Fallo del trabajo de plazos | Cloud Scheduler registra un error (como mucho un aviso por hora) |

Usa comandos `gcloud alpha` y `beta` de Monitoring: si `gcloud` pide instalar esos componentes,
acepta (`gcloud components install alpha beta`).

Además, en las consolas:

1. **Error Reporting** (Google Cloud) → Configurar notificaciones → tu canal de correo.
2. **Crashlytics** (Firebase) → Alertas → nuevos problemas, regresiones y aumento de fallos.
3. **App de Google Cloud** en el móvil, para recibir las alertas críticas como notificación.

✅ Prueba en qa: `gcloud run services update tablero-api --region=southamerica-east1 --project=escaque-qa
--update-env-vars=PROJECT_ID=roto` hace fallar el servidor; la alerta llega en menos de 5 minutos.
Vuelve a poner el valor correcto.

---

## 2. Copias de Firestore (O2)

```bash
infra/backups/setup.sh prod escaque-prod   # diaria, 14 días + recuperación a un minuto (7 días)
infra/backups/setup.sh qa   escaque-qa     # semanal, 4 semanas
```

Necesitas el rol `roles/datastore.owner` (o propietario del proyecto).

### Simulacro trimestral

```bash
infra/backups/restore-drill.sh escaque-prod southamerica-east1
```

Restaura la última copia en una base **nueva** (`restore-AAAAMMDD`), nunca sobre la de producción.
Comprueba en la consola que tiene documentos en `games` y `users`, anota el tiempo y bórrala con el
comando que muestra el script. Objetivo: menos de 30 minutos.

### Si hay que recuperar datos de verdad

- **Un error de los últimos 7 días** (borrado masivo, despliegue defectuoso): recuperación a un
  minuto concreto en una base nueva; después se copian los documentos afectados.
- **Algo más antiguo**: la copia diaria más cercana, igual que el simulacro.

En ambos casos se restaura en una base nueva y se migran datos: nunca se sobrescribe `(default)` sin
haber comprobado antes la copia.

---

## 3. Revocación de tokens (O3)

Qué hace el servidor:

| Operación | Comprobación |
| --- | --- |
| Todas | Firma, caducidad, tipo de cuenta, App Check |
| Cambiar nombre de usuario | Además: el token no está revocado (cierre de sesión en todos los dispositivos, cambio de contraseña o cuenta desactivada) |
| Borrar la cuenta | Además: inicio de sesión de hace menos de 5 minutos. La app pide confirmar la identidad y reintenta sola |

Lo consulta en Identity Toolkit, con caché de 5 minutos por cuenta. Permiso necesario, en cada
proyecto:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:tablero-api@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role=roles/firebaseauth.viewer
```

Códigos nuevos: `token_revoked` (la app cierra la sesión), `recent_login_required` (la app
reautentica) y `auth_unavailable` (no se pudo comprobar: se rechaza la operación, no se arriesga).

Para cerrar la sesión de una cuenta en todos sus dispositivos (por ejemplo, si avisan de un robo):
Firebase → Authentication → la cuenta → menú ⋮ → **Desactivar cuenta**. Las operaciones sensibles
se rechazan como mucho 5 minutos después; las demás, cuando caduque su token (1 hora).

---

## 4. Pruebas de carga (O4)

### Preparar qa (una vez)

```bash
export PROJECT_ID=escaque-qa
SECRET=$(openssl rand -hex 24)
printf '%s' "$SECRET" | gcloud secrets create load-test-secret --data-file=- --project=$PROJECT_ID
gcloud secrets add-iam-policy-binding load-test-secret --project=$PROJECT_ID \
  --member="serviceAccount:tablero-api@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor
gcloud run services update tablero-api --project=$PROJECT_ID --region=southamerica-east1 \
  --update-secrets=LOAD_TEST_SECRET=load-test-secret:latest
echo "$SECRET"   # cópialo al secreto LOAD_TEST_SECRET del entorno qa en GitHub
```

En GitHub, entorno `qa`: secreto `LOAD_TEST_SECRET` y variable `API_URL`
(`https://api-escaque-qa.system-failed-tech.com`).

**Nunca en prod:** el servidor se niega a arrancar si tiene `LOAD_TEST_SECRET` y `ENVIRONMENT=prod`
(o sin `ENVIRONMENT`). El despliegue fija `ENVIRONMENT` en cada entorno.

### Ejecutar

GitHub → Actions → **Carga (qa)** → Run workflow (200 partidas, 2 s entre jugadas por defecto).
O en local, con [k6](https://k6.io):

```bash
cd tool/load
k6 run -e BASE_URL=https://api-escaque-qa.system-failed-tech.com -e LOAD_TEST_SECRET=... \
  -e GAMES=50 -e THINK=2 partidas.js
```

Cada usuario virtual crea dos cuentas de prueba (`load_…`), juega una partida completa de 80 medias
jugadas legales, abandona y borra las cuentas.

### Objetivos

| Métrica (k6) | Objetivo |
| --- | --- |
| `http_req_duration{endpoint:move}` p95 | < 800 ms |
| `http_req_failed` | < 1 % |
| `jugadas_perdidas` | 0 |
| `checks` | > 99 % |

Si falla un umbral, k6 termina con error y el resumen queda como artefacto (`carga-N`). Anota
también, de la consola de Firestore, las lecturas y escrituras de la prueba: es el coste por
partida.

---

## 5. Estadísticas de uso (punto 0)

### Activar

1. Firebase → **Analytics** → activar en cada proyecto (si no se activó al crearlo).
2. Analytics → Configuración del administrador → Conservación de datos: **2 meses**.
3. Desactiva «Señales de Google» y la compartición de datos con Google (no se usan para anuncios).

### Cómo funciona en la app

- **Desactivado hasta que la persona acepta, en todos los países.** La Ley 29733 de Perú y su
  Reglamento (DS 016-2024-JUS, vigente desde el 30/03/2025) exigen consentimiento previo y expreso,
  como el RGPD.
- La app lo pregunta una vez, con una tarjeta en Inicio («¿Nos ayudas a mejorar Escaque?»), y se
  cambia en Ajustes → Privacidad → «Estadísticas de uso».
- Crashlytics no recibe el uid: los informes de errores son datos técnicos sin identificar a nadie.
- Modo de consentimiento: solo almacenamiento de analítica; los permisos de publicidad de Analytics
  se deniegan siempre.
- En depuración no se envía nada.

Para que nada salga antes de esa decisión, añade al `<application>` del `AndroidManifest.xml`:

```xml
<meta-data android:name="firebase_analytics_collection_enabled" android:value="false"/>
<meta-data android:name="google_analytics_default_allow_analytics_storage" android:value="false"/>
<meta-data android:name="google_analytics_default_allow_ad_storage" android:value="false"/>
<meta-data android:name="google_analytics_default_allow_ad_user_data" android:value="false"/>
<meta-data android:name="google_analytics_default_allow_ad_personalization_signals" android:value="false"/>
```

### Eventos

| Evento | Parámetros |
| --- | --- |
| `game_start` | `kind`, `mode`, `ai_level` (partidas nuevas offline) |
| `game_end` | `kind`, `mode`, `result` (win/loss/draw/end), `plies` |
| `puzzle_solved` | `mate_in`, `daily`, `attempts` |
| `online_invite` | — |
| `online_join` | `via` (code/link) |

Sin uid, nombre de usuario ni correo. Verlos en directo: Analytics → **DebugView** con
`adb shell setprop debug.firebase.analytics.app com.tuempresa.escaque.qa` y una compilación release
del flavor qa.

### Panel de indicadores

En Analytics (o Looker Studio conectado a Analytics):

| Indicador | Objetivo inicial |
| --- | --- |
| Retención D1 / D7 | Medir la base antes de la fase C |
| Partidas por usuario activo y día | Ídem |
| % de usuarios activos que resuelven el problema del día | Ídem |
| Usuarios sin fallos (Crashlytics) | ≥ 99,5 % |

### Antes de publicar esta versión

- **Política de privacidad**: ya incluye «Estadísticas de uso» (landing).
- **Play Console → Seguridad de los datos**: añade «Interacciones en la app» y «Diagnóstico» con
  finalidad *Estadísticas*, opcional para el usuario.

---

## 6. Problemas: añadir sin publicar versión

La app trae sus problemas y, una vez al día, descarga el catálogo de la web de su entorno:
`https://<landing>/puzzles/catalog.json`. Los problemas con ids nuevos aparecen sin actualizar la app.

### Añadir problemas

```bash
cd tablero_app
python3 tool/puzzles/gen_more.py 400 150          # amplía ajedrez hasta 400 mates en 1 y 150 en 2
python3 tool/puzzles/gen_draughts_puzzles.py ...  # golpes de damas (ver el propio script)
flutter test test/puzzles_test.dart test/puzzles_draughts_test.dart   # verificación con el motor
```

Los existentes conservan su id (el progreso de cada persona se mantiene). Sube los cambios a `main`:
el despliegue de la landing (`npm run build`, que ejecuta `scripts/catalog.mjs`) publica el catálogo
en qa; con la etiqueta de versión, en producción.

### Garantías

- La app valida cada problema con el motor antes de usarlo y descarta los inválidos.
- Un catálogo vacío, roto o con otro formato no sustituye a la copia buena.
- Sin red, la app usa la copia guardada y los problemas incluidos.
- Los incluidos van siempre primero y en el mismo orden: el problema del día no cambia porque
  llegue un catálogo nuevo.
