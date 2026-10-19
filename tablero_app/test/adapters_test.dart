import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/board/board_layout.dart';
import 'package:tablero_app/match/adapters/chess_adapter.dart';
import 'package:tablero_app/match/adapters/chinese_checkers_adapter.dart';
import 'package:tablero_app/match/adapters/draughts_adapter.dart';
import 'package:tablero_app/match/board_view.dart';
import 'package:tablero_engine/tablero_engine.dart';

void main() {
  test('ajedrez: e2-e4 por casillas y snapshot', () {
    final a = ChessAdapter();
    expect(a.targetsFrom(parseSquare('e2')), containsAll([parseSquare('e3'), parseSquare('e4')]));
    expect(a.play(parseSquare('e2'), parseSquare('e4')), isTrue);
    final snap = a.snapshot();
    expect(snap.version, 1);
    expect(snap.lastPath, [parseSquare('e2'), parseSquare('e4')]);
    expect(a.moveLog, ['e4']);
    a.undo();
    expect(a.snapshot().version, 0);
  });

  test('damas: snapshot con 24 piezas y jugada legal', () {
    final a = DraughtsAdapter(DraughtsVariant.spanish);
    expect(a.snapshot().pieces, hasLength(24));
    final from = a.movableCells().first;
    expect(a.play(from, a.targetsFrom(from).first), isTrue);
    expect(a.moveLog, hasLength(1));
  });

  test('damas chinas: 2 jugadores, 20 fichas', () {
    final a = ChineseCheckersAdapter(2);
    expect(a.snapshot().pieces, hasLength(20));
    expect(a.snapshot().shape, BoardShape.star);
  });

  test('layout: ida y vuelta casilla ↔ punto', () {
    for (final flipped in [false, true]) {
      final l = BoardLayout(shape: BoardShape.chessGrid, size: 8, flipped: flipped, extent: 800);
      for (var i = 0; i < 64; i++) {
        expect(l.cellAt(l.center(i)), i);
      }
    }
    final star = BoardLayout(shape: BoardShape.star, size: 0, flipped: false, extent: 800);
    for (var i = 0; i < 121; i++) {
      expect(star.cellAt(star.center(i)), i);
    }
  });

  test('damas: elegir recorrido cuando dos capturas acaban en la misma casilla', () {
    // Dama blanca en 12 y seis peones negros: dos secuencias de 3 capturas
    // distintas terminan en 30 (posición encontrada con el prototipo del motor).
    const rules = DraughtsRules(DraughtsVariant.international);
    final b = List.filled(100, 0);
    b[12] = 2;
    for (final s in [32, 34, 41, 54, 65, 89]) {
      b[s] = -1;
    }
    final a = DraughtsAdapter(DraughtsVariant.international, initial: rules.fromBoard(b, 1));
    final routes = a.routesFor(12, 30);
    expect(routes, hasLength(2));
    expect(a.play(12, 30, route: 1), isTrue);
    // Recorrido 1: por 56 y 74, capturando 34, 65 y 41. El peón de 54 (que
    // el recorrido 0 capturaba) sigue en el tablero.
    expect(a.state.board[30], 2);
    expect(a.state.board[65], 0);
    expect(a.state.board[54], -1);
    expect(a.moveLog.single, '7x16');
  });

  test('ajedrez: anuncio de la última jugada', () {
    final a = ChessAdapter();
    final m = ChessEngine.fromSan(a.state.position, 'Nf3')!;
    a.play(m.from, m.to);
    expect(a.lastMoveSpoken, 'Blancas: Caballo a f3');
  });
}
