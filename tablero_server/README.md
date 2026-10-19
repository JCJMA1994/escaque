# tablero_server

Servidor autoritativo del modo online de Escaque, en Dart (shelf) para Cloud Run. Usa el mismo
`tablero_engine` que la app: una sola implementación de las reglas.

## API

Todas las rutas de jugador llevan `Authorization: Bearer <ID token de Firebase>` y, si App Check está
activo, `X-Firebase-AppCheck`. Las de `/v1/tasks/` exigen el token OIDC de la cuenta de Cloud
Scheduler (también la usa la suscripción push de Pub/Sub). Los errores devuelven `{error, message}`
con el mensaje en español; la app lo traduce por su código.

| Método y ruta | Cuerpo | Respuesta |
| --- | --- | --- |
| `POST /v1/usernames/check` | `username` | `available`, `username`, `reason?` |
| `POST /v1/me/username` | `username` | `username` |
| `POST /v1/me/delete` | — | `resigned`, `cancelled` |
| `POST /v1/games` | `kind`, `variant`, `seat` | `id`, `code` |
| `POST /v1/games/join` | `code` | `id`, `seat`, `kind`, `variant` |
| `POST /v1/games/{id}/rematch` | — | `id`, `seat` (partida nueva ya activa, colores cambiados; si el rival ya la pidió, la misma) |
| `POST /v1/games/{id}/moves` | `ply` (jugadas antes), `move` | `ply`, `status`, `result?` |
| `POST /v1/games/{id}/resign` | — | `ok` (en espera: cancela) |
| `POST /v1/games/{id}/draw` | `action`: `offer` · `accept` · `decline` | `ok` |
| `POST /v1/games/{id}/emote` | `phrase` (id de una de las 12 frases fijas) | `ok` |
| `POST /v1/games/{id}/decline` | — | `ok` (el retado rechaza un reto antes de su primera jugada: partida cancelada) |
| `POST /v1/friends/request` | `username` | `status`: `pending` · `accepted` (si te la había enviado) |
| `POST /v1/friends/respond` | `uid`, `accept` | `ok` |
| `POST /v1/friends/remove` | `uid` | `ok` (quita al amigo o cancela la solicitud enviada) |
| `POST /v1/friends/block` | `uid` | `ok` |
| `POST /v1/friends/unblock` | `uid` | `ok` (solo quien bloqueó) |
| `POST /v1/friends/challenge` | `uid`, `kind`, `variant?`, `seat`, `rated?` | `id`, `seat` (partida ya activa, sin código) |
| `POST /v1/purchases/verify` | `productId`, `token` | `adFree` |
| `POST /v1/tasks/deadlines` | — (Scheduler, cada 15 min) | `reminded`, `expired`, `cancelled`; además aplica las valoraciones pendientes |
| `POST /v1/tasks/leaderboards` | — (Scheduler, a diario) | `ok` |
| `POST /v1/tasks/play-rtdn` | mensaje push de Pub/Sub | `ok` (reembolsos y anulaciones de Google Play) |
| `GET /healthz` | — | `ok` |

Las de nombre de usuario, borrar cuenta y compras admiten correo aún sin verificar; el resto exige
cuenta verificada y nombre de usuario.

Códigos de error: `unauthorized`, `app_check`, `account_required`, `email_not_verified`,
`username_required`, `invalid_username`, `username_taken`, `username_cooldown`, `rate_limited`, `not_finished`, `opponent_gone`, `not_member`, `not_found`, `code_not_found`,
`own_game`, `already_started`, `not_active`, `not_your_turn`, `stale` (incluye `ply` del servidor),
`illegal_move`, `offer_pending`, `no_offer`, `draw_too_soon`, `too_many_waiting`, `busy`,
`emote_too_fast`, `not_a_challenge`, `already_moved`, `corrupt` (una partida guardada que el motor no
puede reconstruir), `social_unavailable`; amigos: `user_not_found`, `blocked`, `already_friends`, `request_pending`,
`requests_off`, `too_many_requests`, `too_many_friends`, `no_request`, `not_friends`; compras:
`purchases_unavailable`, `wrong_product`, `invalid_purchase`, `purchase_pending`,
`purchase_cancelled`, `purchase_other_account`.

## Garantías

