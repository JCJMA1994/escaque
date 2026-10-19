import 'package:tablero_engine/tablero_engine.dart';

import '../board_view.dart';
import '../match_config.dart';
import 'chess_adapter.dart';
import 'chinese_checkers_adapter.dart';
import 'draughts_adapter.dart';

/// Une cada motor con la interfaz: casillas en lugar de tipos de jugada.
/// Cada adaptador guarda su propio historial para deshacer.
abstract class MatchAdapter {
  int get playerCount;
  int get toMove;
  GameResult? get result;
  BoardSnapshot snapshot();

  /// Casillas con una pieza del jugador en turno que puede mover.
  Set<int> movableCells();

  /// Destinos legales desde [cell].
  List<int> targetsFrom(int cell);

  /// ¿La jugada de [from] a [to] necesita elegir pieza de coronación?
  bool needsPromotionChoice(int from, int to) => false;

  /// Recorridos distintos de [from] a [to] (damas: dos capturas que acaban en
  /// la misma casilla). Con 0 o 1 no hay nada que elegir.
  List<String> routesFor(int from, int to) => const [];

  /// Aplica la jugada de la persona. Devuelve `false` si es ilegal.
  /// [route] elige entre [routesFor] cuando hay varios.
  bool play(int from, int to, {int? promotion, int? route});

  /// Calcula y aplica la jugada de la IA para el jugador en turno.
  Future<void> playAi(int level);

  bool get canUndo;
  void undo();

  /// Notación de las jugadas hechas.
  List<String> get moveLog;

  /// Jugadas en un formato que [replay] puede volver a aplicar (para guardar
  /// y retomar partidas).
  List<String> get moveCodes;

  /// Aplica una jugada guardada con [moveCodes]. `false` si no es legal.
  bool replay(String code);

  /// Última jugada en lenguaje natural, con quién la hizo (para TalkBack).
  String? get lastMoveSpoken => null;

  /// Hay una captura obligatoria (damas).
  bool get mustCapture => false;

  /// Resultado si al jugador [player] se le acaba el tiempo.
  GameResult timeout(int player) => GameResult.win(1 - player, 'tiempo agotado');

  /// Jugada sugerida para el jugador en turno: (origen, destino).
  Future<(int, int)?> hint() async => null;

  /// Tablas reclamables ahora mismo (solo ajedrez).
  String? claimableDraw() => null;

  static MatchAdapter create(MatchConfig config) => switch (config.kind) {
        GameKind.chess => ChessAdapter(),
        GameKind.draughts => DraughtsAdapter(config.draughtsVariant),
        GameKind.chineseCheckers => ChineseCheckersAdapter(config.players),
      };
}
