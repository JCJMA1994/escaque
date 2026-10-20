import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/metrics.dart';
import '../app/settings.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../board/board_game.dart';
import '../match/adapters/chess_adapter.dart';
import '../match/adapters/draughts_adapter.dart';
import '../match/adapters/match_adapter.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import 'puzzles.dart';
import '../l10n/l10n.dart';

/// Resolver un problema. Mate en 1: cualquier jugada que dé mate. Mate en 2:
/// la primera jugada es la única que fuerza el mate; la defensa la juega el
/// motor y después hay que dar mate.
class PuzzleScreen extends ConsumerStatefulWidget {
  final int puzzleId;
  final bool daily;
  const PuzzleScreen({super.key, required this.puzzleId, this.daily = false});

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

enum _Phase { solving, replying, wrong, solved }

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> {
  Puzzle? _puzzle;
  late MatchAdapter _adapter;
  BoardGame? _game;
  int? _selected;
  List<int> _targets = const [];
  _Phase _phase = _Phase.solving;
  String _message = '';
  final _rng = Random();
  int _attempts = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = TableroColors.of(context).withBoard(ref.read(settingsProvider).boardTheme);
    if (_game == null) {
      _game = BoardGame(colors: colors, onCellTap: _tap);
    } else {
      _game!.updateColors(colors);
    }
    if (_puzzle != null) _game!.sync(_view());
  }

  @override
  void dispose() {
    _game = null;
    super.dispose();
  }

  /// Se llama desde build: prepara el estado sin setState.
  void _load(Puzzle p) {
    if (_puzzle?.id == p.id) return;
    _puzzle = p;
    _reset();
    if (_game != null) _game!.sync(_view());
  }

  void _reset() {
    final p = _puzzle!;
    _adapter = p.isDraughts
        ? DraughtsAdapter(p.variant!, initial: DraughtsRules(p.variant!).fromBoard(p.board, p.side))
        : ChessAdapter(fen: p.fen);
    _selected = null;
    _targets = const [];
    _phase = _Phase.solving;
    _message = '${_puzzle!.sideText}. ${_puzzle!.goal}';
  }

  void _restart() {
    _reset();
    _sync();
  }

  MatchView _view() {
    final p = _puzzle!;
    final canMove = _phase == _Phase.solving && _adapter.toMove == p.sideToMove;
    return MatchView(
      config: MatchConfig(
        kind: p.kind,
        draughtsVariant: p.variant ?? DraughtsVariant.spanish,
        opponent: Opponent.ai,
        humanSeat: p.sideToMove,
      ),
      board: _adapter.snapshot(),
      toMove: _adapter.toMove,
      movable: canMove ? _adapter.movableCells() : const {},
      selected: _selected,
      targets: _targets,
      aiThinking: _phase == _Phase.replying,
      moveLog: _adapter.moveLog,
      result: null,
      clocks: null,
      mustCapture: false,
      pendingPromotion: null,
      spokenMove: _adapter.lastMoveSpoken,
      canUndo: false,
      flipped: p.sideToMove == 1,
    );
  }

  void _syncBoard() {
    if (mounted && _puzzle != null) {
      _game?.sync(_view());
      setState(() {});
    }
  }

  void _sync() => _syncBoard();

  void _tap(int cell) {
    if (_phase != _Phase.solving || _adapter.toMove != _puzzle!.sideToMove) return;
    if (_selected != null && _targets.contains(cell)) {
      _move(_selected!, cell);
      return;
    }
    if (_adapter.movableCells().contains(cell)) {
      _selected = cell == _selected ? null : cell;
      _targets = _selected == null ? const [] : _adapter.targetsFrom(cell);
    } else {
      _selected = null;
      _targets = const [];
    }
    _sync();
  }

