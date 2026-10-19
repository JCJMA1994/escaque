import 'package:tablero_engine/tablero_engine.dart';
import 'package:test/test.dart';

void main() {
  const rules = ChessRules();

  ChessState play(List<String> sans, [ChessState? from]) {
    var s = from ?? rules.initialState();
    for (final san in sans) {
      final m = ChessEngine.fromSan(s.position, san);
      expect(m, isNotNull, reason: 'jugada $san');
      s = rules.apply(s, m!);
    }
    return s;
  }

  test('FEN ida y vuelta', () {
    expect(ChessPosition.fromFen(startFen).toFen(), startFen);
  });

  test('mate del loco', () {
    final s = play(['f3', 'e5', 'g4']);
    final mate = ChessEngine.fromSan(s.position, 'Qh4')!;
    expect(ChessEngine.toSan(s.position, mate), 'Qh4#');
    final r = rules.result(rules.apply(s, mate))!;
    expect(r.winner, 1);
    expect(r.reason, 'jaque mate');
  });

  test('rey ahogado', () {
    final r = rules.result(rules.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'))!;
    expect(r.isDraw, isTrue);
    expect(r.reason, 'rey ahogado');
  });

  test('material insuficiente: rey y alfil contra rey', () {
    final r = rules.result(rules.fromFen('8/8/8/4k3/8/8/2B5/4K3 w - - 0 1'))!;
    expect(r.isDraw, isTrue);
  });

  test('no se enroca a través de una casilla atacada', () {
    final s = rules.fromFen('4k3/8/8/8/8/8/5r2/4K2R w K - 0 1');
    expect(rules.legalMoves(s).where((m) => m.flag == MoveFlag.castle), isEmpty);
  });

  test('enroque corto legal y movimiento de la torre', () {
    final s = rules.fromFen('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    final castle = ChessEngine.fromSan(s.position, 'O-O')!;
    final next = rules.apply(s, castle).position;
    expect(next.board[6], Piece.king);
    expect(next.board[5], Piece.rook);
    expect(next.castling, 0);
  });

  test('captura al paso', () {
    final s = rules.fromFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
    final ep = rules.legalMoves(s).firstWhere((m) => m.flag == MoveFlag.enPassant);
    expect(ChessEngine.toSan(s.position, ep), 'exd6');
    expect(rules.apply(s, ep).position.board[parseSquare('d5')], 0);
  });

  test('coronación con jaque', () {
    final s = rules.fromFen('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
    final m = ChessEngine.fromUci(s.position, 'b7b8q')!;
    expect(ChessEngine.toSan(s.position, m), 'b8=Q+');
  });

  test('desambiguación SAN', () {
    final s = rules.fromFen('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1');
    final m = ChessEngine.fromUci(s.position, 'b1d2')!;
    expect(ChessEngine.toSan(s.position, m), 'Nbd2');
  });

  test('triple repetición reclamable, no automática', () {
    final s = play(['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1', 'Ng8']);
    expect(rules.claimableDraw(s), DrawClaim.threefoldRepetition);
    expect(rules.result(s), isNull);
  });

  test('tiempo agotado contra rey solo = tablas', () {
    final s = rules.fromFen('4k3/8/8/8/8/8/8/Q3K3 w - - 0 1');
    // Cae la bandera de las blancas: las negras, con rey solo, no pueden dar mate.
    expect(rules.onTimeout(s, 0).isDraw, isTrue);
    // Cae la de las negras: las blancas tienen dama y ganan.
    expect(rules.onTimeout(s, 1).winner, 0);
  });

  test('jugada ilegal lanza error', () {
    final s = rules.initialState();
    expect(() => rules.apply(s, const ChessMove(12, 36)), throwsArgumentError);
  });

  test('quíntuple repetición termina la partida sola', () {
    final moves = <String>[];
    for (var i = 0; i < 4; i++) {
      moves.addAll(['Nf3', 'Nf6', 'Ng1', 'Ng8']);
    }
    final s = play(moves);
    expect(s.repetitions, 5);
    expect(rules.result(s)?.reason, 'quíntuple repetición');
  });

  test('el hash ignora la captura al paso si no es posible', () {
    // Tras 1. e4 no hay peón negro que pueda capturar al paso en e3.
    final a = play(['e4']);
    final b = rules.fromFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
    expect(a.hash, b.hash);
  });
}
