# Escaque — diseño, marca y UX

## Nombre

**Escaque** (cada casilla del tablero de ajedrez o damas). Título en Play Store:
**«Escaque: Ajedrez y Damas»** (24 de los 30 caracteres permitidos).

| | Tablero (antes) | Escaque |
| --- | --- | --- |
| Distintivo en la tienda | No: es el nombre de la categoría de juegos de mesa | Sí: palabra del dominio, poco usada |
| Búsquedas | Se pierde entre cientos de resultados | Las palabras clave van en el subtítulo |
| Registro de marca | Término genérico, débil | Viable; **pendiente de comprobar** en la oficina de marcas antes de publicar |

En el código se mantienen los nombres internos (`tablero_engine`, `TableroColors`): renombrarlos no
cambia nada para el usuario y rompería historiales y rutas.

## Auditoría UX/UI y cambios

| Problema | Impacto | Cambio |
| --- | --- | --- |
| Fondo crema con serif expresiva: la combinación más repetida en apps generadas, sin identidad | Marca genérica | Paleta mineral y fieltro de mesa de club; una sola familia, Archivo, en dos anchos |
| Piezas de ajedrez con glifos Unicode: cambian según el móvil y algunos no tienen fuente | Tablero roto o inconsistente | Set propio de piezas en SVG |
| Iconos de Material: aspecto de plantilla | Sin identidad | 39 iconos propios en SVG |
| Fuentes descargadas en el primer arranque | Texto con la fuente equivocada sin conexión | Fuentes variables incluidas en la app |
| Solo vertical; en tablet el tablero queda pequeño y sobra espacio | Mala experiencia en tablets y plegables | Clases de ventana; partida a dos columnas; navegación lateral; horizontal permitido en tablets |
| Formularios estirados a todo el ancho en tablet | Líneas ilegibles | Ancho máximo de 560 dp centrado |
| Solo tocar origen y destino | Poco natural para quien juega en físico | Arrastrar y soltar, con opción en Ajustes |
| Las reglas «oficiales» no se podían consultar | La promesa del producto no se ve | Hoja de reglas por juego y variante, en la partida y en «Nueva partida» |
| Historial sin resumen | Sin sensación de progreso | «Tu balance» por juego |
| Un solo aspecto de tablero | Accesibilidad y gusto | Temas Madera, Fieltro y Alto contraste |
| Inicio sin jerarquía: todo eran tarjetas iguales | No se sabe qué es lo principal | Banda de fieltro con la marca como único elemento llamativo; «Continuar» destacado; juegos en rejilla |

## Funciones: hechas y siguientes

Hechas en esta versión: arrastrar piezas, temas de tablero, hoja de reglas, balance de partidas,
diseño adaptable, piezas e iconos propios.

Siguientes, por valor y esfuerzo:

| Función | Valor | Esfuerzo | Nota |
| --- | --- | --- | --- |
| Revancha online con un toque | Alto | Bajo | Crea una partida con los colores invertidos y avisa al rival |
| Problemas diarios (mate en N, combinaciones de damas) | Alto | Medio | Retención diaria; posiciones en FEN/PDN servidas desde Firestore |
| Lista de amigos por nombre de usuario | Alto | Medio | Retar sin pasar códigos; requiere solicitudes y privacidad |
| Análisis tras la partida | Medio | Medio | Barra de evaluación y «jugada clave» con el mismo motor |
| Tutorial interactivo de reglas | Medio | Medio | Posiciones guiadas por variante |
| Clasificación Elo online | Medio | Alto | Solo tiene sentido con el servidor autoritativo (ya hecho) y anti-trampas |
| Chat con frases predefinidas | Bajo | Bajo | Sin moderación de texto libre |

## Paleta

Concepto: **mesa de club**. Interfaz en blanco mineral (con un punto de verde, no crema), tinta verde
casi negra, fieltro verde como color de marca y latón como acento. La madera queda solo en el tablero.

| Token | Claro | Oscuro | Uso |
| --- | --- | --- | --- |
| bg | `#EEF1EC` | `#0E1513` | Fondo |
| surface | `#FFFFFF` | `#161F1C` | Tarjetas |
| surfaceRaised | `#E2E7E1` | `#1F2925` | Controles, avisos |
| ink | `#16201C` | `#E7EDE9` | Texto |
| inkMuted | `#4F5C56` | `#9FADA6` | Texto secundario |
| lineStrong | `#76837C` | `#677670` | Bordes de control |
| brand / felt | `#17543F` | `#5DBE9A` / `#123F30` | Acción principal, cabecera |
| accent | `#C08A1E` | `#E2B04E` | Selección, último movimiento, jugada actual |
| danger | `#B3261E` | `#F2867D` | Rendirse, jaque, reloj bajo |

