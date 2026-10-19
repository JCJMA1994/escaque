import 'package:tablero_engine/tablero_engine.dart';
import 'package:test/test.dart';

/// Posiciones de referencia de perft (valores publicados en la wiki de
/// Chess Programming). Si alguno falla, el generador de jugadas tiene un bug.
void main() {
  const cases = {
    'inicial': (startFen, [20, 400, 8902, 197281]),
    'kiwipete': (
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      [48, 2039, 97862]
    ),
    'posición 3': ('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812, 43238]),
    'posición 4': (
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
      [6, 264, 9467]
    ),
    'posición 5': (
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
      [44, 1486, 62379]
    ),
  };

  for (final entry in cases.entries) {
    final (fen, expected) = entry.value;
    test('perft ${entry.key}', () {
      final p = ChessPosition.fromFen(fen);
      for (var d = 1; d <= expected.length; d++) {
        expect(ChessEngine.perft(p, d), expected[d - 1], reason: 'profundidad $d');
      }
    });
  }
}
