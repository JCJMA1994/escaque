import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/theme.dart';
import '../l10n/l10n.dart';
import '../match/match_config.dart';

/// Calidad de una jugada según cuánto empeora la evaluación para quien mueve.
enum MoveQuality { good, inaccuracy, mistake }

/// Análisis de una partida terminada (PLAN.md, fase C, punto 4).
class GameAnalysis {
  /// Evaluación en centipeones desde las blancas, antes de cada jugada y al
  /// final (n + 1 valores), recortada a ±1000.
  final List<double> evals;

  /// Por jugada: calidad y la mejor alternativa (notación) si era otra.
  final List<MoveQuality> quality;
  final List<String?> best;

  /// Índice de la jugada que más cambió la partida.
  final int keyMove;

  const GameAnalysis(this.evals, this.quality, this.best, this.keyMove);

  static const mistake = 200.0, inaccuracy = 80.0, clamp = 1000.0;

  String toJson() => jsonEncode({
        'evals': evals,
        'quality': [for (final q in quality) q.index],
        'best': best,
        'key': keyMove,
      });

  factory GameAnalysis.fromJson(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return GameAnalysis(
      [for (final e in j['evals'] as List) (e as num).toDouble()],
      [for (final q in j['quality'] as List) MoveQuality.values[q as int]],
      [for (final b in j['best'] as List) b as String?],
      j['key'] as int,
    );
  }

  /// Texto para TalkBack y la lista: «Jugada 14, error grave; mejor era Cxe5».
  String describe(int i, String played) {
    final n = i ~/ 2 + 1;
    final b = best[i];
    return switch (quality[i]) {
      MoveQuality.mistake => b == null
          ? tr('Jugada {n} ({move}): error grave', {'n': n, 'move': played})
          : tr('Jugada {n} ({move}): error grave; mejor era {best}', {'n': n, 'move': played, 'best': b}),
      MoveQuality.inaccuracy => b == null
          ? tr('Jugada {n} ({move}): imprecisión', {'n': n, 'move': played})
          : tr('Jugada {n} ({move}): imprecisión; mejor era {best}', {'n': n, 'move': played, 'best': b}),
      MoveQuality.good => tr('Jugada {n} ({move}): bien', {'n': n, 'move': played}),
    };
  }

  /// Analiza en un isolate propio; [onProgress] recibe la fracción hecha (0–1).
  /// El trabajo devuelto se puede cancelar ([AnalysisJob.cancel]).
  static AnalysisJob start(
    MatchConfig config,
    List<String> moves, {
    Duration perPosition = const Duration(milliseconds: 300),
    void Function(double)? onProgress,
  }) =>
      AnalysisJob._(config.kind, config.draughtsVariant.id, moves, perPosition, onProgress);
}

/// El análisis se canceló.
class AnalysisCancelled implements Exception {
  const AnalysisCancelled();
}

/// Análisis en marcha. `Isolate.run` no se puede interrumpir, así que se usa
/// un isolate propio que [cancel] termina al momento.
class AnalysisJob {
  final _done = Completer<GameAnalysis>();
  final _port = ReceivePort();
  Isolate? _isolate;
  bool _cancelled = false;

  AnalysisJob._(GameKind kind, String variantId, List<String> moves, Duration time, void Function(double)? onProgress) {
    _port.listen((m) {
      if (m is double) {
        onProgress?.call(m);
      } else if (m is String) {
        _finish(() => _done.complete(GameAnalysis.fromJson(m)));
      } else if (m is List) {
        _finish(() => _done.completeError(StateError('Análisis: ${m.first}')));
      }
    });
    Isolate.spawn(_entry, (_port.sendPort, kind, variantId, moves, time), errorsAreFatal: true, onError: _port.sendPort)
        .then((i) {
      if (_cancelled) {
        i.kill(priority: Isolate.immediate);
      } else {
        _isolate = i;
      }
    }, onError: (Object e) => _finish(() => _done.completeError(e)));
  }

  Future<GameAnalysis> get result => _done.future;

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(() => _done.completeError(const AnalysisCancelled()));
  }

  void _finish(void Function() complete) {
    if (_done.isCompleted) return;
    complete();
    _port.close();
  }

  static void _entry((SendPort, GameKind, String, List<String>, Duration) args) {
    final (send, kind, variantId, moves, time) = args;
    send.send(_analyse(kind, variantId, moves, time, send).toJson());
  }
}

