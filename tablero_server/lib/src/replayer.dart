import 'package:tablero_engine/tablero_engine.dart';

/// Reconstruye una partida jugada a jugada con el motor y valida la siguiente.
/// Los códigos son los mismos que usa la app: UCI en ajedrez y el recorrido
/// `origen-salto-destino` en damas.
abstract class Replayer {
  int get toMove;
  GameResult? get result;

  /// Aplica [code] si es legal en la posición actual y la partida sigue.
  bool apply(String code);

  /// Resultado si al jugador [player] se le acaba el tiempo.
  GameResult timeout(int player);

  static const kinds = {'chess', 'draughts', 'chineseCheckers'};

  static bool validVariant(String id) => DraughtsVariant.all.any((v) => v.id == id);

  factory Replayer.create(String kind, String variant) => switch (kind) {
        'chess' => _ChessReplayer(),
        'draughts' => _DraughtsReplayer(DraughtsVariant.all.firstWhere((v) => v.id == variant)),
        'chineseCheckers' => _ChineseCheckersReplayer(),
        _ => throw ArgumentError('Juego no admitido online: $kind'),
      };
}

class _ChessReplayer implements Replayer {
  static const _rules = ChessRules();
  ChessState _state = _rules.initialState();

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result => _rules.result(_state);

  @override
  bool apply(String code) {
    if (result != null) return false;
    final m = ChessEngine.fromUci(_state.position, code);
    if (m == null) return false;
    _state = _rules.applyUnchecked(_state, m);
    return true;
  }

  @override
  GameResult timeout(int player) => _rules.onTimeout(_state, player);
}

class _DraughtsReplayer implements Replayer {
  final DraughtsRules _rules;
  late DraughtsState _state;

  _DraughtsReplayer(DraughtsVariant v) : _rules = DraughtsRules(v) {
    _state = _rules.initialState();
  }

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result => _rules.result(_state);

  @override
  bool apply(String code) {
    if (result != null) return false;
    for (final m in _rules.legalMoves(_state)) {
      if (m.path.join('-') == code) {
        _state = _rules.applyUnchecked(_state, m);
        return true;
      }
    }
    return false;
  }

  @override
  GameResult timeout(int player) => GameResult.win(1 - player, 'tiempo agotado');
}

/// Damas chinas online a dos jugadores. Código de jugada: `origen-destino`.
/// Igual que la app, un jugador sin jugadas posibles pasa automáticamente.
class _ChineseCheckersReplayer implements Replayer {
  final _rules = ChineseCheckersRules(players: 2);
  late CCState _state = _rules.initialState();

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result => _rules.result(_state);

  @override
  bool apply(String code) {
    if (result != null) return false;
    final parts = code.split('-');
    if (parts.length != 2) return false;
    final from = int.tryParse(parts[0]), to = int.tryParse(parts[1]);
    if (from == null || to == null || from < 0 || from >= _state.occupant.length) return false;
    if (_state.occupant[from] != _state.toMove) return false;
    for (final m in _rules.movesFrom(_state, from)) {
      if (m.to == to) {
        _state = _rules.applyUnchecked(_state, m);
        _skipBlocked();
        return true;
      }
    }
    return false;
  }

  void _skipBlocked() {
    for (var i = 0; i < _state.playerCount && result == null; i++) {
      final real = _rules.legalMoves(_state).where((m) => !m.isPass);
      if (real.isNotEmpty) return;
      _state = _rules.applyUnchecked(_state, CCMove.pass());
    }
  }

  @override
  GameResult timeout(int player) => GameResult.win(1 - player, 'tiempo agotado');
}
