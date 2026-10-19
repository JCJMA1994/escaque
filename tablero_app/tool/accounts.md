# Cuentas, inicio de sesión y tokens

Decisión: **dos modos**. *Sin cuenta* (offline) para jugar contra la IA o en local, y *con cuenta
registrada* para el modo online. Se elimina la sesión anónima: el servidor y las reglas de Firestore
rechazan cuentas anónimas.

## Por qué cuenta registrada para online

| Problema con la sesión anónima | Con cuenta registrada |
| --- | --- |
| Reinstalar o borrar datos crea otro uid: se pierden las partidas abiertas y el rival queda esperando | El uid sobrevive a reinstalaciones y cambios de móvil |
| Cuentas ilimitadas y gratis: base para spam y abuso de costes | Cada cuenta cuesta un correo verificado o una cuenta de Google |
| Sin forma de recuperar el acceso | Restablecer contraseña o volver a entrar con Google |
| Una partida solo se puede seguir en un dispositivo | Se sigue en cualquier dispositivo con la misma cuenta |

Offline no necesita cuenta: todo vive en el dispositivo (historial en SQLite, ajustes en
SharedPreferences) y se puede crear la cuenta más tarde sin perder nada.

## Métodos de acceso

1. **Google** (`google_sign_in` 6.x → `GoogleAuthProvider.credential` → Firebase). Un toque, correo
   ya verificado, sin contraseña que guardar. Requiere las huellas SHA-1 y SHA-256 en Firebase.
2. **Correo y contraseña** (Firebase Auth). Contraseña de 8 caracteres o más (también configurable
   como política en la consola). **El correo debe verificarse antes de jugar online**: lo exige el
   servidor, no solo la app.
3. Recuperación: «¿Olvidaste tu contraseña?» envía el correo de Firebase. Con la protección contra
   enumeración de correos activa (por defecto en proyectos nuevos), los errores de inicio de sesión no
   distinguen «no existe» de «contraseña incorrecta»; la app muestra un único mensaje.

Si un correo ya existe con Google y se intenta registrar con contraseña, Firebase devuelve
`email-already-in-use`: la app sugiere entrar con Google.

## Tokens

| Token | Quién lo emite | Vida | Dónde vive | Quién lo valida |
| --- | --- | --- | --- | --- |
| ID token de Firebase (JWT RS256) | Firebase Auth | 1 hora; el SDK lo renueva solo | Memoria del SDK | Servidor: firma (JWKS de Google), `iss`, `aud`, `exp`, `sub`, proveedor y correo verificado |
| Refresh token | Firebase Auth | Largo; se revoca al cambiar contraseña, deshabilitar o borrar la cuenta | Almacenamiento privado de la app | Solo Firebase |
| Token de App Check (JWT) | Firebase App Check (Play Integrity) | Minutos a horas | SDK | Servidor: firma, `iss`, `aud` |
| Token de Google Sign-In | Google | Corto | Solo durante el inicio de sesión | Firebase (al canjearlo) |
| Token de FCM | Firebase Messaging | Hasta que se rota o se desinstala | `users/{uid}/devices/{token}` | Servidor al enviar; se borra si FCM lo rechaza |
| OIDC de Cloud Scheduler | Google | 1 hora | — | Servidor: `iss`, `aud`, `email` |

Comprobaciones nuevas del servidor sobre el ID token:

- `firebase.sign_in_provider` distinto de `anonymous` → si no, `account_required`.
- Proveedor `password` con `email_verified = false` → `email_not_verified`.

Tras verificar el correo, la app fuerza `getIdToken(true)`: el token en caché seguiría diciendo
`email_verified: false` hasta una hora.

Revocación: el servidor no consulta la revocación en cada petición (necesitaría una llamada extra a
la API de Identity Toolkit). Tras cerrar sesión o cambiar la contraseña, un ID token robado sigue
siendo válido hasta su caducidad (máximo 1 hora). Aceptable para un juego; si algún día hay pagos, se
añade la comprobación.

## Cerrar sesión y borrar cuenta

- **Cerrar sesión**: se borra el token de FCM de ese dispositivo (para no recibir avisos de otra
  cuenta), luego `FirebaseAuth.signOut` y `GoogleSignIn.signOut`. Los datos offline se conservan.
- **Eliminar cuenta** (obligatorio en Google Play para apps con registro): `POST /v1/me/delete`
  abandona las partidas activas (gana el rival, motivo «cuenta eliminada»), cancela las que esperan,
  sustituye el nombre por «Cuenta eliminada» en todas sus partidas y borra `users/{uid}` con sus
  dispositivos. Después la app borra el usuario de Firebase Auth; si Firebase pide un inicio de
  sesión reciente, se vuelve a pedir la contraseña o Google y se reintenta. También se borran sus
  amistades y su valoración. El enlace web que pide Google Play para solicitar el borrado sin la app
  está publicado en la landing: `/eliminar-cuenta` (y `/en/delete-account`).

## Nombre de usuario

Lo que ven los rivales es un **nombre de usuario** que elige la persona (`@ana_88`), no el nombre de
Google ni el correo.

| Regla | Valor |
| --- | --- |
| Formato | 3 a 20 caracteres; letras sin tilde, números y `_`; empieza por letra; sin `__` |
| Unicidad | Sin distinguir mayúsculas: se guarda en minúsculas |
| Reservados | `admin`, `soporte`, `tablero`, `ia`, `bot`… (lista en el servidor) |
| Filtro | Lista básica de insultos por subcadena, ampliable en el servidor |
| Cambios | Uno cada 30 días; el anterior queda libre |
| Al borrar la cuenta | Se libera |

Cómo se garantiza la unicidad: el servidor reserva `usernames/{nombre}` con una escritura
condicionada a que el documento **no exista**, y en la misma escritura actualiza `users/{uid}` y libera
el nombre anterior. Si dos personas piden el mismo nombre a la vez, solo una escritura entra. Las reglas
de Firestore impiden que la app escriba `usernames` o el campo `username`.

Flujo: tras crear la cuenta o entrar con Google por primera vez, la app pide el nombre de usuario
(comprobando la disponibilidad mientras se escribe) y después, si hace falta, la verificación del
correo. Elegir el nombre se permite con el correo aún sin verificar; jugar online, no.

Al cambiarlo, las partidas en curso y en espera pasan a mostrar el nombre nuevo; las terminadas
conservan el que se usó al jugarlas.

La comprobación de disponibilidad no tiene límite de peticiones propio: los nombres de usuario son
públicos (los ve cualquier rival), así que enumerarlos no expone nada privado. App Check frena su uso
desde fuera de la app.