/// Recorre la partida evaluando cada posición con la IA (sin ruido).
GameAnalysis _analyse(GameKind kind, String variantId, List<String> moves, Duration time, SendPort progress) {
  final scores = <double>[]; // desde el bando en turno
  final bestCodes = <String?>[];
  final bestText = <String?>[];
  final movers = <int>[];
  if (kind == GameKind.chess) {
    const rules = ChessRules();
    final ai = chessAi(5, timeLimit: time);
    var s = rules.initialState();
    final states = [s];
    for (final code in moves) {
      final m = ChessEngine.fromUci(s.position, code);
      if (m == null) break;
      s = rules.apply(s, m);
      states.add(s);
    }
    for (var i = 0; i < states.length; i++) {
      final st = states[i];
      movers.add(st.toMove);
      final r = ai.analyse(st);
      if (r == null) {
        final res = rules.result(st);
        scores.add(res == null || res.winner == null ? 0 : (res.winner == st.toMove ? GameAnalysis.clamp : -GameAnalysis.clamp));
        bestCodes.add(null);
        bestText.add(null);
      } else {
        scores.add(r.score);
        bestCodes.add(r.move.uci);
        bestText.add(ChessEngine.toSan(st.position, r.move));
      }
      progress.send((i + 1) / states.length);
    }
  } else {
    final variant = DraughtsVariant.all.firstWhere((v) => v.id == variantId);
    final rules = DraughtsRules(variant);
    final ai = draughtsAi(rules, 5, timeLimit: time);
    var s = rules.initialState();
    final states = [s];
    for (final code in moves) {
      final m = rules.legalMoves(s).where((m) => m.path.join('-') == code);
      if (m.isEmpty) break;
      s = rules.apply(s, m.first);
      states.add(s);
    }
    String notation(DraughtsMove m) =>
        '${rules.squareNumber(m.path.first)}${m.captured.isEmpty ? '-' : 'x'}${rules.squareNumber(m.path.last)}';
    for (var i = 0; i < states.length; i++) {
      final st = states[i];
      movers.add(st.toMove);
      final r = ai.analyse(st);
      if (r == null) {
        final res = rules.result(st);
        scores.add(res == null || res.winner == null ? 0 : (res.winner == st.toMove ? GameAnalysis.clamp : -GameAnalysis.clamp));
        bestCodes.add(null);
        bestText.add(null);
      } else {
        scores.add(r.score);
        bestCodes.add(r.move.path.join('-'));
        bestText.add(notation(r.move));
      }
      progress.send((i + 1) / states.length);
    }
  }
  double clampScore(double x) => max(-GameAnalysis.clamp, min(GameAnalysis.clamp, x));
  final evals = [for (var i = 0; i < scores.length; i++) clampScore(movers[i] == 0 ? scores[i] : -scores[i])];
  final n = scores.length - 1;
  final quality = <MoveQuality>[];
  final best = <String?>[];
  var keyMove = 0;
  var keySwing = -1.0;
  for (var i = 0; i < n; i++) {
    // Pérdida para quien movió: lo que valía la mejor jugada menos lo que vale ahora.
    final loss = clampScore(scores[i]) + clampScore(scores[i + 1]);
    quality.add(loss >= GameAnalysis.mistake
        ? MoveQuality.mistake
        : loss >= GameAnalysis.inaccuracy
            ? MoveQuality.inaccuracy
            : MoveQuality.good);
    best.add(i < moves.length && bestCodes[i] != moves[i] ? bestText[i] : null);
    final swing = (evals[i + 1] - evals[i]).abs();
    if (swing > keySwing) {
      keySwing = swing;
      keyMove = i;
    }
  }
  return GameAnalysis(evals, quality, best, keyMove);
}

/// Gráfica de la evaluación (blancas arriba). Marca la jugada actual y la clave.
class EvalChart extends StatelessWidget {
  final GameAnalysis analysis;
  final int ply;
  const EvalChart({super.key, required this.analysis, required this.ply});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Semantics(
      label: tr('Gráfica de la evaluación de la partida'),
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: CustomPaint(painter: _EvalPainter(analysis, ply, c)),
      ),
    );
  }
}

class _EvalPainter extends CustomPainter {
  final GameAnalysis a;
  final int ply;
  final TableroColors c;
  _EvalPainter(this.a, this.ply, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final n = a.evals.length;
    if (n < 2) return;
    double x(int i) => i * size.width / (n - 1);
    double y(double e) => size.height / 2 - (e / GameAnalysis.clamp) * size.height / 2;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)), Paint()..color = c.surfaceRaised);
    final area = Path()..moveTo(0, size.height / 2);
    for (var i = 0; i < n; i++) {
      area.lineTo(x(i), y(a.evals[i]));
    }
    area
      ..lineTo(size.width, size.height / 2)
      ..close();
    canvas.drawPath(area, Paint()..color = c.brand.withAlpha(70));
    final line = Path()..moveTo(0, y(a.evals[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(a.evals[i]));
    }
    canvas.drawPath(line, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = c.brand);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), Paint()..color = c.line);
    for (var i = 0; i < a.quality.length; i++) {
      if (a.quality[i] == MoveQuality.mistake) {
        canvas.drawCircle(Offset(x(i + 1), y(a.evals[i + 1])), 3.5, Paint()..color = c.danger);
      }
    }
    canvas.drawLine(Offset(x(a.keyMove + 1), 0), Offset(x(a.keyMove + 1), size.height),
        Paint()
          ..color = c.accent
          ..strokeWidth = 2);
    canvas.drawLine(Offset(x(ply), 0), Offset(x(ply), size.height), Paint()..color = c.ink.withAlpha(120));
  }

  @override
  bool shouldRepaint(_EvalPainter old) => old.ply != ply || old.a != a;
}
