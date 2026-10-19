import 'package:tablero_engine/tablero_engine.dart';

/// Dos IA juegan 20 jugadas de ajedrez y una partida de damas españolas.
void main() {
  const chess = ChessRules();
  var s = chess.initialState();
  final white = chessAi(3, seed: 1), black = chessAi(2, seed: 2);
  final sans = <String>[];
  for (var ply = 0; ply < 40 && chess.result(s) == null; ply++) {
    final m = (s.toMove == 0 ? white : black).bestMove(s)!;
    sans.add(ChessEngine.toSan(s.position, m));
    s = chess.applyUnchecked(s, m);
  }
  final pgn = StringBuffer();
  for (var i = 0; i < sans.length; i++) {
    if (i.isEven) pgn.write('${i ~/ 2 + 1}. ');
    pgn.write('${sans[i]} ');
  }
  print(pgn.toString().trim());
  print('FEN final: ${s.position.toFen()}');
  print('Resultado: ${chess.result(s) ?? 'en curso'}');

  final draughts = DraughtsRules(DraughtsVariant.spanish);
  var d = draughts.initialState();
  final ai = draughtsAi(draughts, 2, seed: 3);
  var plies = 0;
  while (draughts.result(d) == null && plies < 200) {
    d = draughts.applyUnchecked(d, ai.bestMove(d)!);
    plies++;
  }
  print('Damas españolas tras $plies medias jugadas: ${draughts.result(d) ?? 'en curso'}');
}
