# Escaque — hoja de ruta

Estado a 18/10/2026. **Todo lo priorizado está implementado en código** (fases A–E de
[PLAN.md](PLAN.md)) y pendiente de la primera compilación en el CI.

## Obligatorio (plazos de Google)

| Qué | Cuándo | Estado |
| --- | --- | --- |
| Apuntar a Android 16 (API 36) | Obligatorio para apps nuevas y actualizaciones desde el 31/08/2026 | Hecho: Flutter 3.47.7 en el CI |
| Atrás predictivo y de borde a borde | Obligatorios al apuntar a API 36 | Hecho: `PopScope` en la partida, áreas seguras, `enableOnBackInvokedCallback` |
| Google Sign-In con Credential Manager | Google retira las APIs antiguas de inicio de sesión | Hecho: `google_sign_in` 7 |
| Enlace web para borrar la cuenta | Requisito de Play para apps con registro | Hecho: `/eliminar-cuenta` y `/en/delete-account` |
| Siguiente nivel de API | Cada agosto | Actualizar Flutter en julio |
| Firebase 5.x | Publicado el 15/10/2026; se dejó la serie 4.x por prudencia | Actualizar a partir de noviembre (cambio: `minSdk` 24, ya aplicado) |

## Antes de publicar

| Qué | Dónde |
| --- | --- |
| Primera ejecución del CI y corrección de lo que salga | [CI_CD.md](CI_CD.md), «Primera ejecución» |
| Proyectos, servidor y Play Console configurados | [GUIA_CONFIGURACION.md](GUIA_CONFIGURACION.md) y [ENTORNOS_Y_DOMINIOS.md](ENTORNOS_Y_DOMINIOS.md) |
| Revisión legal de la política de privacidad y datos del titular | `landing/src/site.ts` |
| Registro de la marca «Escaque» | Oficina de marcas |
| Capturas de Play Store | Workflow `screenshots.yml` |

## Limitaciones conocidas

Diferencias con el diseño original que quedaron fuera (detalle en PLAN.md, «Cambio»):

| Qué | Efecto |
| --- | --- |
| Motor: tablas de las damas españolas, finales de 16 y 5 jugadas en las internacionales, posiciones muertas por bloqueo de peones | `tablero_engine/README.md`, «Pendiente» |

Cerradas el 18/10/2026: análisis cancelable, rechazar un reto, ajuste global de frases, lecciones de
damas chinas y de ahogado, y partidas en curso en la lista de amigos.

## Ideas para después

| Idea | Valor | Esfuerzo | Notas |
| --- | --- | --- | --- |
| Torneos entre amigos | Medio | Alto | Sobre retos y valoración existentes |
| Portugués | Medio | Bajo | `tr()` admite otro idioma con un archivo como `en.dart` |
| Flechas de análisis sobre el tablero | Medio | Medio | El análisis ya calcula la mejor alternativa |
| Modo espectador de partidas de amigos | Bajo | Medio | Lectura de `games` con reglas nuevas |
| Emparejamiento automático para partidas valoradas | Medio | Alto | Hoy solo entre amigos |
