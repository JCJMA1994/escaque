# Escaque

Ajedrez y damas con reglas oficiales para Android. Monorepo:

| Carpeta | Qué es |
| --- | --- |
| `tablero_engine/` | Motor de reglas en Dart puro (ajedrez FIDE, damas internacional, inglesa y española, damas chinas) e IA |
| `tablero_server/` | Servidor autoritativo en Dart para Cloud Run: partidas, nombres de usuario, amigos, valoraciones, compras, plazos y avisos |
| `tablero_app/` | App Flutter + Flame |
| `landing/` | Web en Astro: portada, privacidad, eliminación de cuenta, invitaciones, catálogo de problemas, `app-ads.txt` |
| `firebase/`, `firebase.json` | Reglas e índices de Firestore con sus tests; Hosting de la landing y de la API por entorno |
| `infra/` | Alertas de Cloud Monitoring y copias de Firestore como código |
| `tool/` | Verificación del repositorio, auditoría de conexiones y pruebas de carga |
| `.github/workflows/` | CI, despliegues, integración en emulador, pruebas de carga y capturas de Play |

## Documentación

| Documento | Para qué |
| --- | --- |
| [GUIA_CONFIGURACION.md](GUIA_CONFIGURACION.md) | De cero a publicado, un entorno |
| [ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md) | dev, qa y prod con subdominios de `system-failed-tech.com` |
| [CI_CD.md](CI_CD.md) | GitHub Actions con Workload Identity Federation y comprobaciones sin compilar |
| [OPERACION.md](OPERACION.md) | Alertas, copias, revocación de tokens, pruebas de carga, estadísticas y catálogo de problemas |
| [PLAN.md](PLAN.md) · [ROADMAP.md](ROADMAP.md) | Lo implementado por fases, limitaciones conocidas e ideas |
| `tablero_app/README.md` | Funciones de la app y estructura; enlaza a diseño, cuentas, idiomas y ficha de Play |
| `tablero_server/README.md` | API, garantías y variables de entorno |
| `tablero_engine/README.md` | Reglas, IA y verificación del motor |
| `landing/README.md` | Páginas de la web |

## Ejecución y depuración

El proyecto cuenta con perfiles listos en `.vscode/launch.json` para ejecutar y depurar cualquier componente desde el panel **Ejecución y depuración** del IDE (`Ctrl+Shift+D`), así como comandos directos de terminal:

| Componente | Ejecución / Tests (Terminal) | Perfil de depuración en IDE |
| --- | --- | --- |
| **`tablero_app`** | `flutter test` · `flutter run --flavor dev --dart-define-from-file=config/dev.json` | `App: Escaque (dev)` · `App: Tests unitarios` |
| **`tablero_server`** | `dart test` · `dart run bin/server.dart` | `Server: Iniciar servidor local` · `Server: Tests unitarios` |
| **`tablero_engine`** | `dart test` · `dart run example/main.dart` | `Engine: Tests unitarios` · `Engine: Ejemplo (main.dart)` |
| **`landing`** | `npm --prefix landing run dev` · `npm --prefix landing run build` | `Landing: Servidor dev (Astro)` |
| **`tool/`** | `python tool/verify_repo.py` · `python tool/audit_wiring.py` | Tareas: `Tool: Verificar Monorepo` · `Tool: Auditar Conexiones` |

Consulte el `README.md` de cada subcarpeta para detalles específicos de configuración y variables de entorno.

## Estado

Implementado en código (fases A–E de PLAN.md):

- **Juegos:** ajedrez, tres variantes de damas y damas chinas de 2 a 6 jugadores, con IA de 5
  niveles, local y online por turnos (código, enlace, revancha, tablas, plazos y avisos).
- **Aprender:** 300 problemas de ajedrez y 100 golpes de damas con catálogo remoto, problema del
  día, 19 lecciones y análisis tras la partida.
- **Social:** amigos por @usuario con retos directos, frases fijas y valoración Glicko-2 con
  clasificaciones.
- **Cuenta e ingresos:** Google o correo verificado, nombre de usuario único, borrar cuenta en la
  app y en la web; anuncios con consentimiento y compra única para quitarlos, verificada en el
  servidor; logros de Google Play Games.
- **Calidad:** español e inglés en app, avisos y web; TalkBack y diseño adaptable; Crashlytics,
  Error Reporting, Remote Config, alertas, copias y pruebas de carga; privacidad conforme a la Ley
  29733 de Perú y al RGPD (estadísticas desactivadas hasta aceptarlas).
- **Comprobaciones sin compilar:** sintaxis de todo el Dart, conexiones entre app, servidor y
  landing, traducciones y documentos (`tool/verify_repo.py`, `tool/audit_wiring.py`).

Pendiente: ver [ROADMAP.md](ROADMAP.md), «Antes de publicar». Lo primero es **la primera ejecución
real del CI**: nada se ha compilado todavía.
