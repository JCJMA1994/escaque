# Escaque — app Android

**Configuración paso a paso (Firebase, servidor, AdMob, Play): [GUIA_CONFIGURACION.md](../GUIA_CONFIGURACION.md).**

App Flutter de juegos de mesa con reglas oficiales: ajedrez (FIDE), damas internacionales, inglesas
y españolas, y damas chinas de 2 a 6 jugadores. Usa el motor `tablero_engine` (carpeta hermana) y
Flame para el tablero. En español e inglés.

## Puesta en marcha

```bash
cd tablero_app
flutter create --platforms=android --org com.tuempresa --project-name tablero_app .
python3 tool/bootstrap_android.py --package com.tuempresa.escaque   # configura android/
cp config/dev.json.example config/dev.json
flutter pub get
flutter test
flutter run --flavor dev --dart-define-from-file=config/dev.json
```

## Ejecución y depuración

### Desde la terminal
```bash
cd tablero_app
flutter pub get
flutter analyze --no-pub                                             # Análisis de código y lints
flutter test                                                         # 450 tests unitarios
flutter run --flavor dev --dart-define-from-file=config/dev.json     # Ejecución con Hot Reload
```

### Desde el IDE (VS Code / Antigravity)
En el panel **Ejecución y depuración** (`Ctrl+Shift+D`):
- **App: Escaque (dev)**: arranca la app con el entorno `dev`, hot reload y depuración de widgets.
- **App: Escaque (qa)**: arranca con el entorno `qa`.
- **App: Escaque (prod)**: arranca con la configuración de producción.
- **App: Tests unitarios**: ejecuta y depura los 450 tests unitarios.
- **App: Test de integración (offline flow)**: corre el flujo sin conexión en emulador.

Sin Firebase ni servidor configurados, la app funciona igual sin conexión (IA, local, problemas,
lecciones e historial) y la sección online lo indica.

## Estructura

```
lib/
├─ main.dart        arranque: Firebase, Crashlytics, Remote Config, anuncios, compras, avisos
├─ app/             router, tema (design system), ajustes, entorno, analítica (Metrics),
│                   Crashlytics (Telemetry), Remote Config, Play Games, reseñas, sonidos
├─ l10n/            tr() y traducciones al inglés (tool/i18n.md)
├─ onboarding/      presentación de la primera vez
├─ account/         Google y correo, verificación, nombre de usuario, borrar cuenta
├─ match/           configuración, controlador (Riverpod), vista, anuncios para TalkBack
│  └─ adapters/     ajedrez, damas y damas chinas → casillas
├─ board/           tablero en Flame: componentes, piezas, disposición
├─ screens/         inicio, nueva partida, partida, resultado, historial, revisión, ajustes,
│                   sala online, invitaciones, hoja de reglas
├─ puzzles/         problemas de ajedrez y golpes de damas, catálogo remoto, problema del día
├─ learn/           19 lecciones interactivas (lessons.dart; verificadas en test/lessons_test.dart)
├─ analysis/        análisis tras la partida y gráfica de evaluación
├─ online/          cliente de la API, repositorio (Firestore), avisos FCM, frases fijas
├─ social/          amigos y retos, valoración y clasificación
├─ purchases/       compra «quitar anuncios»
├─ ads/             AdMob con UMP, banner
├─ data/            SQLite (partidas y análisis), exportar PGN y PDN
├─ ui/              iconos y piezas propios (SVG), anchos adaptables
└─ widgets/         Segmented, PlayerBar, MoveStrip
```

Flujo: un toque o un arrastre en el tablero → `MatchController` → el adaptador valida con el motor →
nuevo `MatchView` → `BoardGame.sync` anima la diferencia. Flame nunca decide la legalidad.

## Qué hace

**Jugar**
- Contra la IA (5 niveles, pistas con anuncio recompensado o directas sin anuncios), en el mismo
  teléfono o online. La IA calcula en un `Isolate`; en damas chinas a dos jugadores usa alfa-beta
  desde el nivel 3.
