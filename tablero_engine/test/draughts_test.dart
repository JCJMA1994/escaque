import 'package:tablero_engine/tablero_engine.dart';
import 'package:test/test.dart';

void main() {
  group('perft desde la posición inicial', () {
    // Valores publicados para inglesa e internacional.
    const expected = {
      'english': [7, 49, 302, 1469, 7361, 36768],
      'international': [9, 81, 658, 4265, 27117],
      'spanish': [7, 49, 302],
    };
    for (final v in DraughtsVariant.all) {
      test(v.name, () {
        final rules = DraughtsRules(v);
        final s = rules.initialState();
        final values = expected[v.id]!;
        for (var d = 1; d <= values.length; d++) {
          expect(rules.perft(s, d), values[d - 1], reason: 'profundidad $d');
        }
      });
    }
  });

  List<int> empty(int n) => List.filled(n * n, 0);
  int sq(int n, int r, int c) => r * n + c;

  test('internacional: peón captura hacia atrás y se exige el máximo', () {
    final rules = DraughtsRules(DraughtsVariant.international);
    final b = empty(10);
    b[sq(10, 5, 4)] = 1;
    b[sq(10, 6, 5)] = -1; // detrás: solo 1 captura
    b[sq(10, 4, 3)] = -1; // delante: cadena de 2
    b[sq(10, 2, 3)] = -1;
    final moves = rules.legalMoves(rules.fromBoard(b, 1));
    expect(moves, hasLength(1));
    expect(moves.single.path, [54, 32, 14]);
    expect(moves.single.captured, [43, 23]);
  });

  test('internacional: dama larga encadena tres capturas', () {
    final rules = DraughtsRules(DraughtsVariant.international);
    final b = empty(10);
    b[sq(10, 9, 0)] = 2;
    b[sq(10, 6, 3)] = -1;
    b[sq(10, 4, 3)] = -1;
    b[sq(10, 4, 1)] = -1;
    final moves = rules.legalMoves(rules.fromBoard(b, 1));
    expect(moves.single.path, [90, 54, 32, 50]);
    expect(moves.single.captured, [63, 43, 41]);
  });

  test('internacional: sin preferencia por capturar damas', () {
    final rules = DraughtsRules(DraughtsVariant.international);
    final b = empty(10);
    b[sq(10, 5, 2)] = 1;
    b[sq(10, 4, 3)] = -1;
    b[sq(10, 4, 1)] = -2;
    expect(rules.legalMoves(rules.fromBoard(b, 1)), hasLength(2));
  });

  test('española: con igual número de piezas, obligatorio capturar la dama', () {
    final rules = DraughtsRules(DraughtsVariant.spanish);
    final b = empty(8);
    b[sq(8, 5, 2)] = 1;
    b[sq(8, 4, 3)] = -1;
    b[sq(8, 4, 1)] = -2;
    final moves = rules.legalMoves(rules.fromBoard(b, 1));
    expect(moves.single.path, [42, 24]);
    expect(moves.single.captured, [33]);
  });

  test('inglesa: coronar capturando termina el turno', () {
    final rules = DraughtsRules(DraughtsVariant.english);
    final b = empty(8);
    b[sq(8, 2, 1)] = 1;
    b[sq(8, 1, 2)] = -1;
    b[sq(8, 1, 4)] = -1;
    final s = rules.fromBoard(b, 1);
    final moves = rules.legalMoves(s);
    expect(moves.single.path, [17, 3]);
    expect(rules.apply(s, moves.single).board[3], 2);
  });

  test('internacional: pasar por la última fila capturando no corona', () {
    final rules = DraughtsRules(DraughtsVariant.international);
    final b = empty(10);
    b[sq(10, 2, 1)] = 1;
    b[sq(10, 1, 2)] = -1;
    b[sq(10, 1, 4)] = -1;
    final s = rules.fromBoard(b, 1);
    final moves = rules.legalMoves(s);
    expect(moves.single.path, [21, 3, 25]);
    expect(rules.apply(s, moves.single).board[25], 1);
  });

  test('sin movimientos pierde', () {
    final rules = DraughtsRules(DraughtsVariant.english);
    final b = empty(8);
    b[sq(8, 0, 1)] = -1; // las blancas no tienen piezas: no pueden mover
    final r = rules.result(rules.fromBoard(b, 1))!;
    expect(r.winner, 1);
  });

  test('notación PDN', () {
    final rules = DraughtsRules(DraughtsVariant.international);
    final m = DraughtsMove([sq(10, 6, 1), sq(10, 5, 2)]);
    expect(rules.notation(m), '31-27');
  });
}
