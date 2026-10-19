import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../board/board_game.dart';
import '../data/export.dart';
import '../data/game_store.dart';
import '../match/adapters/match_adapter.dart';
import '../match/board_view.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../widgets/move_strip.dart';
import '../analysis/analysis.dart';
import '../app/telemetry.dart';
import 'history_screen.dart';
import '../ui/app_icon.dart';
import '../l10n/l10n.dart';

/// Revisión de una partida terminada: navegar jugada a jugada y exportar.
class ReviewScreen extends ConsumerStatefulWidget {
  final SavedGame game;
  const ReviewScreen({super.key, required this.game});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final List<BoardSnapshot> _snapshots;
  late final List<int> _toMove;
  BoardGame? _game;
  int _ply = 0;
  bool _flipped = false;
  GameAnalysis? _analysis;
  double? _progress; // análisis en curso
  AnalysisJob? _job;

  bool get _canAnalyse =>
      _cfg.kind != GameKind.chineseCheckers && widget.game.finished && widget.game.moves.isNotEmpty;

  MatchConfig get _cfg => widget.game.config;

  @override
  void initState() {
    super.initState();
    final adapter = MatchAdapter.create(_cfg);
    _snapshots = [adapter.snapshot()];
    _toMove = [adapter.toMove];
    for (final code in widget.game.moves) {
      if (!adapter.replay(code)) break;
      _snapshots.add(adapter.snapshot());
      _toMove.add(adapter.toMove);
    }
    _ply = _snapshots.length - 1;
    _flipped = _cfg.opponent != Opponent.local && _cfg.humanSeat == 1 && _cfg.kind != GameKind.chineseCheckers;
    _loadAnalysis();
  }

  /// Un análisis ya hecho se guarda en SQLite y no se repite.
  Future<void> _loadAnalysis() async {
    final id = widget.game.id;
    if (id == null || !_canAnalyse) return;
    final json = await ref.read(gameStoreProvider).loadAnalysis(id);
    if (json != null && mounted) setState(() => _analysis = GameAnalysis.fromJson(json));
  }

  @override
  void dispose() {
    _job?.cancel(); // salir de la pantalla también lo detiene
    super.dispose();
  }

  Future<void> _analyse() async {
    setState(() => _progress = 0);
    final job = GameAnalysis.start(_cfg, widget.game.moves, onProgress: (f) {
      if (mounted) setState(() => _progress = f);
    });
    _job = job;
    try {
      final a = await job.result;
      final id = widget.game.id;
      if (id != null) await ref.read(gameStoreProvider).saveAnalysis(id, a.toJson());
      if (mounted) setState(() => _analysis = a);
    } on AnalysisCancelled {
      // La persona lo detuvo: no es un error.
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Análisis tras la partida');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('No se pudo analizar la partida.'))));
      }
    } finally {
      _job = null;
      if (mounted) setState(() => _progress = null);
    }
  }

  Widget _analysisPanel(TableroColors c) {
    final a = _analysis;
    if (a == null) {
      if (!_canAnalyse) return const SizedBox.shrink();
      final p = _progress;
      return p == null
          ? OutlinedButton(onPressed: _analyse, child: Text(tr('Analizar la partida')))
          : Column(children: [
              LinearProgressIndicator(value: p),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(tr('Analizando… {pct} %', {'pct': (p * 100).round()}), style: TType.bodySm(c.inkMuted)),
                ),
                TextButton(onPressed: () => _job?.cancel(), child: Text(tr('Detener'))),
              ]),
            ]);
    }
    final i = _ply - 1;
    final log = widget.game.log;
    final note = i >= 0 && i < a.quality.length && i < log.length ? a.describe(i, log[i]) : null;
    final color = i >= 0 && i < a.quality.length
        ? switch (a.quality[i]) {
            MoveQuality.mistake => c.danger,
            MoveQuality.inaccuracy => c.accent,
            MoveQuality.good => c.inkMuted,
          }
        : c.inkMuted;
    return Column(
      children: [
        EvalChart(analysis: a, ply: _ply),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(note ?? tr('Mueve por la partida para ver cada jugada.'), style: TType.bodySm(color)),
              ),
            ),
            TextButton(onPressed: () => _go(a.keyMove + 1), child: Text(tr('Jugada clave'))),
          ],
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = TableroColors.of(context).withBoard(ref.read(settingsProvider).boardTheme);
    if (_game == null) {
      _game = BoardGame(colors: colors, onCellTap: (_) {})..dragEnabled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    } else {
      _game!.updateColors(colors);
    }
  }

  List<String> get _log {
    final spanish = ref.read(settingsProvider).spanishNotation && _cfg.kind == GameKind.chess;
    final log = widget.game.log.take(_ply).toList();
    return spanish ? [for (final m in log) spanishSan(m)] : log;
  }

  void _sync() {
    _game?.sync(MatchView.readOnly(
      config: _cfg,
      board: _snapshots[_ply],
      toMove: _toMove[_ply],
      moveLog: _log,
      flipped: _flipped,
    ));
  }

  void _go(int ply) {
    final next = ply.clamp(0, _snapshots.length - 1);
    if (next == _ply) return;
    setState(() => _ply = next);
    _sync();
  }

  Future<void> _export() async {
    final text = exportGame(widget.game);
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final format = _cfg.kind == GameKind.chess ? 'PGN' : 'PDN';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('{format} copiado al portapapeles', {'format': format}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    _game?.showCoordinates = ref.watch(settingsProvider).showCoordinates;
    final last = _snapshots.length - 1;
    final canExport = _cfg.kind != GameKind.chineseCheckers;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('Volver'),
                    icon: const AppIcon(AppIcons.back),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Revisión · {title}', {'title': _cfg.title}), style: TType.title(c.ink)),
                        Text(resultLine(widget.game), style: TType.bodySm(c.inkMuted)),
                      ],
                    ),
                  ),
                  if (canExport)
                    IconButton(
                      tooltip: tr('Copiar {format}', {'format': _cfg.kind == GameKind.chess ? 'PGN' : 'PDN'}),
                      icon: const AppIcon(AppIcons.copy),
                      onPressed: _export,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(aspectRatio: 1, child: GameWidget(game: _game!)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _ply == 0 ? tr('Posición inicial') : tr('Jugada {p0} de {p1}', {'p0': (_ply + 1) ~/ 2, 'p1': (last + 1) ~/ 2}),
                      style: TType.bodySm(c.inkMuted),
                    ),
                    const SizedBox(height: 8),
                    if (_cfg.kind != GameKind.chineseCheckers) MoveStrip(moves: _log),
                    const SizedBox(height: 8),
                    _analysisPanel(c),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(tooltip: tr('Inicio'), icon: const AppIcon(AppIcons.first), onPressed: _ply > 0 ? () => _go(0) : null),
                  IconButton(tooltip: tr('Anterior'), icon: const AppIcon(AppIcons.chevronLeft), onPressed: _ply > 0 ? () => _go(_ply - 1) : null),
                  IconButton(tooltip: tr('Siguiente'), icon: const AppIcon(AppIcons.chevronRight), onPressed: _ply < last ? () => _go(_ply + 1) : null),
                  IconButton(tooltip: tr('Final'), icon: const AppIcon(AppIcons.last), onPressed: _ply < last ? () => _go(last) : null),
                  IconButton(
                    tooltip: tr('Girar tablero'),
                    icon: const AppIcon(AppIcons.flip),
                    onPressed: _cfg.kind == GameKind.chineseCheckers
                        ? null
                        : () {
                            setState(() => _flipped = !_flipped);
                            _sync();
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
