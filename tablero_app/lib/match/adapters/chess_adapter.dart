import 'dart:isolate';

import 'package:tablero_engine/tablero_engine.dart';

import '../board_view.dart';
import '../spoken.dart';
import 'match_adapter.dart';
import '../../l10n/l10n.dart';

class ChessAdapter extends MatchAdapter {
  static const _rules = ChessRules();
  /// Nombre de la pieza propia (assets/pieces) por tipo del motor (1 = peón … 6 = rey).
  static const _kinds = ['', 'pawn', 'knight', 'bishop', 'rook', 'queen', 'king'];

  ChessState _state;
  final _history = <ChessState>[];

  /// [fen]: posición de partida (problemas); por defecto, la inicial.
  ChessAdapter({String? fen}) : _state = fen == null ? _rules.initialState() : _rules.fromFen(fen);
  final _moves = <ChessMove>[];
  final _sans = <String>[];
  GameResult? _cachedResult;
  bool _resultComputed = false;

  ChessState get state => _state;

  @override
  int get playerCount => 2;

  @override
  int get toMove => _state.toMove;

  @override
  GameResult? get result {
    if (!_resultComputed) {
      _cachedResult = _rules.result(_state);
      _resultComputed = true;
    }
    return _cachedResult;
  }

  List<ChessMove> get _legal => _rules.legalMoves(_state);

  @override
  Set<int> movableCells() => _legal.map((m) => m.from).toSet();

  @override
  List<int> targetsFrom(int cell) =>
      _legal.where((m) => m.from == cell).map((m) => m.to).toSet().toList();

  @override
  bool needsPromotionChoice(int from, int to) =>
      _legal.any((m) => m.from == from && m.to == to && m.promotion != 0);

  @override
  bool play(int from, int to, {int? promotion, int? route}) {
    final wanted = needsPromotionChoice(from, to) ? (promotion ?? Piece.queen) : 0;
    for (final m in _legal) {
      if (m.from == from && m.to == to && m.promotion == wanted) {
        _apply(m);
        return true;
      }
    }
    return false;
  }

  void _apply(ChessMove m) {
    _sans.add(ChessEngine.toSan(_state.position, m));
    _history.add(_state);
    _moves.add(m);
    _state = _rules.applyUnchecked(_state, m);
    _resultComputed = false;
  }

  @override
  Future<void> playAi(int level) async {
    final s = _state;
    final m = await Isolate.run(() => chessAi(level).bestMove(s));
    if (m != null && identical(s, _state)) _apply(m);
  }

  @override
  Future<(int, int)?> hint() async {
    final s = _state;
    final m = await Isolate.run(() {
      const rules = ChessRules();
      return AlphaBeta<ChessState, ChessMove>(
        rules: rules,
        evaluate: chessEvaluator,
        depth: 8,
        timeLimit: const Duration(milliseconds: 1500),
        fastApply: rules.applyUnchecked,
        orderMoves: orderChessMoves,
        terminal: rules.resultWith,
        hash: (s) => s.hash,
        noisyMoves: chessNoisyMoves,
      ).bestMove(s);
    });
    return m == null || !identical(s, _state) ? null : (m.from, m.to);
  }

  @override
  bool get canUndo => _history.isNotEmpty;

  @override
  void undo() {
    if (!canUndo) return;
    _state = _history.removeLast();
    _moves.removeLast();
    _sans.removeLast();
    _resultComputed = false;
  }

  @override
  List<String> get moveLog => List.unmodifiable(_sans);

  @override
  String? get lastMoveSpoken {
    if (_sans.isEmpty) return null;
    final who = _history.last.toMove == 0 ? tr('Blancas') : tr('Negras');
    return '$who: ${Spoken.chess(_sans.last)}';
  }

  @override
  List<String> get moveCodes => [for (final m in _moves) m.uci];

  @override
  bool replay(String code) {
    final m = ChessEngine.fromUci(_state.position, code);
    if (m == null) return false;
    _apply(m);
    return true;
  }

  @override
  GameResult timeout(int player) => _rules.onTimeout(_state, player);

  @override
  String? claimableDraw() => switch (_rules.claimableDraw(_state)) {
        DrawClaim.threefoldRepetition => tr('triple repetición'),
        DrawClaim.fiftyMoves => tr('regla de los 50 movimientos'),
        null => null,
      };

  @override
  BoardSnapshot snapshot() {
    final b = _state.position.board;
    final pieces = <PieceView>[
      for (var s = 0; s < 64; s++)
        if (b[s] != 0)
          PieceView(
            cell: s,
            owner: b[s] > 0 ? 0 : 1,
            style: PieceStyle.chessGlyph,
            glyph: _kinds[b[s].abs()],
          ),
    ];
    var path = const <int>[];
    var captured = const <int>[];
    if (_moves.isNotEmpty) {
      final m = _moves.last;
      final before = _history.last.position;
      path = [m.from, m.to];
      if (m.flag == MoveFlag.enPassant) {
        captured = [m.to - 8 * before.side];
      } else if (before.board[m.to] != 0) {
        captured = [m.to];
      }
    }
    final p = _state.position;
    return BoardSnapshot(
      shape: BoardShape.chessGrid,
      size: 8,
      version: _moves.length,
      pieces: pieces,
      lastPath: path,
      lastCaptured: captured,
      checkCell: ChessEngine.inCheck(p) ? ChessEngine.kingSquare(p.board, p.side) : null,
    );
  }
}
