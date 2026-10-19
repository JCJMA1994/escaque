# Escaque — plan de implementación de la hoja de ruta

Plan para las 9 funciones y las 4 tareas de operación de la hoja de ruta. **Estado: las cinco
fases están implementadas en código** y pendientes de la primera compilación en el CI. Las
secciones 5 a 7 describen lo implementado y señalan dónde se apartó del diseño original («Cambio»).
Estimaciones en días de una persona (d).

---

## 1. Análisis

### Dependencias que deciden el orden

| Si haces… | …antes necesitas | Por qué |
| --- | --- | --- |
| Cualquier función nueva | **Medición** (nuevo punto 0) | Sin datos de uso no sabrás si los problemas, los logros o el chat mejoran la retención. Hoy la app no mide nada a propósito (privacidad) |
| Más pantallas y textos | **Inglés (1)** | Cada función que se añade antes de internacionalizar es texto que habrá que extraer después. Hacerlo primero abarata todo lo demás |
| Amigos, Elo, chat | **Revocación de tokens**, **pruebas de carga**, **alertas** | Más tráfico y más datos personales en el servidor: hay que verlo y protegerlo antes |
| Elo (6) | **Amigos (5)** | Sin rivales conocidos, las partidas valoradas se llenan de abusos (cuentas propias para regalarse puntos) |
| Tutorial (7) | **Más problemas (3)** | Ambos usan el mismo motor de «posición + objetivo» |
| Quitar anuncios (9) | Servidor y cuentas (hechos) | La compra se valida en el servidor |

### Valor frente a esfuerzo

| # | Función | Valor | Esfuerzo | Encaje |
| --- | --- | --- | --- | --- |
| 0 | Medición con consentimiento | Alto (habilita decidir) | 2 d | Firebase Analytics + modo de consentimiento con UMP |
| 1 | Inglés | Alto | 8 d | `gen-l10n`, códigos de error del servidor, landing `/en` |
| 2 | Logros y clasificaciones | Medio | 4 d | `games_services`, sin tocar el servidor |
| 3 | Más problemas y de damas | Alto | 5 d | Generador existente + catálogo en Firestore |
| 4 | Análisis tras la partida | Medio | 5 d | IA existente en un isolate |
| 5 | Lista de amigos | Alto | 8 d | Endpoints nuevos y una colección |
| 6 | Elo (Glicko-2) | Medio | 7 d | En la misma transacción que el fin de partida |
| 7 | Tutorial interactivo | Medio | 5 d | Reutiliza la pantalla de problemas |
| 8 | Chat con frases fijas | Bajo | 2 d | Ids de frase, no texto libre |
| 9 | Quitar anuncios | Medio | 6 d | `in_app_purchase` + verificación en servidor |
| O1 | Alertas de Cloud Monitoring | Alto | 1 d | Políticas como código |
| O2 | Copia diaria de Firestore | Alto | 0,5 d | Copias programadas nativas + PITR |
| O3 | Revocación de tokens | Medio | 2 d | Identity Toolkit REST |
| O4 | Pruebas de carga | Medio | 2 d | k6 contra qa |

Total: unos 58 días de trabajo, unas 13 semanas a tiempo completo.

---

## 2. Fases

| Fase | Semanas | Contenido | Resultado |
| --- | --- | --- | --- |
| **A. Base** ✅ código | 1–2 | O1, O2, O3, O4, punto 0 | Lo ves todo, puedes recuperar datos y sabes cuánta carga aguanta. Implementada; para activarla en los proyectos, [OPERACION.md](OPERACION.md) |
| **B. Alcance** ✅ código | 3–4 | 1 (inglés) | App y web en dos idiomas; ficha de Play en inglés. Implementada: ver `tablero_app/tool/i18n.md` y `tablero_app/store/listing.md` |
| **C. Retención** ✅ código | 5–8 | 3, 7, 2, 4 | Motivos para volver cada día. Implementada: 300 problemas de ajedrez y 100 golpes de damas con catálogo remoto (OPERACION.md, 6), 19 lecciones, logros y clasificaciones de Play Games, análisis tras la partida |
| **D. Ingresos** ✅ código | 9 | 9 | Primera fuente de ingresos además de anuncios. Implementada: compra `remove_ads` verificada y reconocida en el servidor, reembolsos por notificaciones de Play (GUIA, 14.8) |
| **E. Social** ✅ código | 10–13 | 5, 8, 6 | Jugar con conocidos y competir. Implementada: amistades con límites y bloqueo, retos directos, 12 frases fijas, valoración Glicko-2 por juego con anti-abuso y barrido, clasificaciones diarias |

