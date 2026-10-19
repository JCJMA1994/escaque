import 'dart:isolate';

import 'package:tablero_engine/tablero_engine.dart';

import '../board_view.dart';
import '../spoken.dart';
import 'match_adapter.dart';
import '../../l10n/l10n.dart';

class DraughtsAdapter extends MatchAdapter {
  final DraughtsRules _rules;
  late DraughtsState _state;
  final _history = <DraughtsState>[];
  final _moves = <DraughtsMove>[];
  final _log = <String>[];
  List<DraughtsMove>? _legalCache;

  /// [initial]: una posición concreta (tests, problemas); por defecto, la de salida.
  DraughtsAdapter(DraughtsVariant variant, {DraughtsState? initial}) : _rules = DraughtsRules(variant) {
    _state = initial ?? _rules.initialState();
  }

  DraughtsState get state => _state;

  List<DraughtsMove> get _legal => _legalCache ??= _rules.legalMoves(_state);

  @override
  int get playerCount => 2;

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result => _rules.result(_state);

  @override
  bool get mustCapture => _legal.isNotEmpty && _legal.first.isCapture;

  @override
  Set<int> movableCells() => _legal.map((m) => m.from).toSet();

  @override
  List<int> targetsFrom(int cell) =>
      _legal.where((m) => m.from == cell).map((m) => m.to).toSet().toList();

  List<DraughtsMove> _between(int from, int to) =>
      [for (final m in _legal) if (m.from == from && m.to == to) m];

  @override
  List<String> routesFor(int from, int to) {
    final options = _between(from, to);
    if (options.length < 2) return const [];
    return [
      for (final m in options)
        // «Por 23 y 14 · captura 3»: casillas intermedias en numeración PDN.
        '${m.path.length > 2 ? 'Por ${m.path.sublist(1, m.path.length - 1).map(_rules.squareNumber).join(' y ')} · ' : ''}'
            'captura ${m.captured.length}'
    ];
  }

  @override
  bool play(int from, int to, {int? promotion, int? route}) {
    final options = _between(from, to);
    if (options.isEmpty) return false;
    final i = route ?? 0;
    if (i < 0 || i >= options.length) return false;
    _apply(options[i]);
    return true;
  }

  void _apply(DraughtsMove m) {
    _log.add(_rules.notation(m));
    _history.add(_state);
    _moves.add(m);
    _state = _rules.applyUnchecked(_state, m);
    _legalCache = null;
  }

  @override
  Future<void> playAi(int level) async {
    final s = _state;
    final rules = _rules;
    final m = await Isolate.run(() => draughtsAi(rules, level).bestMove(s));
    if (m != null && identical(s, _state)) _apply(m);
  }

  @override
  Future<(int, int)?> hint() async {
    final s = _state;
    final rules = _rules;
    final m = await Isolate.run(() => AlphaBeta<DraughtsState, DraughtsMove>(
          rules: rules,
          evaluate: draughtsEvaluator,
          depth: 10,
          timeLimit: const Duration(milliseconds: 1500),
          fastApply: rules.applyUnchecked,
          terminal: rules.resultWith,
          hash: (s) => s.hash,
          noisyMoves: draughtsNoisyMoves,
        ).bestMove(s));
    return m == null || !identical(s, _state) ? null : (m.from, m.to);
  }

  @override
  bool get canUndo => _history.isNotEmpty;

  @override
  void undo() {
    if (!canUndo) return;
    _state = _history.removeLast();
    _moves.removeLast();
    _log.removeLast();
    _legalCache = null;
  }

  @override
  List<String> get moveLog => List.unmodifiable(_log);

  @override
  String? get lastMoveSpoken {
    if (_moves.isEmpty) return null;
    final who = _history.last.side == 1 ? tr('Blancas') : tr('Negras');
    return '$who: ${Spoken.draughts(_log.last, _moves.last.captured.length)}';
  }

  @override
  List<String> get moveCodes => [for (final m in _moves) m.path.join('-')];

  @override
  bool replay(String code) {
    for (final m in _legal) {
      if (m.path.join('-') == code) {
        _apply(m);
        return true;
      }
    }
    return false;
  }

  @override
  BoardSnapshot snapshot() {
    final b = _state.board;
    return BoardSnapshot(
      shape: BoardShape.draughtsGrid,
      size: _rules.variant.size,
      version: _moves.length,
      pieces: [
        for (var s = 0; s < b.length; s++)
          if (b[s] != 0)
            PieceView(
              cell: s,
              owner: b[s] > 0 ? 0 : 1,
              style: PieceStyle.disc,
              glyph: b[s].abs() == 2 ? 'crown' : null,
            ),
      ],
      lastPath: _moves.isEmpty ? const [] : _moves.last.path,
      lastCaptured: _moves.isEmpty ? const [] : _moves.last.captured,
    );
  }
}
