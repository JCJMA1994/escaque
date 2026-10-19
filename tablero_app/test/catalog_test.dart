import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_app/puzzles/catalog.dart';
import 'package:tablero_app/puzzles/puzzles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final chess = jsonDecode(File('assets/puzzles_chess.json').readAsStringSync()) as List;
  final draughts = jsonDecode(File('assets/puzzles_draughts.json').readAsStringSync()) as List;

  String catalog(List<Object?> puzzles, {int format = 1}) =>
      jsonEncode({'format': format, 'version': 'x', 'puzzles': puzzles});

  test('valida los problemas reales del catálogo', () {
    final all = PuzzleCatalog.parseAndValidate(catalog([...chess, ...draughts]));
    expect(all, hasLength(chess.length + draughts.length));
  });

  test('descarta entradas inválidas o mal formadas, y formatos desconocidos', () {
    final good = chess.first as Map<String, dynamic>;
    final wrongSolution = {...good, 'id': 9001, 'solution': 'a1a1'};
    final notMate = {...good, 'id': 9002, 'solution': (chess[3] as Map)['solution']};
    final badDraughts = {...(draughts.first as Map<String, dynamic>), 'id': 9003, 'board': [1, 2, 3]};
    final out = PuzzleCatalog.parseAndValidate(catalog([good, wrongSolution, notMate, badDraughts, 'basura']));
    expect(out.map((p) => p.id), [good['id']]);
    expect(PuzzleCatalog.parseAndValidate(catalog([good], format: 2)), isEmpty);
    expect(PuzzleCatalog.parseAndValidate('no es json'), isEmpty);
  });

  test('los incluidos van primero y los remotos solo añaden ids nuevos', () {
    const a = Puzzle(id: 1, solution: 'x'), b = Puzzle(id: 2, solution: 'y'), b2 = Puzzle(id: 2, solution: 'z');
    const c = Puzzle(id: 3, solution: 'w');
    expect(PuzzleCatalog.merge([a, b], [b2, c]).map((p) => (p.id, p.solution)), [(1, 'x'), (2, 'y'), (3, 'w')]);
  });

  test('descarga como mucho una vez al día y guarda la copia', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(catalog([chess.first]), 200);
    });
    final t = DateTime(2026, 10, 18, 10);
    expect(await PuzzleCatalog.refresh(client: client, now: t), hasLength(1));
    expect(await PuzzleCatalog.refresh(client: client, now: t.add(const Duration(hours: 5))), isNull);
    expect(calls, 1);
    expect(await PuzzleCatalog.cached(), hasLength(1));
    await PuzzleCatalog.refresh(client: client, now: t.add(const Duration(days: 2)));
    expect(calls, 2);
  });

  test('un catálogo roto no sustituye a la copia buena', () async {
    SharedPreferences.setMockInitialValues({});
    final ok = MockClient((_) async => http.Response(catalog([chess.first]), 200));
    final broken = MockClient((_) async => http.Response('{"format":1,"puzzles":[]}', 200));
    final t = DateTime(2026, 10, 18);
    await PuzzleCatalog.refresh(client: ok, now: t);
    expect(await PuzzleCatalog.refresh(client: broken, now: t.add(const Duration(days: 2))), isNull);
    expect(await PuzzleCatalog.cached(), hasLength(1));
  });
}