Cada fase termina con una versión en producción. La compra (D) va antes que lo social porque
genera ingresos con poco riesgo y no depende de tener usuarios activos online.

---

## 3. Fase A — Base de operación ✅

### O1. Alertas de Cloud Monitoring ✅ (1 d)

Políticas en `infra/monitoring/*.yaml`, aplicadas por entorno con
`gcloud monitoring policies create --policy-from-file`, para que sean reproducibles en qa y prod.

| Alerta | Condición | Canal |
| --- | --- | --- |
| API caída | Comprobación de disponibilidad de `https://api-escaque…/healthz` falla 2 veces seguidas desde 3 regiones | Correo + móvil (app de Google Cloud) |
| Errores del servidor | Respuestas 5xx > 2 % durante 5 min | Correo |
| Lentitud | Latencia p95 de Cloud Run > 1,5 s durante 10 min | Correo |
| Errores nuevos | Cloud Error Reporting: notificación de errores nuevos (consola) | Correo |
| Scheduler | Trabajo `tablero-deadlines` falla 3 veces seguidas | Correo |
| Crashlytics | Alertas de nuevos fallos y de regresiones (consola de Firebase) | Correo |

Hecho cuando: un `exit(1)` provocado en qa dispara la alerta en menos de 5 minutos.

### O2. Copia diaria de Firestore ✅ (0,5 d)

Firestore tiene copias programadas nativas; no hace falta exportar a mano.

```bash
gcloud firestore backups schedules create --database='(default)' \
  --recurrence=daily --retention=14d --project=escaque-prod
gcloud firestore databases update --database='(default)' \
  --enable-pitr --project=escaque-prod   # recuperación a cualquier minuto de los últimos 7 días
```

- qa: copia semanal con retención de 4 semanas.
- **Simulacro trimestral**: restaurar la última copia en una base nueva (`escaque-restore`) y
  comprobar que hay partidas. Documentarlo en la guía.

Hecho cuando: el primer simulacro restaura en menos de 30 minutos.

### O3. Revocación de tokens ✅ (2 d)

El servidor valida la firma y la caducidad del token (1 h), pero no sabe si la cuenta cerró sesión
en todos los dispositivos o cambió la contraseña. No hay SDK Admin para Dart, así que:

1. Para **operaciones sensibles** (borrar cuenta, cambiar nombre de usuario), el servidor consulta
   `accounts:lookup` de Identity Toolkit con su cuenta de servicio y obtiene `validSince` (y
   `disabled`).
2. Rechaza el token si `iat < validSince` → `401 token_revoked`.
3. Para borrar la cuenta exige además `auth_time` de menos de 5 minutos → `401 recent_login_required`
   (la app ya sabe reautenticar).
4. Caché por usuario de 5 minutos para no consultar en cada petición.

Tests: token emitido antes de `validSince`, cuenta desactivada y `auth_time` antiguo.

### O4. Pruebas de carga ✅ (2 d)

- Script de **k6** en `tool/load/partidas.js`: N parejas crean, se unen y juegan 40 jugadas con
  pausas realistas.
- Autenticación: un modo de pruebas en el servidor, `LOAD_TEST_SECRET`, que acepta `X-Test-User`
  **solo** con ese secreto y **se niega a arrancar si `ENV=prod`**. Solo en qa.
- Objetivos con 200 partidas simultáneas:

| Métrica | Objetivo |
| --- | --- |
| p95 de `POST /moves` | < 800 ms |
| Errores 5xx | 0 % |
| Jugadas perdidas por conflicto | 0 (los reintentos con precondición deben absorberlos) |
| Coste en Firestore | Medido y anotado (lecturas y escrituras por partida) |

- Workflow manual `load.yml` contra qa.

Hecho cuando: el informe de k6 se guarda como artefacto y cumple la tabla.

### 0. Medición con consentimiento ✅ (2 d)

