import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/theme.dart';
import '../match/match_config.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

typedef RulesSection = (String title, List<String> points);

/// Reglas del juego y la variante de la partida, en una hoja inferior.
Future<void> showRulesSheet(BuildContext context, MatchConfig config) {
  final c = TableroColors.of(context);
  final (title, source, sections) = rulesFor(config);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: c.surface,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: pagePadding(context, bottom: 32),
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: TType.titleLg(c.ink))),
              TextButton(
                  onPressed: () {
                    // El router se toma antes de cerrar la hoja: después su contexto ya no vale.
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push('/learn?kind=${config.kind.name}');
                  },
                  child: Text(tr('Practicar')),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(source, style: TType.bodySm(c.inkMuted)),
          for (final (heading, points) in sections) ...[
            const SizedBox(height: 20),
            Text(tr(heading), style: TType.title(c.ink)),
            const SizedBox(height: 8),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 10),
                      child: Container(width: 5, height: 5, decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text(tr(p), style: TType.body(c.ink))),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

(String, String, List<RulesSection>) rulesFor(MatchConfig config) => switch (config.kind) {
      GameKind.chess => (tr('Ajedrez'), tr('Según las Leyes del Ajedrez de la FIDE.'), _chess),
      GameKind.chineseCheckers => (tr('Damas chinas'), tr('Reglamento estándar (no existe federación oficial).'), _chinese),
      GameKind.draughts => switch (config.draughtsVariant.id) {
          'international' => (tr('Damas internacionales'), tr('Según el reglamento de la FMJD.'), _international),
          'english' => (tr('Damas inglesas'), tr('Según el reglamento de la WCDF.'), _english),
          _ => (tr('Damas españolas'), tr('Reglas de la variante española.'), _spanish),
        },
    };

const List<RulesSection> _chess = [
  ('Objetivo', ['Dar jaque mate: atacar al rey rival de forma que no pueda evitar la captura.']),
  ('Movimientos especiales', [
    'Enroque: el rey se mueve dos casillas hacia una torre y la torre salta a su lado. Ni el rey ni esa torre se han movido, no hay piezas entre ellos, el rey no está en jaque y no pasa ni cae en una casilla atacada.',
    'Captura al paso: si un peón avanza dos casillas y queda junto a un peón rival, este puede capturarlo como si hubiera avanzado una. Solo en la jugada siguiente.',
    'Coronación: el peón que llega a la última fila se cambia por dama, torre, alfil o caballo, a elección.',
  ]),
  ('Tablas', [
    'Rey ahogado: el jugador en turno no está en jaque y no tiene jugadas legales.',
    'Material insuficiente: ninguna serie de jugadas puede acabar en mate (por ejemplo, rey contra rey y alfil).',
    'Se pueden reclamar con triple repetición de la posición o con 50 jugadas de cada bando sin capturas ni movimientos de peón.',
    'Son automáticas con quíntuple repetición o con 75 jugadas sin capturas ni movimientos de peón.',
    'Por acuerdo entre los jugadores.',
  ]),
  ('Reloj', ['Si se te acaba el tiempo pierdes, salvo que tu rival no pueda dar mate con ninguna serie de jugadas legales: entonces son tablas.']),
];

const List<RulesSection> _international = [
  ('Tablero y salida', ['10×10, 20 piezas por bando en las casillas oscuras. Empiezan las blancas.']),
  ('Movimientos', [
    'El peón avanza una casilla en diagonal hacia delante.',
    'La dama es larga: recorre cualquier número de casillas libres en diagonal.',
  ]),
  ('Capturas', [
    'Capturar es obligatorio, y hay que elegir la secuencia que toma más piezas.',
    'El peón captura hacia delante y hacia atrás.',
    'Las piezas capturadas se retiran al terminar la secuencia y no se pueden saltar dos veces.',
    'Un peón que pasa por la última fila durante una captura y no termina en ella no corona.',
  ]),
  ('Final', [
    'Pierde quien no puede mover (sin piezas o bloqueado).',
    'Tablas por triple repetición o por 25 jugadas de cada bando solo con damas, sin capturas ni movimientos de peón.',
  ]),
];

const List<RulesSection> _english = [
  ('Tablero y salida', ['8×8, 12 piezas por bando. Empiezan las negras.']),
  ('Movimientos', [
    'El peón avanza una casilla en diagonal hacia delante.',
    'La dama es corta: una casilla en diagonal, hacia delante o hacia atrás.',
  ]),
  ('Capturas', [
    'Capturar es obligatorio, pero puedes elegir cualquier secuencia, aunque tome menos piezas.',
    'El peón solo captura hacia delante.',
    'Un peón que corona capturando termina ahí su turno.',
  ]),
  ('Final', [
    'Pierde quien no puede mover.',
    'Tablas por triple repetición o por 40 jugadas de cada bando sin capturas ni movimientos de peón.',
  ]),
];

const List<RulesSection> _spanish = [
  ('Tablero y salida', ['8×8, 12 piezas por bando. Empiezan las blancas.']),
  ('Movimientos', [
    'El peón avanza una casilla en diagonal hacia delante.',
    'La dama es larga: recorre cualquier número de casillas libres en diagonal.',
  ]),
  ('Capturas', [
    'Capturar es obligatorio, y hay que tomar el máximo de piezas.',
    'Si dos secuencias toman las mismas piezas, es obligatoria la que captura más damas.',
    'El peón solo captura hacia delante.',
  ]),
  ('Final', ['Pierde quien no puede mover.', 'Tablas por triple repetición de la posición.']),
];

const List<RulesSection> _chinese = [
  ('Tablero y salida', ['Estrella de 121 casillas. Cada jugador empieza con 10 fichas en una punta. Se juega a 2, 3, 4 o 6.']),
  ('Movimientos', [
    'Mover a una casilla vecina libre.',
    'O saltar sobre una ficha vecina (tuya o ajena) a la casilla libre justo detrás, y encadenar saltos en el mismo turno.',
    'No hay capturas.',
  ]),
  ('Final', [
    'Gana quien llena primero la punta opuesta.',
    'Si un rival deja fichas en tu meta, cuenta como llena cuando no quedan huecos y al menos una ficha es tuya.',
    'Quien no tiene ninguna jugada pasa el turno.',
  ]),
];

/// Resumen de una línea para «Nueva partida».
String variantSummary(DraughtsVariant v) => switch (v.id) {
      'international' => tr('10×10 · dama larga · captura obligatoria de más piezas; el peón captura hacia atrás.'),
      'english' => tr('8×8 · dama corta · captura obligatoria; eliges la secuencia. Empiezan las negras.'),
      _ => tr('8×8 · dama larga · captura obligatoria de más piezas; con empate, la que capture más damas.'),
    };
