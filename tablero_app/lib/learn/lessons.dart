// Posiciones y jugadas verificadas con los prototipos del motor (las mismas
// reglas que tablero_engine). Los textos están en español: se traducen al
// mostrarlos con tr().
import 'package:tablero_engine/tablero_engine.dart';

import '../match/match_config.dart';

/// Una lección: una posición, la instrucción, las jugadas que cumplen el
/// objetivo y el texto de acierto.
class Lesson {
  final String id;
  final GameKind kind;
  final String title;
  final String text;
  final String done;
  /// Ajedrez: FEN. Damas: tablero, bando y variante.
  final String fen;
  final List<int> board;
  final int side;
  final DraughtsVariant? variant;
  /// Jugadas aceptadas: UCI en ajedrez, recorrido «a-b-c» en damas.
  final List<String> accept;

  /// Damas chinas (dos jugadores): piezas como (coordenada hexagonal, jugador)
  /// y jugadas aceptadas como (origen, destino). Se convierten a índices del
  /// tablero al usarlas, así no dependen de la numeración interna.
  final List<((int, int, int), int)> ccPieces;
  final List<((int, int, int), (int, int, int))> ccAccept;

  /// Jugadas «trampa» con su explicación (p. ej. la que ahoga en vez de dar mate).
  final Map<String, String> traps;

  const Lesson(
      {required this.id,
      required this.kind,
      required this.title,
      required this.text,
      required this.done,
      this.accept = const [],
      this.fen = '',
      this.board = const [],
      this.side = 1,
      this.variant,
      this.ccPieces = const [],
      this.ccAccept = const [],
      this.traps = const {}});

  static int _cell((int, int, int) h) {
    final i = StarBoard.instance.indexOf(Hex(h.$1, h.$2, h.$3));
    if (i == null) throw StateError('Casilla fuera del tablero: $h');
    return i;
  }

  /// Jugadas aceptadas con el formato de `moveCodes` del adaptador.
  List<String> get acceptCodes => kind == GameKind.chineseCheckers
      ? [for (final (a, b) in ccAccept) '${_cell(a)}-${_cell(b)}']
      : accept;

  /// Posición de damas chinas de la lección (a dos jugadores, juegan las naranjas).
  CCState ccState() {
    final occ = List<int>.filled(StarBoard.instance.cells.length, -1);
    for (final (h, player) in ccPieces) {
      occ[_cell(h)] = player;
    }
    return CCState(occupant: occ, seats: ChineseCheckersRules.seatsByPlayers[2]!, toMove: 0, ply: 0);
  }
}