- `firebase_analytics` con **modo de consentimiento v2**. *Cambio:* desactivadas hasta que la
  persona acepta **en todos los países** (la Ley 29733 de Perú y su Reglamento de 2025 exigen
  consentimiento previo, como el RGPD). Tarjeta única en Inicio y interruptor «Estadísticas de uso»
  en Ajustes → Privacidad; Crashlytics no recibe el uid (OPERACION.md, 5).
- Eventos mínimos, sin datos personales:

| Evento | Parámetros |
| --- | --- |
| `game_start` / `game_end` | `kind`, `mode` (ia/local/online), `ai_level`, `result` |
| `puzzle_solved` | `mate_in`, `daily`, `attempts` |
| `online_invite` / `online_join` | `via` (código/enlace) |
| `tutorial_step` | `lesson`, `ok` |
| `purchase_remove_ads` | — |

- KPI en un panel: retención D1/D7, partidas por usuario y día, % del problema del día resuelto,
  usuarios sin fallos (objetivo ≥ 99,5 %).
- Actualizar la política de privacidad y el formulario de seguridad de los datos de Play.

---

## 4. Fase B — Inglés (1) ✅

| Parte | Trabajo |
| --- | --- |
| App | *Cambio:* en lugar de `gen-l10n` con ARB, `tr()` con el español como clave y las traducciones en `lib/l10n/en.dart` (motivos en `tablero_app/tool/i18n.md`). Plurales con dos claves. Selector Sistema / Español / English |
| Contenido | Reglas (`rules_sheet.dart`), anuncios de jugadas (`Spoken`), nombres de piezas y variantes, textos de problemas |
| Servidor | Hoy devuelve mensajes en español. Pasa a devolver solo el **código** de error (ya existe) y la app lo traduce. Las notificaciones push se generan en el idioma guardado en `users/{uid}.locale` (la app lo escribe al cambiar) |
| Landing | Rutas `/en/…` con `i18n` de Astro, `hreflang`, selector de idioma, privacidad y borrado de cuenta en inglés |
| Play | Ficha y capturas en inglés |
| Control | `tool/verify_repo.py` rechaza `Text('…')` literal sin `tr()`; `test/l10n_test.dart` exige traducción y los mismos marcadores para cada texto, incluidas las lecciones. *Cambio:* sin pseudoidioma |

Riesgo: los textos legales en inglés también requieren revisión.

---

## 5. Fase C — Retención ✅

Cada apartado describe lo implementado; «Cambio» señala dónde se apartó del diseño original.

### 3. Más problemas y de damas

- **Ajedrez:** 300 problemas (200 de mate en 1 y 100 de mate en 2) con solución única y
  dificultad 1–3 (jaques «tentadores» que no dan mate). `tablero_app/tool/puzzles/gen_more.py` amplía el
  catálogo sin cambiar los ids existentes. *Cambio:* sin mate en 3 (la demostración de unicidad
  sería demasiado lenta en el generador).
- **Damas:** 100 «golpes» (40 internacionales, 30 españoles, 30 ingleses): una única jugada que,
  responda lo que responda el rival, gana al menos 2 de material (dama = 3). Generados con el
  prototipo y verificados por el motor de Dart (`test/puzzles_draughts_test.dart`). *Cambio:* el
  tipo «golpe» sustituye a «gana en 2» y «corona a la fuerza»: es el problema clásico de damas y
  la captura obligatoria lo hace forzado.
- **Catálogo remoto:** archivo estático `/puzzles/catalog.json` en la web de cada entorno, generado
  en cada compilación de la landing (`landing/scripts/catalog.mjs`). La app lo descarga como mucho
  una vez al día, valida cada problema con el motor y usa los incluidos si no hay red
  (OPERACION.md, 6). *Cambio:* Firebase Hosting en lugar de una colección de Firestore: sin reglas,
  sin coste por lectura y con CDN; no hace falta el script de publicación previsto.

### 7. Tutorial interactivo

- 19 lecciones como datos (`lib/learn/lessons.dart`): posición, instrucción, jugadas aceptadas,
  jugadas «trampa» con su explicación y texto de acierto; `test/lessons_test.dart` las verifica con
  el motor.