  int? _promotionFor(int from, int to) {
    if (!_adapter.needsPromotionChoice(from, to)) return null;
    // La coronación de la solución, si es esa jugada; si no, dama.
    final sol = _puzzle!.solution;
    final code = '${_squareName(from)}${_squareName(to)}';
    if (sol.length == 5 && sol.startsWith(code)) return Piece.knight + 'nbrq'.indexOf(sol[4]);
    return Piece.queen;
  }

  static String _squareName(int s) => '${'abcdefgh'[s % 8]}${s ~/ 8 + 1}';

  /// Material desde el bando del problema (peón 1, dama 3).
  static int _material(List<int> board, int side) {
    var m = 0;
    for (final x in board) {
      if (x == 0) continue;
      final v = x.abs() == 2 ? 3 : 1;
      m += x * side > 0 ? v : -v;
    }
    return m;
  }

  /// Damas: 1) la jugada de la solución, 2) responde el motor, 3) capturar
  /// ganando al menos 2 de material.
  Future<void> _moveDraughts(int from, int to) async {
    final p = _puzzle!;
    final a = _adapter as DraughtsAdapter;
    final ply = a.moveCodes.length;
    // Con varios recorridos posibles, el que más material gana.
    int? route;
    final routes = a.routesFor(from, to);
    if (routes.length > 1) {
      var best = -999;
      for (var i = 0; i < routes.length; i++) {
        final trial = DraughtsAdapter(p.variant!, initial: a.state)..play(from, to, route: i);
        final g = _material(trial.state.board, p.side);
        if (g > best) {
          best = g;
          route = i;
        }
      }
    }
    if (!a.play(from, to, route: route)) return;
    _selected = null;
    _targets = const [];
    _feedback();
    if (ply == 0 && a.moveCodes.last == p.solution) {
      _phase = _Phase.replying;
      _message = tr('¡Bien! Ahora responde el rival…');
      _sync();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      final replies = DraughtsRules(p.variant!).legalMoves(a.state);
      if (replies.isEmpty) {
        await _solved(); // el rival no puede mover: gana
        return;
      }
      a.replay(replies[_rng.nextInt(replies.length)].path.join('-'));
      _feedback();
      _phase = _Phase.solving;
      _message = tr('Y ahora, a capturar.');
      _sync();
      _announce(_message);
      return;
    }
    final gain = _material(a.state.board, p.side) - _material(p.board, p.side);
    if (ply == 2 && (gain >= 2 || a.result?.winner == p.sideToMove)) {
      await _solved();
      return;
    }
    await _wrong(ply == 0 ? tr('Esa no gana material. Prueba otra.') : tr('Así no ganas material. Inténtalo de nuevo.'));
  }

  Future<void> _wrong(String message) async {
    _attempts++;
    _phase = _Phase.wrong;
    _message = message;
    _sync();
    _announce(_message);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _restart();
  }

  Future<void> _move(int from, int to) async {
    final p = _puzzle!;
    if (p.isDraughts) return _moveDraughts(from, to);
    final ply = _adapter.moveCodes.length;
    if (!_adapter.play(from, to, promotion: _promotionFor(from, to))) return;
    _selected = null;
    _targets = const [];
    _feedback();
    final mated = _adapter.result?.winner == p.sideToMove;
    if (mated) {
      await _solved();
      return;
    }
    if (p.mateIn == 2 && ply == 0 && _adapter.moveCodes.last == p.solution) {
      // Buena primera jugada: responde el motor con una defensa cualquiera
      // (todas pierden por construcción del problema).
      _phase = _Phase.replying;
      _message = tr('¡Bien! Ahora responde el rival…');
      _sync();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      final replies = const ChessRules().legalMoves((_adapter as ChessAdapter).state);
      final r = replies[_rng.nextInt(replies.length)];
      _adapter.play(r.from, r.to, promotion: r.promotion == 0 ? null : r.promotion);
      _feedback();
      _phase = _Phase.solving;
      _message = tr('Y ahora, mate.');
      _sync();
      _announce(_message);
      return;
    }
    // Jugada que no lleva al mate: se deshace y se vuelve a intentar.
    await _wrong(p.mateIn == 2 && ply == 0 ? tr('Esa no fuerza el mate. Prueba otra.') : tr('No es mate. Inténtalo de nuevo.'));
  }