- Cada jugada se valida reconstruyendo la partida con el motor; el resultado lo calcula el servidor.
- Escrituras con precondición de `updateTime`: dos jugadas simultáneas nunca entran las dos.
- Plazo de 72 h por jugada, recordatorio 24 h antes, derrota por tiempo según el reglamento.
- Máximo 10 partidas en espera por usuario; las de más de 7 días se cancelan.
- Una oferta de tablas cada dos jugadas propias.
- Valoraciones Glicko-2 aplicadas una sola vez por partida (`ratingApplied` en la misma escritura) y
  recogidas por el barrido si algo falló; no cuentan partidas de menos de 10 jugadas por bando ni
  más de 3 valoradas al día contra el mismo rival.
- Amistades y retos solo los escribe el servidor; bloquear impide solicitudes y retos en los dos
  sentidos.

## Ejecución y depuración

### Desde la terminal
```bash
cd tablero_server
dart pub get
dart analyze   # análisis estático
dart test      # lógica completa con almacén en memoria, sin red (75 tests)
dart run bin/server.dart  # arranque local del servidor
```

### Desde el IDE (VS Code / Antigravity)
En el panel **Ejecución y depuración** (`Ctrl+Shift+D`):
- **Server: Iniciar servidor local**: ejecuta `bin/server.dart` con puerto `8080` y entorno de desarrollo.
- **Server: Tests unitarios**: ejecuta los tests con soporte para depuración y puntos de interrupción.

Despliegue paso a paso: [GUIA_CONFIGURACION.md](../GUIA_CONFIGURACION.md).

## Juegos online

Ajedrez, las tres variantes de damas y damas chinas a dos jugadores (`kind: chineseCheckers`; un
jugador sin jugadas pasa automáticamente, igual que en la app). Las damas chinas no tienen
valoración.

## Variables de entorno

| Variable | Uso |
| --- | --- |
| `PROJECT_ID`, `PROJECT_NUMBER` | Proyecto de Firebase/Google Cloud (tokens, App Check, Firestore) |
| `SCHEDULER_SA`, `SERVICE_URL` | Cuenta y audiencia del token OIDC de las tareas |
| `APP_CHECK` | `monitor` (por defecto), `enforce` u `off` |
| `MOVE_TIME_HOURS` | Plazo por jugada (72 por defecto) |
| `ENVIRONMENT` | `dev`, `qa` o `prod` (lo pone el despliegue) |
| `PLAY_PACKAGE` | Paquete de Android para verificar compras (lo pone el despliegue); vacío = compras desactivadas |
| `PRODUCT_REMOVE_ADS` | Producto de «quitar anuncios» (`remove_ads` por defecto) |
| `LOAD_TEST_SECRET` | Solo qa: pruebas de carga (rechazado en prod) |

## Límites y registro

- 60 peticiones seguidas por cuenta y una más por segundo (`RateLimiter`), por instancia.
- Registro estructurado en JSON: los errores llegan agrupados a **Cloud Error Reporting**, con la
  revisión de Cloud Run como versión.

## Seguridad de la sesión

- Cambiar el nombre de usuario exige que el token no esté revocado; borrar la cuenta, además, un
  inicio de sesión de menos de 5 minutos. Se consulta Identity Toolkit (`accounts:lookup`, rol
  `roles/firebaseauth.viewer`) con caché de 5 minutos. Códigos: `token_revoked`,
  `recent_login_required`, `auth_unavailable`.

## Variables de entorno nuevas

| Variable | Para qué |
| --- | --- |
| `ENVIRONMENT` | `dev`, `qa` o `prod` (la fija el despliegue) |
| `LOAD_TEST_SECRET` | Solo qa: activa el modo de pruebas de carga (`x-load-test`). Prohibido en prod: el servidor no arranca |

## Compras

`POST /v1/purchases/verify` (`productId`, `token`): consulta la compra en la Google Play Developer
API, comprueba que es de esta cuenta (identificador ofuscado `sha256('escaque:'+uid)`), la reconoce
si hace falta y escribe `users/{uid}.adFree`. `POST /v1/tasks/play-rtdn` recibe las notificaciones
de Play por Pub/Sub (con el token OIDC de la cuenta de Scheduler) y retira la ventaja si hay
reembolso o anulación. Variables: `PLAY_PACKAGE` (sin ella, compras desactivadas) y
`PRODUCT_REMOVE_ADS` (por defecto `remove_ads`). El token para Play se pide con el ámbito
`androidpublisher` (`ScopedMetadataClient`).
