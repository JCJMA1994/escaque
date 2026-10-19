"""Genera store/listing.md (ficha de Google Play en español e inglés) y comprueba
los límites de Google: título 30, descripción breve 80, completa 4000.

    python3 tool/store/listing.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'store', 'listing.md')

LISTING = {
    'es': dict(
        lang='Español (es-419 y es-ES)',
        title='Escaque: Ajedrez y Damas',
        short='Ajedrez y damas con reglas oficiales. Contra la IA, con amigos u online.',
        full='''Escaque reúne tres juegos de mesa clásicos con las reglas de sus reglamentos oficiales, sin simplificaciones.

AJEDREZ
• Leyes del Ajedrez de la FIDE: enroque, captura al paso, coronación
• Tablas por ahogado, material insuficiente, repetición y regla de los 50 y 75 movimientos
• Reloj con incremento

DAMAS
• Internacional (10×10, FMJD), inglesa (8×8, WCDF) y española (8×8)
• Captura obligatoria según cada variante, dama larga o corta
• Aviso cuando debes capturar y elección del recorrido cuando hay varios

DAMAS CHINAS
• Tablero de estrella de 121 casillas, de 2 a 6 jugadores

JUEGA COMO QUIERAS
• Contra la IA: cinco niveles, con pistas
• En el mismo teléfono, por turnos
• Online por turnos con un enlace o un código, avisos cuando te toca y revancha con un toque. Cada jugada se valida en nuestro servidor
• Añade amigos por su nombre de usuario y rétalos directamente
• Partidas valoradas con clasificación por juego
• Frases rápidas durante la partida («¡Suerte!», «Bien jugado»…), sin chat libre

APRENDE Y MEJORA
• 19 lecciones interactivas para aprender a mover cada pieza y las reglas clave
• 400 problemas: mates en uno y en dos, y golpes de damas, con problema del día y racha
• Análisis al terminar: gráfica de la partida, errores y la mejor jugada alternativa
• Historial con revisión jugada a jugada y exportación a PGN y PDN
• Logros y clasificaciones de Google Play Juegos

PENSADA PARA TODOS
• Toca o arrastra las piezas
• Tableros de madera, fieltro y alto contraste; modo claro y oscuro
• TalkBack anuncia cada jugada; respeta la opción de quitar animaciones
• Diseño para tablets y plegables, en vertical u horizontal
• En español e inglés

Gratis, con anuncios que nunca aparecen durante una partida, y un pago único opcional para quitarlos. Sin cuenta para jugar contra la IA o en local; la cuenta solo hace falta para jugar online.'''),
    'en': dict(
        lang='English (en-US y en-GB)',
        title='Escaque: Chess & Draughts',
        short='Chess and draughts with official rules. Play the AI, friends or online.',
        full='''Escaque brings together three classic board games with the rules of their official rulebooks, nothing simplified.

CHESS
• FIDE Laws of Chess: castling, en passant, promotion
• Draws by stalemate, insufficient material, repetition and the 50- and 75-move rules
• Clock with increment

DRAUGHTS
• International (10×10, FMJD), English (8×8, WCDF) and Spanish (8×8)
• Mandatory capture as each variant requires, flying or short kings
• A warning when you must capture, and a choice of route when there are several

CHINESE CHECKERS
• 121-hole star board, 2 to 6 players

PLAY YOUR WAY
• Against the AI: five levels, with hints
• On the same phone, taking turns
• Turn-based online play with a link or a code, notifications when it’s your turn and one-tap rematch. Every move is validated on our server
• Add friends by username and challenge them directly
• Rated games with a leaderboard for each game
• Quick phrases during the game (“Good luck!”, “Well played”…), no free chat

LEARN AND IMPROVE
• 19 interactive lessons on how each piece moves and the key rules
• 400 puzzles: mates in one and two, and draughts shots, with a daily puzzle and streak
• Post-game analysis: evaluation chart, mistakes and the best alternative move
• History with move-by-move review and PGN and PDN export
• Google Play Games achievements and leaderboards

BUILT FOR EVERYONE
• Tap or drag the pieces
• Wood, felt and high-contrast boards; light and dark mode
• TalkBack reads every move aloud; follows the system setting to remove animations
• Designed for tablets and foldables, in portrait or landscape
• In Spanish and English

Free, with ads that never appear during a game, and an optional one-time payment to remove them. No account needed to play the AI or locally; you only need one to play online.'''),
}

out = ['# Ficha de Google Play', '',
       'Textos para Play Console → Crecer → Ficha de Play Store. Añade cada idioma en «Gestionar traducciones».',
       'Límites de Google: título 30, descripción breve 80, descripción completa 4000 caracteres.',
       'Se genera con `tool/store/listing.py` (que comprueba los límites): edita allí, no aquí.', '']
for v in LISTING.values():
    lim = [(len(v['title']), 30), (len(v['short']), 80), (len(v['full']), 4000)]
    assert all(a <= b for a, b in lim), (v['lang'], lim)
    out += [f"## {v['lang']}", '', '| Campo | Caracteres |', '| --- | --- |',
            f'| Título | {lim[0][0]} / 30 |', f'| Descripción breve | {lim[1][0]} / 80 |',
            f'| Descripción completa | {lim[2][0]} / 4000 |', '',
            '**Título**', '', '```', v['title'], '```', '', '**Descripción breve**', '', '```', v['short'], '```', '',
            '**Descripción completa**', '', '```', v['full'], '```', '']
out += ['## Recursos gráficos', '',
        '| Recurso | Archivo | Idiomas |', '| --- | --- | --- |',
        '| Icono 512×512 | `play_icon_512.png` | Común |',
        '| Gráfico destacado 1024×500 | `feature_graphic_1024x500.png` y `feature_graphic_en_1024x500.png` | Uno por idioma (`tool/brand/appicon.py` genera los dos) |',
        '| Capturas de teléfono y tablet | Workflow `screenshots.yml` (8 pantallas por dispositivo e idioma, como artefactos) | Una serie por idioma |', '']
open(OUT, 'w').write('\n'.join(out))
for k, v in LISTING.items():
    print(k, len(v['title']), len(v['short']), len(v['full']))