- Ajedrez: coronación, jaque resaltado, SAN (también con letras en español), tablas reclamables,
  caída de bandera según FIDE. Damas: aviso de captura obligatoria, elección de recorrido cuando
  dos capturas acaban en la misma casilla, animación salto a salto.
- Relojes con incremento, deshacer contra la IA, girar tablero, tocar o arrastrar piezas; temas
  Madera, Fieltro y Alto contraste.
- La partida en curso se guarda tras cada jugada; las terminadas van al historial con revisión,
  exportación PGN/PDN y balance.

**Aprender y practicar**
- 300 problemas de ajedrez (mate en 1 y en 2) y 100 golpes de damas, todos con solución única
  verificada por el motor; problema del día con racha. Catálogo remoto diario desde la web
  (`puzzles/catalog.dart`), validado antes de usarlo.
- 19 lecciones (10 de ajedrez, 6 de damas y 3 de damas chinas) desde Inicio y desde la hoja de
  reglas («Practicar»).
- Análisis tras la partida en la revisión: gráfica de evaluación, errores graves, imprecisiones,
  mejor alternativa y jugada clave; se puede detener y se guarda para no repetirlo.

**Online** (servidor autoritativo en `../tablero_server`)
- Partidas por turnos con código o enlace (`/j/CÓDIGO`), revancha con un toque, tablas y abandono.
  Cada jugada la valida el servidor; los clientes solo leen Firestore.
- Amigos por @usuario: solicitudes, bloqueo, partidas en curso con cada uno y retos directos,
  valorados o no; el retado puede rechazarlos antes de mover.
- 12 frases fijas durante la partida (sin texto libre), silenciables por partida o en Ajustes.
- Valoración Glicko-2 por juego y clasificación diaria de las 100 mejores.
- Avisos FCM en el idioma de la app: te toca, rival unido, tablas, final, recordatorio, revancha,
  solicitud de amistad y reto. App Check (Play Integrity) en cada petición.

**Cuenta, ingresos y tienda**
- Sin cuenta para jugar sin conexión; con cuenta (Google o correo verificado) para online. Nombre
  de usuario único, un cambio cada 30 días; borrar cuenta en la app y en la web
  (`tool/accounts.md`).
- AdMob con consentimiento UMP; nunca hay anuncios durante una partida. Compra única «quitar
  anuncios», verificada en el servidor y válida en todos los teléfonos de la cuenta.
- Logros y clasificaciones de Google Play Games (opcionales), petición de reseña y actualizaciones
  desde Play.

**Privacidad, calidad y accesibilidad**
- Estadísticas de uso desactivadas hasta que la persona acepta; Crashlytics sin identificar a nadie.
- TalkBack anuncia cada jugada y cada frase; respeta «Quitar animaciones»; diseño para teléfono,
  tablet y plegable.
- Remote Config: versión mínima, interruptor del modo online y frecuencia de anuncios.

## Pruebas

| Dónde | Qué |
| --- | --- |
| `test/` | Adaptadores, datos, traducciones (incluidas las lecciones y sus trampas), las 19 lecciones y los problemas de ajedrez y de damas verificados con el motor, catálogo remoto, compras, anuncios de voz |
| `integration_test/offline_flow_test.dart` | Flujo completo sin conexión en un emulador (CI de cada noche) |
| `integration_test/screenshots_test.dart` | Capturas de Play Store en teléfono y tablet, en los dos idiomas (`screenshots.yml`) |

## Documentos

| Documento | Contenido |
| --- | --- |
| `tool/design.md` | Marca, paleta, tipografía, iconos y diseño adaptable |
| `tool/accounts.md` | Cuentas, tokens, nombre de usuario y borrado |
| `tool/i18n.md` | Idiomas y cómo añadir textos |
| `tool/android_setup.md` | Configuración de Android y AdMob |
| `store/listing.md` | Ficha de Play en español e inglés y recursos gráficos |

## Pendiente

- Primera compilación real en el CI (nada se ha compilado aún; ver `../CI_CD.md`).
- Comprobar el registro de la marca «Escaque» antes de publicar.
- Revisión legal de la política de privacidad y datos del titular en `../landing/src/site.ts`.
