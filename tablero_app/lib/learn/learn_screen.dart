import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/metrics.dart';
import '../app/play_games.dart';
import '../app/settings.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../board/board_game.dart';
import '../l10n/l10n.dart';
import '../match/adapters/chess_adapter.dart';
import '../match/adapters/chinese_checkers_adapter.dart';
import '../match/adapters/draughts_adapter.dart';
import '../match/adapters/match_adapter.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import 'lessons.dart';

/// Lecciones completadas (en el dispositivo).
class LearnProgress extends AsyncNotifier<Set<String>> {
  static const _k = 'lessonsDone';

  @override
  Future<Set<String>> build() async =>
      ((await SharedPreferences.getInstance()).getStringList(_k) ?? const <String>[]).toSet();

  Future<void> complete(String id) async {
    final next = {...(state.valueOrNull ?? await future), id};
    state = AsyncData(next);
    await (await SharedPreferences.getInstance()).setStringList(_k, next.toList());
    if (lessons.every((l) => next.contains(l.id))) PlayGames.unlock(PlayAchievement.allLessons);
  }
}

final learnProgressProvider = AsyncNotifierProvider<LearnProgress, Set<String>>(LearnProgress.new);

/// Lista de lecciones de un juego (o de todos).
class LearnListScreen extends ConsumerWidget {
  final GameKind? kind;
  const LearnListScreen({super.key, this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final done = ref.watch(learnProgressProvider).valueOrNull ?? const <String>{};
    final groups = [
      (GameKind.chess, tr('Ajedrez')),
      (GameKind.draughts, tr('Damas')),
      (GameKind.chineseCheckers, tr('Damas chinas')),
    ].where((g) => kind == null || g.$1 == kind);
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
            children: [
              Row(children: [
                AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                Expanded(child: Text(tr('Aprende a jugar'), style: TType.titleLg(c.ink))),
              ]),
              for (final (k, name) in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: Text(name, style: TType.title(c.ink)),
                ),
                for (final (i, l) in _numbered(k))
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: done.contains(l.id) ? c.brand : c.surfaceRaised,
                      child: done.contains(l.id)
                          ? AppIcon(AppIcons.check, color: c.brandInk, size: 20)
                          : Text('${i + 1}', style: TType.label(c.ink)),
                    ),
                    title: Text(tr(l.title), style: TType.label(c.ink)),
                    trailing: AppIcon(AppIcons.chevronRight, color: c.inkMuted),
                    onTap: () => context.push('/learn/${l.id}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

List<(int, Lesson)> _numbered(GameKind kind) {
  final out = <(int, Lesson)>[];
  for (final l in lessons) {
    if (l.kind == kind) out.add((out.length, l));
  }
  return out;
}

/// Una lección: se juega la jugada pedida en el tablero real.
class LessonScreen extends ConsumerStatefulWidget {
  final String lessonId;
  const LessonScreen({super.key, required this.lessonId});

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  late Lesson _lesson = lessons.firstWhere((l) => l.id == widget.lessonId, orElse: () => lessons.first);
  late MatchAdapter _adapter;
  BoardGame? _game;
  int? _selected;
  List<int> _targets = const [];
  bool _done = false;
  bool _wrong = false;
  String _wrongText = '';

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = TableroColors.of(context).withBoard(ref.read(settingsProvider).boardTheme);
    if (_game == null) {
      _game = BoardGame(colors: colors, onCellTap: _tap)..dragEnabled = true;
    } else {
      _game!.updateColors(colors);
    }
    _game!.sync(_view());
  }

  @override
  void dispose() {
    _game = null;
    super.dispose();
  }

  void _reset() {
    final l = _lesson;
    _adapter = switch (l.kind) {
      GameKind.draughts => DraughtsAdapter(l.variant!, initial: DraughtsRules(l.variant!).fromBoard(l.board, l.side)),
      GameKind.chineseCheckers => ChineseCheckersAdapter(2, initial: l.ccState()),
      GameKind.chess => ChessAdapter(fen: l.fen),
    };
    _selected = null;
    _targets = const [];
    _done = false;
    _wrong = false;
  }

  MatchView _view() {
    final l = _lesson;
    final seat = _adapter.toMove;
    return MatchView(
      config: MatchConfig(
        kind: l.kind,
        draughtsVariant: l.variant ?? DraughtsVariant.spanish,
        players: 2,
        opponent: Opponent.ai,
        humanSeat: seat,
      ),
      board: _adapter.snapshot(),
      toMove: _adapter.toMove,
      movable: _done ? const {} : _adapter.movableCells(),
      selected: _selected,
      targets: _targets,
      aiThinking: false,
      moveLog: _adapter.moveLog,
      result: null,
      clocks: null,
      mustCapture: _adapter.mustCapture,
      pendingPromotion: null,
      spokenMove: _adapter.lastMoveSpoken,
      canUndo: false,
      flipped: false,
    );
  }

  void _syncBoard() {
    if (mounted) {
      _game?.sync(_view());
      setState(() {});
    }
  }

  void _sync() => _syncBoard();

  void _tap(int cell) {
    if (_done) return;
    if (_selected != null && _targets.contains(cell)) {
      _play(_selected!, cell);
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

  Future<void> _play(int from, int to) async {
    final promotion = _adapter.needsPromotionChoice(from, to) ? Piece.queen : null;
    if (!_adapter.play(from, to, promotion: promotion)) return;
    _selected = null;
    _targets = const [];
    final settings = ref.read(settingsProvider);
    if (settings.sound) Sounds.play(Sounds.move);
    final code = _adapter.moveCodes.last;
    final ok = _lesson.acceptCodes.contains(code);
    final trap = _lesson.traps[code];
    Metrics.tutorialStep(lesson: _lesson.id, ok: ok);
    if (ok) {
      _done = true;
      HapticFeedback.heavyImpact();
      _announce(tr(_lesson.done));
      await ref.read(learnProgressProvider.notifier).complete(_lesson.id);
      _sync();
      return;
    }
    _wrong = true;
    _wrongText = trap == null ? tr('Esa no es la jugada que buscamos. Inténtalo de nuevo.') : tr(trap);
    _sync();
    _announce(_wrongText);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _reset();
    _sync();
  }

  void _announce(String text) {
    if (!mounted || !MediaQuery.of(context).accessibleNavigation) return;
    SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
  }

  void _next() {
    final same = lessons.where((l) => l.kind == _lesson.kind).toList();
    final i = same.indexOf(_lesson);
    if (i + 1 >= same.length) {
      context.pop();
      return;
    }
    setState(() {
      _lesson = same[i + 1];
      _reset();
    });
    _syncBoard();
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final settings = ref.watch(settingsProvider);
    _game
      ?..reduceMotion = MediaQuery.disableAnimationsOf(context)
      ..showCoordinates = settings.showCoordinates
      ..dragEnabled = true
      ..updateColors(c.withBoard(settings.boardTheme))
      ..sync(_view());
    final (bg, fg, text) = _done
        ? (c.brand, c.brandInk, tr(_lesson.done))
        : _wrong
            ? (c.danger, c.bg, _wrongText)
            : (c.surfaceRaised, c.ink, tr(_lesson.text));
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 640,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Row(children: [
                  AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                  Expanded(child: Text(tr(_lesson.title), style: TType.title(c.ink))),
                  AppIconButton(
                    icon: AppIcons.undo,
                    tooltip: tr('Reiniciar'),
                    onPressed: () {
                      _reset();
                      _sync();
                    },
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                    child: Text(text, style: TType.body(fg)),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Semantics(
                        label: tr('Tablero de la lección'),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _done ? _next : null,
                    child: Text(tr('Siguiente lección')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