- Ajedrez (10): torre, alfil, caballo, dama, coronación, enroque, captura al paso, salir del jaque,
  jaque mate y ahogado (dos jugadas ahogan y se explica por qué son tablas). Damas (6): mover,
  captura obligatoria, capturas en cadena, coronar, dama larga y ley de la mayoría. Damas chinas
  (3): mover, saltar y saltos en cadena, con posiciones en coordenadas hexagonales.
- Desde Inicio («¿Nuevo en estos juegos?») y desde la hoja de reglas («Practicar»). Progreso en el
  dispositivo; evento `tutorial_step`.
- *Cambio:* no se ofrecen al terminar la presentación.

### 2. Logros y clasificaciones de Google Play Games

- Plugin `games_services` 5.x tras la clase propia `PlayGames`; IDs por `--dart-define`
  (GUIA, 14.7). Sin IDs, todo queda inactivo y los botones se ocultan.
- 10 logros y 3 clasificaciones (problemas resueltos, mejor racha, victorias contra el nivel 5).
  Lo desbloqueado sin sesión se guarda y se envía después. Botones «Logros» y «Clasificaciones» en
  Inicio.
- *Cambio:* el logro «Coronar con captura en damas internacionales» se sustituyó por «Todas las
  lecciones completadas».

### 4. Análisis tras la partida

- «Analizar la partida» en la revisión: la IA de nivel 5 evalúa cada posición en un isolate
  (0,3 s por posición) con barra de progreso.
- Gráfica propia (`CustomPainter`), errores graves (≥ 200 cp), imprecisiones (≥ 80 cp), mejor
  alternativa y botón «Jugada clave»; TalkBack lee «Jugada 14 (Cxe5): error grave; mejor era…».
- Se guarda en SQLite para no repetirlo. *Cambio:* en una tabla `analysis` aparte (migración a la
  versión 2) en lugar de una columna de `games`, para no tocar la tabla principal. Se puede
  detener («Detener», o al salir de la pantalla): corre en un isolate propio que se termina al
  momento.

---

## 6. Fase D — Quitar anuncios (9) ✅

| Pieza | Implementado |
| --- | --- |
| Producto | No consumible `remove_ads` en Play Console (GUIA, 14.8) |
| App | `in_app_purchase` 3.3 tras `AdFreeController`; sección «Sin anuncios» en Ajustes y enlace en el resultado; «Restaurar compras» |
| Validación | `POST /v1/purchases/verify`: Google Play Developer API (`purchases.products.get`) con la cuenta del servidor `tablero-api`, comprobación de que la compra es de esa cuenta (identificador ofuscado del uid) y **reconocimiento** si hace falta. El token se pide con el ámbito `androidpublisher` (`ScopedMetadataClient`) |
| Derecho | `users/{uid}.adFree` (solo lo escribe el servidor) y copia local. La ventaja se activa al confirmar Google Play, y la verificación se reintenta si no hay red. Una compra hecha sin cuenta se liga a la cuenta al iniciar sesión |
| Reembolsos | RTDN → Pub/Sub (push con la cuenta de Scheduler) → `POST /v1/tasks/play-rtdn` retira `adFree` |
| Anuncios | Sin banners, intersticiales ni recompensados; las pistas pasan a ser directas |
| Pruebas | Testers de licencia; tests del servidor con la API simulada y test de que app y servidor calculan el mismo identificador ofuscado |

---

## 7. Fase E — Social ✅

### 5. Lista de amigos

| Pieza | Implementado |
| --- | --- |
| Datos | `friendships/{uidA_uidB}` (uids ordenados): `status` (pending/accepted/blocked), `requestedBy`, `blockedBy`, nombres y fechas. Solo los escribe el servidor; cada miembro lee los suyos |
| API | `POST /v1/friends/request` (por nombre de usuario exacto; si la otra persona ya la había enviado, queda aceptada), `respond` (aceptar o rechazar), `remove`, `block`, `unblock` |
| Retar | `POST /v1/friends/challenge` crea la partida ya activa con los dos jugadores (sin código), valorada o no, y avisa al amigo. El retado puede rechazarla antes de su primera jugada (`POST /v1/games/{id}/decline`): queda cancelada, sin ganador ni valoración, y se avisa a quien retó |
| Privacidad | Búsqueda solo por nombre exacto. Bloquear impide solicitudes y retos en los dos sentidos y no se avisa. Ajuste «Solicitudes de amistad» |
| Límites | 20 solicitudes al día; máximo 200 amigos |
| App | Pantalla «Amigos» (desde la sala online, con el número de solicitudes): solicitudes, amigos con «Retar» y las partidas en curso con cada uno («Te toca en 1 partida»; al tocarlo se abre), enviadas y bloqueados |
| Avisos | Solicitud recibida, aceptada y reto; los de amistad abren la pantalla de amigos |
| Borrar cuenta | Elimina sus amistades y su valoración |

