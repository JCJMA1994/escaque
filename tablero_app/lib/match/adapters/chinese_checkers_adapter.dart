import 'dart:isolate';

import 'package:tablero_engine/tablero_engine.dart';

import '../board_view.dart';
import 'match_adapter.dart';
import '../../l10n/l10n.dart';

class ChineseCheckersAdapter extends MatchAdapter {
  final ChineseCheckersRules _rules;
  late CCState _state;
  final _history = <CCState>[];
  final _moves = <CCMove>[];
  final _log = <String>[];

  /// [initial]: otra posición de partida (lecciones).
  ChineseCheckersAdapter(int players, {CCState? initial})
      : _rules = ChineseCheckersRules(players: players) {
    _state = initial ?? _rules.initialState();
  }

  CCState get state => _state;

  @override
  int get playerCount => _state.playerCount;

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result => _rules.result(_state);

  List<CCMove> get _legal =>
      _rules.legalMoves(_state).where((m) => !m.isPass).toList();

  @override
  Set<int> movableCells() => _legal.map((m) => m.from).toSet();

  @override
  List<int> targetsFrom(int cell) =>
      _rules.movesFrom(_state, cell).map((m) => m.to).toList();

  @override
  bool play(int from, int to, {int? promotion, int? route}) {
    if (_state.occupant[from] != _state.toMove) return false;
    for (final m in _rules.movesFrom(_state, from)) {
      if (m.to == to) {
        _apply(m);
        return true;
      }
    }
    return false;
  }

  void _apply(CCMove m) {
    _history.add(_state);
    _moves.add(m);
    _log.add('${m.from}→${m.to}');
    _state = _rules.applyUnchecked(_state, m);
    _skipBlockedPlayers();
  }

  /// Un jugador sin ninguna jugada posible pasa el turno automáticamente.
  void _skipBlockedPlayers() {
    for (var i = 0; i < _state.playerCount && result == null; i++) {
      if (_legal.isNotEmpty) return;
      _state = _rules.applyUnchecked(_state, CCMove.pass());
    }
  }

  /// IA según el nivel (motor: chineseCheckersMove). A dos jugadores y en
  /// niveles altos busca con alfa-beta, así que se calcula en otro hilo.
  @override
  Future<void> playAi(int level) async {
    final s = _state, rules = _rules;
    final started = DateTime.now();
    final m = await Isolate.run(() => chineseCheckersMove(rules, s, level));
    final wait = const Duration(milliseconds: 350) - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait); // que no parezca instantánea
    if (!identical(s, _state)) return; // se deshizo mientras pensaba
    _apply(m);
  }

  @override
  Future<(int, int)?> hint() async {
    final m = _rules.greedyMove(_state);
    return m.isPass ? null : (m.from, m.to);
  }

  @override
  bool get canUndo => _history.isNotEmpty;

  @override
  void undo() {
    if (!canUndo) return;
    _state = _history.removeLast();
    _moves.removeLast();
    _log.removeLast();
  }

  @override
  List<String> get moveLog => List.unmodifiable(_log);

  static const _colorNames = ['naranja', 'azul', 'verde', 'amarillo', 'negro', 'blanco'];

  @override
  String? get lastMoveSpoken {
    if (_moves.isEmpty) return null;
    final m = _moves.last;
    final who = tr('Jugador {p0}', {'p0': tr(_colorNames[_history.last.toMove % _colorNames.length])});
    return m.isJump ? tr('{who}: salto de {p1} casillas', {'who': who, 'p1': m.path.length - 1}) : tr('{who}: avanza una casilla', {'who': who});
  }

  @override
  List<String> get moveCodes => [for (final m in _moves) '${m.from}-${m.to}'];

  @override
  bool replay(String code) {
    final parts = code.split('-');
    if (parts.length != 2) return false;
    final from = int.tryParse(parts[0]), to = int.tryParse(parts[1]);
    if (from == null || to == null) return false;
    return play(from, to);
  }

  @override
  BoardSnapshot snapshot() => BoardSnapshot(
        shape: BoardShape.star,
        size: 0,
        version: _moves.length,
        pieces: [
          for (var i = 0; i < _state.occupant.length; i++)
            if (_state.occupant[i] >= 0)
              PieceView(cell: i, owner: _state.occupant[i], style: PieceStyle.stone),
        ],
        lastPath: _moves.isEmpty ? const [] : _moves.last.path,
      );
}