  Future<void> _solved() async {
    _phase = _Phase.solved;
    _message = tr('¡Resuelto!');
    _sync();
    _announce(tr('Problema resuelto'));
    HapticFeedback.heavyImpact();
    Metrics.puzzleSolved(mateIn: _puzzle!.isDraughts ? 0 : _puzzle!.mateIn, daily: widget.daily, attempts: _attempts);
    await ref.read(puzzleProgressProvider.notifier).markSolved(_puzzle!.id, daily: widget.daily);
  }

  void _feedback() {
    final settings = ref.read(settingsProvider);
    if (settings.sound) Sounds.play(_adapter.moveLog.last.contains('x') ? Sounds.capture : Sounds.move);
    HapticFeedback.selectionClick();
    final spoken = _adapter.lastMoveSpoken;
    if (spoken != null) _announce(spoken);
  }

  void _announce(String text) {
    if (!mounted || !MediaQuery.of(context).accessibleNavigation) return;
    SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
  }

  void _showSolution() {
    final sol = _puzzle!.solution;
    final int from, to;
    if (_puzzle!.isDraughts) {
      final path = sol.split('-').map(int.parse).toList();
      from = path.first;
      to = path.last;
    } else {
      from = 'abcdefgh'.indexOf(sol[0]) + (int.parse(sol[1]) - 1) * 8;
      to = 'abcdefgh'.indexOf(sol[2]) + (int.parse(sol[3]) - 1) * 8;
    }
    _restart();
    _selected = from;
    _targets = [to];
    _message = tr('La primera jugada está marcada.');
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final all = ref.watch(puzzlesProvider);
    _game?.reduceMotion = MediaQuery.disableAnimationsOf(context);
    _game?.showCoordinates = ref.watch(settingsProvider).showCoordinates;
    return Scaffold(
      body: SafeArea(
        child: all.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('No se pudieron cargar los problemas.'), style: TType.body(c.ink))),
          data: (list) {
            final puzzle = list.firstWhere((p) => p.id == widget.puzzleId, orElse: () => list.first);
            _load(puzzle);
            final settings = ref.watch(settingsProvider);
            _game
              ?..reduceMotion = MediaQuery.disableAnimationsOf(context)
              ..showCoordinates = settings.showCoordinates
              ..updateColors(c.withBoard(settings.boardTheme))
              ..sync(_view());
            final index = list.indexOf(puzzle);
            final next = list[(index + 1) % list.length];
            final banner = switch (_phase) {
              _Phase.solved => (c.brand, c.brandInk),
              _Phase.wrong => (c.danger, c.bg),
              _ => (c.surfaceRaised, c.ink),
            };
            return ContentWidth(
              maxWidth: 640,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Row(
                      children: [
                        AppIconButton(
                          icon: AppIcons.back,
                          tooltip: tr('Volver'),
                          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.daily ? tr('Problema del día') : tr('Problema {id}', {'id': puzzle.id}), style: TType.title(c.ink)),
                              Text('${puzzle.gameName} · ${puzzle.title} · ${puzzle.sideText.toLowerCase()}',
                                  style: TType.bodySm(c.inkMuted)),
                            ],
                          ),
                        ),
                        AppIconButton(icon: AppIcons.undo, tooltip: tr('Reiniciar'), onPressed: _restart),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Semantics(
                            label: tr('Tablero del problema'),
                            child: GameWidget(
                              key: ValueKey(_game),
                              game: _game!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: banner.$1, borderRadius: BorderRadius.circular(12)),
                            child: Text(_message, style: TType.label(banner.$2), textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _phase == _Phase.solved ? null : _showSolution,
                                child: Text(tr('Ver pista')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => context.pushReplacement('/puzzles/${next.id}'),
                                child: Text(_phase == _Phase.solved ? tr('Siguiente') : tr('Saltar')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