const lessons = <Lesson>[
  Lesson(id: 'chess-rook', kind: GameKind.chess, title: 'La torre', fen: '7k/8/8/8/8/8/8/R5K1 w - - 0 1', accept: ['a1a8'],
      text: 'La torre se mueve en línea recta, en horizontal o en vertical, tantas casillas libres como quiera. Llévala a a8 para dar jaque al rey.',
      done: 'Eso es: la torre recorre toda la columna de un solo movimiento.'),
  Lesson(id: 'chess-bishop', kind: GameKind.chess, title: 'El alfil', fen: '7k/8/8/8/5p2/8/8/2B3K1 w - - 0 1', accept: ['c1f4'],
      text: 'El alfil se mueve en diagonal, tantas casillas libres como quiera, y captura ocupando la casilla de la pieza rival. Captura el peón de f4.',
      done: 'Bien: el alfil siempre se queda en casillas del mismo color.'),
  Lesson(id: 'chess-knight', kind: GameKind.chess, title: 'El caballo', fen: '7k/8/8/8/8/2p5/PPP5/1N4K1 w - - 0 1', accept: ['b1c3'],
      text: 'El caballo se mueve en forma de L (dos casillas en una dirección y una en la otra) y es la única pieza que salta por encima de las demás. Captura el peón de c3.',
      done: 'Exacto: el caballo saltó por encima de tus peones.'),
  Lesson(id: 'chess-queen', kind: GameKind.chess, title: 'La dama', fen: '6k1/5ppp/8/8/8/8/8/3Q2K1 w - - 0 1', accept: ['d1d8'],
      text: 'La dama combina la torre y el alfil: se mueve en línea recta o en diagonal, tantas casillas como quiera. Da jaque mate al rey, encerrado por sus propios peones.',
      done: '¡Jaque mate! El rey no tiene ninguna casilla a la que escapar.'),
  Lesson(id: 'chess-promotion', kind: GameKind.chess, title: 'Coronar', fen: '7k/4P3/8/8/8/8/8/4K3 w - - 0 1', accept: ['e7e8q', 'e7e8r', 'e7e8b', 'e7e8n'],
      text: 'El peón avanza una casilla hacia delante (dos en su primera jugada) y captura en diagonal. Si llega a la última fila, se convierte en otra pieza. Avanza el peón a e8.',
      done: 'Coronado: casi siempre conviene elegir una dama.'),
  Lesson(id: 'chess-castling', kind: GameKind.chess, title: 'El enroque', fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1', accept: ['e1g1'],
      text: 'En el enroque el rey se mueve dos casillas hacia una torre y la torre salta a su otro lado. Solo se puede si ninguno de los dos se ha movido y el rey no está en jaque ni pasa por casillas atacadas. Enroca corto: mueve el rey a g1.',
      done: 'Enroque corto hecho: tu rey está más protegido y la torre entra en juego.'),
  Lesson(id: 'chess-enpassant', kind: GameKind.chess, title: 'Captura al paso', fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', accept: ['e5d6'],
      text: 'El peón negro acaba de avanzar dos casillas, de d7 a d5, y ha quedado junto al tuyo. Puedes capturarlo como si hubiera avanzado una sola: mueve tu peón de e5 a d6.',
      done: 'Captura al paso: solo se puede justo en la jugada siguiente.'),
  Lesson(id: 'chess-check', kind: GameKind.chess, title: 'Salir del jaque', fen: '4r1k1/8/8/8/8/8/8/4K3 w - - 0 1', accept: ['e1d1', 'e1f1', 'e1d2', 'e1f2'],
      text: 'Tu rey está en jaque: la torre de e8 lo ataca. Estar en jaque obliga a salir de él en la jugada siguiente. Mueve el rey fuera de la columna e.',
      done: 'A salvo. Si no hubieras podido salir del jaque, sería jaque mate.'),
  Lesson(id: 'chess-mate', kind: GameKind.chess, title: 'Jaque mate', fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1', accept: ['a1a8'],
      text: 'La partida se gana dando jaque mate: el rey rival está en jaque y no puede evitarlo. Busca el mate en una jugada.',
      done: '¡Jaque mate! Es el «mate del pasillo»: el rey queda atrapado por sus peones.'),
  Lesson(id: 'chess-stalemate', kind: GameKind.chess, title: 'Cuidado con el ahogado', fen: '7k/4Q3/6K1/8/8/8/8/8 w - - 0 1',
      accept: ['e7f8', 'e7d8', 'e7g7', 'e7h7', 'e7e8'],
      traps: {
        'e7f7': '¡Ahogado! El rey negro no está en jaque pero no tiene ninguna jugada: la partida acaba en tablas. Busca un jaque mate.',
        'e7e6': '¡Ahogado! El rey negro no está en jaque pero no tiene ninguna jugada: la partida acaba en tablas. Busca un jaque mate.',
      },
      text: 'Si el rival no está en jaque y no tiene ninguna jugada legal, es ahogado: tablas, aunque tengas mucha ventaja. Aquí casi todo gana, pero dos jugadas de la dama ahogan. Da jaque mate.',
      done: '¡Jaque mate! Con ventaja, asegúrate siempre de que el rival tenga alguna jugada o esté en jaque.'),
  Lesson(id: 'draughts-move', kind: GameKind.draughts, title: 'Mover un peón', variant: DraughtsVariant.spanish, side: 1,
      board: [0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      accept: ['42-33', '42-35'],
      text: 'En damas, los peones avanzan una casilla en diagonal hacia delante, siempre por las casillas oscuras. Mueve el peón blanco.',
      done: 'Bien. Los peones nunca retroceden al moverse.'),
  Lesson(id: 'draughts-capture', kind: GameKind.draughts, title: 'La captura es obligatoria', variant: DraughtsVariant.spanish, side: 1,
      board: [0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      accept: ['42-28'],
      text: 'Si puedes capturar, debes hacerlo: se salta sobre la pieza rival a la casilla libre de detrás. Captura el peón negro.',
      done: 'Captura hecha. Si no capturas cuando puedes, la jugada no es legal.'),
  Lesson(id: 'draughts-multi', kind: GameKind.draughts, title: 'Capturas en cadena', variant: DraughtsVariant.spanish, side: 1,
      board: [0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      accept: ['49-35-21'],
      text: 'Si después de capturar puedes volver a capturar, la captura sigue en la misma jugada. Captura los dos peones negros.',
      done: '¡Doble captura! Las piezas capturadas se retiran al terminar.'),
  Lesson(id: 'draughts-crown', kind: GameKind.draughts, title: 'Coronar', variant: DraughtsVariant.spanish, side: 1,
      board: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0],
      accept: ['10-1', '10-3'],
      text: 'Un peón que llega a la última fila se convierte en dama. Lleva tu peón a la fila del fondo.',
      done: 'Coronado: ahora es una dama.'),
  Lesson(id: 'draughts-king', kind: GameKind.draughts, title: 'La dama larga', variant: DraughtsVariant.spanish, side: 1,
      board: [0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0],
      accept: ['56-35', '56-28', '56-21', '56-14'],
      text: 'En las damas españolas e internacionales, la dama recorre cualquier número de casillas libres en diagonal. Muévela al menos tres casillas.',
      done: 'Eso es: en las damas inglesas, en cambio, la dama solo avanza una casilla.'),
  Lesson(id: 'draughts-majority', kind: GameKind.draughts, title: 'La ley de la mayoría', variant: DraughtsVariant.international, side: 1,
      board: [0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      accept: ['63-45-27'],
      text: 'En las damas internacionales hay que elegir la captura que toma más piezas. Aquí puedes tomar dos: encuentra la secuencia.',
      done: 'Correcto: una captura más corta no habría sido legal.'),
  Lesson(id: 'cc-step', kind: GameKind.chineseCheckers, title: 'Mover a un hueco',
      ccPieces: [((0, 0, 0), 0), ((-8, 4, 4), 1)],
      ccAccept: [((0, 0, 0), (1, -1, 0)), ((0, 0, 0), (1, 0, -1)), ((0, 0, 0), (0, 1, -1)), ((0, 0, 0), (-1, 1, 0)), ((0, 0, 0), (-1, 0, 1)), ((0, 0, 0), (0, -1, 1))],
      text: 'En damas chinas cada ficha se mueve a uno de los seis huecos vecinos, en cualquier dirección. Mueve tu ficha naranja.',
      done: 'Bien. El objetivo es llevar todas tus fichas a la punta de enfrente antes que el rival.'),
  Lesson(id: 'cc-jump', kind: GameKind.chineseCheckers, title: 'Saltar',
      ccPieces: [((0, 0, 0), 0), ((1, -1, 0), 1), ((-8, 4, 4), 1)],
      ccAccept: [((0, 0, 0), (2, -2, 0))],
      text: 'Puedes saltar por encima de una ficha vecina, tuya o del rival, al hueco libre de detrás. Nada se captura. Salta sobre la ficha azul.',
      done: 'Eso es: un salto avanza el doble que un paso.'),
  Lesson(id: 'cc-chain', kind: GameKind.chineseCheckers, title: 'Saltos en cadena',
      ccPieces: [((0, 0, 0), 0), ((1, -1, 0), 1), ((3, -3, 0), 1), ((-8, 4, 4), 1)],
      ccAccept: [((0, 0, 0), (4, -4, 0))],
      text: 'Tras un salto puedes seguir saltando en la misma jugada, tantas veces como puedas. Llega lo más lejos posible con dos saltos seguidos.',
      done: '¡Doble salto! Encadenar saltos es la clave para ganar en damas chinas.'),
];