### 8. Chat con frases fijas

- 12 frases con id (`hello`, `good_luck`, `good_move`, `oops`, `thinking`, `thanks`,
  `well_played`, `rematch`, `sorry`, `wow`, `your_turn`, `bye`), traducidas en la app.
- `POST /v1/games/{id}/emote`: valida el id, 1 cada 5 s por jugador, guarda las 10 últimas.
- La frase del rival aparece como mensaje flotante 3 s y TalkBack la lee. Se silencia por partida
  o para todas (Ajustes → «Frases del rival»).

### 6. Valoración — Glicko-2

- Glicko-2 (τ = 0,5), una valoración por juego: ajedrez y cada variante de damas; las damas chinas
  no tienen valoración. Verificado con el ejemplo del artículo de Glickman.
- Partidas valoradas solo en retos entre amigos, si quien reta lo elige.
- *Cambio:* la valoración no se calcula en la escritura que termina la partida (hay cinco caminos
  de fin: jugada, abandono, tablas, plazo y borrar cuenta). Se aplica justo después en una escritura
  con precondición que marca `ratingApplied` en la partida, de forma idempotente, y el trabajo de
  plazos hace un **barrido** de las que quedaran sin aplicar. El resultado es el mismo: ninguna
  partida terminada se queda sin valorar.
- Anti-abuso: no cuentan las partidas con menos de 10 jugadas por bando ni, contra el mismo rival,
  a partir de la cuarta valorada en 24 h. *Cambio:* se excluyen en lugar de bajar su peso.
- `ratings/{uid}`: valor, desviación, volatilidad y partidas por juego. Clasificación **diaria**
  (no semanal) por Cloud Scheduler en `leaderboards/{juego}`: las 100 mejores no provisionales.
- App: valoración junto al nombre en las partidas valoradas y pantalla «Clasificación» con la propia.
- Tests: ejemplo de Glickman, idempotencia, partidas cortas, anti-abuso, barrido y clasificación.
  La concurrencia de dos partidas que terminan a la vez está cubierta por las precondiciones y el
  reintento, sin test específico.

---

## 8. Calidad en cada función

Cada punto se considera terminado cuando cumple esta lista:

| Comprobación | Dónde |
| --- | --- |
| Tests unitarios del motor o del servidor afectado | `dart test` en el CI |
| Reglas de Firestore nuevas con sus tests | `firebase/tests` en el CI |
| Textos en los dos idiomas (desde la fase B) | Regla de `verify_repo.py` |
| Accesible con TalkBack y objetivos de 48 dp | Prueba manual con lista en el PR |
| Evento de analítica, si mide algo | Punto 0 |
| Guía y `CI_CD.md` actualizados si hay configuración nueva | Revisión del PR |
| Política de privacidad y seguridad de los datos, si cambian los datos | Revisión del PR |
| Desplegado en qa y probado por testers antes de prod | Workflow `deploy.yml` |

---

## 9. Riesgos

| Riesgo | Mitigación |
| --- | --- |
| La primera ejecución del CI destapa errores de compilación | Resolverlos antes de empezar la fase A (es el punto 1 del README) |
| Costes de Firestore al crecer (amigos, frases, valoraciones) | Medir en las pruebas de carga (O4) y presupuestos con alertas |
| Abuso en partidas valoradas | Solo entre amigos al principio; reglas anti-abuso; revisar las 100 primeras de la clasificación |
| Rechazo en Play por datos o compras | Actualizar el formulario de seguridad de los datos en cada fase que lo cambie |
| Plugins de terceros sin mantenimiento (`games_services`, `in_app_review`) | Fijar versiones; aislar cada uno detrás de una clase propia, como `StorePrompts` |