Contraste comprobado (WCAG): texto 14,7:1 y 15,6:1; secundario ≥ 5,6:1 en todas las superficies;
bordes de control ≥ 3,5:1; texto sobre `brand` 8,8:1 y 7,6:1. El latón sobre fieltro (4,4:1) se usa
solo en elementos grandes o decorativos.

Temas de tablero: Madera (`#E9D8B4` / `#A0704A`), Fieltro (`#CFE0D6` / `#3E7A62`) y Alto contraste
(`#FFFFFF` / `#4A5A68`), cada uno con su versión oscura.

## Tipografía

Una familia, **Archivo** (variable: peso 100–900, ancho 62–125), usada en dos anchos claramente
distintos, más **JetBrains Mono** para relojes y notación. Ambas OFL, incluidas en la app.

| Estilo | Tamaño/línea | Peso | Ancho | Uso |
| --- | --- | --- | --- | --- |
| display | 34/38 | 800 | 125 (expandida) | Marca, resultados, títulos de pantalla |
| titleLg | 24/30 | 700 | 112 | Nombres de juego, títulos |
| title | 18/24 | 700 | 100 | Tarjetas, secciones |
| body | 16/24 | 400 | 100 | Texto |
| bodySm | 14/20 | 400 | 100 | Secundario |
| label | 15/20 | 600 | 100 | Botones |
| caption | 12,5/16 | 600 | 100 | Etiquetas (sin mayúsculas sostenidas) |
| clock | 26/30 | 500 | — (mono) | Relojes, cifras tabulares |
| notation | 14/20 | 400 | — (mono) | Jugadas |

La versión expandida y pesada evoca los marcadores de torneo; el ancho normal mantiene la interfaz
sobria. Las variaciones se fijan con `fontVariations` (peso y ancho), no solo con `fontWeight`.

## Iconografía: SVG o WebP

| Uso | Formato | Por qué |
| --- | --- | --- |
| Iconos de interfaz (36) | **SVG** | Vectorial a cualquier densidad, 300–700 bytes cada uno, color del tema con `currentColor` |
| Piezas de ajedrez (6) | **SVG** como plantilla | Un archivo por pieza; colores del tema sustituidos al cargar; rasterizado una vez al tamaño exacto del tablero y guardado en caché para Flame |
| Icono del lanzador | **PNG** generado desde SVG | Android pide capas de icono adaptativo; `flutter_launcher_icons` las genera por densidad |
| Icono de Play Store | **PNG** 512×512, 32 bits | Google Play no admite WebP para el icono de la ficha |
| Gráfico destacado | **PNG** 1024×500, sin transparencia | Requisito de Play |
| WebP | No se usa | Solo ahorra peso en bitmaps grandes (fotos, fondos); aquí no hay. Si se añaden ilustraciones de fondo, WebP sin pérdida |

Coste de SVG en tiempo de ejecución: `flutter_svg` analiza cada archivo al usarlo. Con 39 iconos
pequeños es despreciable. Si el perfilado muestra lo contrario, `vector_graphics_compiler` los
precompila a binario sin cambiar el código de los widgets.

Especificación de iconos: rejilla 24, trazo 1,75, extremos y uniones redondeados, sin relleno salvo
semitonos (tablas, tema de tablero). Fuente: `tool/brand/icons.py`.

## Icono de la app

Un **escaque** de latón con el caballo propio en marfil, sobre fieltro verde con un damero apenas visible.

- Icono adaptativo: fondo y primer plano separados; el escaque (50 dp de lado, radio de 9) cabe en el
  círculo seguro de 66 dp; la oreja del caballo sobresale a propósito para reforzar la silueta.
- Monocromo para los iconos temáticos de Android 13+.
- Probado con máscara circular, squircle y redondeada, a 200, 48 y 32 px.
- Fuentes: `assets/icon/*.svg` y `tool/brand/appicon.py`, que regenera todos los PNG.

## Diseño adaptable

| Clase | Ancho | Inicio | Partida | Formularios |
| --- | --- | --- | --- | --- |
| Compacta | < 600 dp | Barra inferior; juegos en 1 columna | Una columna; tablero entre las barras de jugador | Ancho completo |
| Media | 600–839 | Barra inferior; juegos en 2 columnas | Dos columnas si está en horizontal | 560 dp centrado |
| Expandida | ≥ 840 | Navegación lateral | Tablero a la altura completa y panel de 340–400 dp | 560 dp centrado |

Teléfonos: solo vertical. Tablets y plegables abiertos (lado corto ≥ 600 dp): cualquier orientación.
Objetivos táctiles de 48 dp; márgenes de 16 dp en teléfono y 24 dp en tablet.
