# Landing de Escaque (Astro 5)

## Ejecución y depuración

### Desde la terminal
```bash
cd landing
npm install
npm run check          # Verificación estática con Astro Check
npm run dev            # Servidor local en http://localhost:4321
npm run build          # Compilación estándar
npm run build:qa       # Entorno QA: no indexable, franja «Entorno: QA»
npm run build:prod     # Producción: indexable y con sitemap
```

### Desde el IDE (VS Code / Antigravity)
Desde el panel **Ejecución y depuración** (`Ctrl+Shift+D`):
- **Landing: Servidor dev (Astro)**: inicia el servidor con recarga en vivo en `http://localhost:4321`.
- **Landing: Compilar (Astro build)**: ejecuta la compilación verificando páginas y el catálogo de problemas.


| Página | Ruta |
| --- | --- |
| Portada | `/` · `/en` |
| Política de privacidad | `/privacidad` · `/en/privacy` |
| Eliminar la cuenta (requisito de Google Play) | `/eliminar-cuenta` · `/en/delete-account` |
| Invitaciones (abre la app o lleva a Play) | `/j/CÓDIGO` (Firebase Hosting reescribe `/j/**` a `j.html`) |
| App Links | `/.well-known/assetlinks.json` (lo genera la compilación con `ANDROID_PACKAGE` y `ANDROID_SHA256`) |
| Catálogo de problemas | `/puzzles/catalog.json` (lo genera `scripts/catalog.mjs` desde `tablero_app/assets/` antes de cada compilación) |

Antes de publicar, revisa `src/site.ts` (enlace de Play, correo y los datos del titular entre
corchetes), la política de privacidad (borrador redactado conforme a la Ley 29733 de Perú y el RGPD,
pendiente de revisión legal) y `public/app-ads.txt`. Iconos y piezas son los mismos SVG propios de
la app.

Despliegue: `firebase deploy --project <entorno> --only hosting:landing` desde la raíz, o el CI.
