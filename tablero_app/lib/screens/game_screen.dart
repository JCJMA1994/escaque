import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../ads/ads_service.dart';
import '../app/env.dart';
import '../app/metrics.dart';
import '../app/play_games.dart';
import '../app/settings.dart';
import '../app/store_prompts.dart';
import '../app/sounds.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../board/board_game.dart';
import '../match/match_config.dart';
import '../online/online_repository.dart';
import '../online/phrases.dart';
import '../match/match_controller.dart';
import '../widgets/move_strip.dart';
import 'rules_sheet.dart';
import '../widgets/player_bar.dart';
import 'result_screen.dart';
import '../ui/app_icon.dart';
import '../ui/piece_art.dart';
import '../l10n/l10n.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  BoardGame? _game;
  bool _resultShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = TableroColors.of(context);
    if (_game == null) {
      _game = BoardGame(
        colors: _boardColors(colors, ref.read(settingsProvider).boardTheme),
        onCellTap: (cell) => ref.read(matchProvider.notifier).tapCell(cell),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _game!.sync(ref.read(matchProvider));
      });
    } else {
      _game!.updateColors(_boardColors(colors, ref.read(settingsProvider).boardTheme));
    }
  }

  TableroColors? _lastBase;
  BoardTheme? _lastTheme;
  TableroColors? _lastBoard;

  /// Los colores con el tema de tablero, reutilizando la misma instancia
  /// mientras nada cambie (el tablero se reinstala solo si cambia).
  TableroColors _boardColors(TableroColors base, BoardTheme theme) {
    if (identical(base, _lastBase) && theme == _lastTheme && _lastBoard != null) return _lastBoard!;
    _lastBase = base;
    _lastTheme = theme;
    return _lastBoard = base.withBoard(theme);
  }

  bool _muteEmotes = false;

  /// Frase nueva del rival: se muestra un momento y TalkBack la lee.
  void _maybeShowEmote(MatchView? prev, MatchView next) {
    if (prev == null || _muteEmotes || !ref.read(settingsProvider).showPhrases || next.emotes.isEmpty) return;
    final last = next.emotes.last;
    if (last.seat == next.config.humanSeat) return;
    final before = prev.emotes.isEmpty ? null : prev.emotes.last;
    if (before != null && before.at == last.at && before.seat == last.seat) return;
    final who = next.nameOf(last.seat);
    final text = '$who: ${phraseText(last.phrase)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)),
    );
    if (MediaQuery.of(context).accessibleNavigation) {
      SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
    }
  }

  Future<void> _declineChallenge(MatchView v) async {
    final id = v.config.onlineGameId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Rechazar el reto?')),
        content: Text(tr('La partida se cancela sin ganador ni valoración, y se avisa a quien te retó.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Volver'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Rechazar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(onlineRepositoryProvider).declineChallenge(id);
      router.pop();
    } on OnlineException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openPhrases(MatchView v) async {
    final c = TableroColors.of(context);
    final id = v.config.onlineGameId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Frases'), style: TType.title(c.ink)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in phraseIds)
                      ActionChip(label: Text(phraseText(p)), onPressed: () => Navigator.of(context).pop(p)),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Silenciar las frases del rival en esta partida'), style: TType.body(c.ink)),
                  value: _muteEmotes,
                  onChanged: (on) {
                    setState(() => _muteEmotes = on);
                    setSheet(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(onlineRepositoryProvider).emote(id, picked);
    } on OnlineException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _onChange(MatchView? prev, MatchView next) {
    _game?.sync(next);
    _maybeShowEmote(prev, next);
    _playFeedback(prev, next);
    _announce(prev, next);
    if (next.onlineError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.onlineError!)));
    }
    if (next.pendingPromotion != null && prev?.pendingPromotion == null) {
      _askPromotion();
    }
    if (next.pendingRoute != null && prev?.pendingRoute == null) {
      _askRoute(next.pendingRoute!.routes);
    }
    if (next.result != null && !_resultShown) {
      _resultShown = true;
      ref.read(adsServiceProvider).gameFinished();
      final r = next.result!;
      final won = r.winner != null && r.winner == next.config.humanSeat && next.config.opponent != Opponent.local;
      final cfg = next.config;
      Metrics.gameEnd(
        kind: cfg.kind.name,
        mode: cfg.opponent.name,
        result: cfg.opponent == Opponent.local
            ? 'end'
            : r.winner == null
                ? 'draw'
                : (won ? 'win' : 'loss'),
        plies: next.moveLog.length,
      );
      if (won) StorePrompts.registerWin();
      // Logros de Play Games.
      if (won) {
        PlayGames.unlock(switch (cfg.kind) {
          GameKind.chess => PlayAchievement.firstWinChess,
          GameKind.draughts => PlayAchievement.firstWinDraughts,
          GameKind.chineseCheckers => PlayAchievement.firstWinChineseCheckers,
        });
        if (cfg.opponent == Opponent.ai && cfg.aiLevel == 5) PlayGames.level5Win();
      }
      if (cfg.isOnline) PlayGames.unlock(PlayAchievement.firstOnlineGame);
      final summary = MatchSummary(
        game: SavedGame(
          config: next.config,
          moves: next.moveCodes,
          log: next.moveLog,
          finished: true,
          winner: r.winner,
          reason: r.reason,
          startedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        config: next.config,
        headline: r.isDraw ? tr('Tablas') : next.config.winnerText(r.winner!),
        reason: r.reason,
        plies: next.moveLog.length,
        clocks: next.clocks,
      );
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) context.pushReplacement('/result', extra: summary);
      });
    }
  }

  /// Con TalkBack activo, cada jugada (propia o del rival) se anuncia.
  void _announce(MatchView? prev, MatchView next) {
    if (prev == null || next.board.version <= prev.board.version) return;
    final text = next.spokenMove;
    if (text == null || !MediaQuery.of(context).accessibleNavigation) return;
    SemanticsService.sendAnnouncement(View.of(context), text, TextDirection.ltr);
  }

  void _playFeedback(MatchView? prev, MatchView next) {
    if (prev == null || !ref.read(settingsProvider).sound) return;
    final finished = prev.result == null && next.result != null;
    final moved = next.board.version > prev.board.version;
    if (!moved && !finished) return;
    final b = next.board;
    final sound = finished
        ? Sounds.end
        : b.checkCell != null
            ? Sounds.check
            : b.lastCaptured.isNotEmpty
                ? Sounds.capture
                : Sounds.move;
    Sounds.play(sound);
    if (moved) HapticFeedback.selectionClick();
  }

  bool _hintBusy = false;

  /// Pista a cambio de un anuncio recompensado. Si no hay anuncio
  /// disponible, la pista se da igual.
  Future<void> _hint() async {
    if (_hintBusy) return;
    final c = TableroColors.of(context);
    final ads = ref.read(adsServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (ads.rewardedAvailable) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(tr('Ver una pista'), style: TType.title(c.ink)),
          content: Text(tr('Mira un anuncio corto y te marcamos una buena jugada.'), style: TType.body(c.ink)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancelar'))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Ver anuncio'))),
          ],
        ),
      );
      if (ok != true) return;
      final earned = await ads.showRewarded();
      if (earned == false) {
        messenger.showSnackBar(SnackBar(content: Text(tr('El anuncio se cerró antes de terminar. No hay pista esta vez.'))));
        return;
      }
    }
    setState(() => _hintBusy = true);
    final shown = await ref.read(matchProvider.notifier).showHint();
    if (mounted) setState(() => _hintBusy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(shown
          ? tr('Pista marcada: toca la casilla resaltada para jugarla.')
          : tr('No se pudo calcular una pista ahora.')),
    ));
  }

  /// Damas: dos capturas distintas acaban en la misma casilla.
  Future<void> _askRoute(List<String> routes) async {
    final c = TableroColors.of(context);
    final controller = ref.read(matchProvider.notifier);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: c.surface,
        title: Text(tr('¿Por dónde capturas?'), style: TType.title(c.ink)),
        children: [
          for (var i = 0; i < routes.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(i),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Text(routes[i], style: TType.body(c.ink)),
            ),
        ],
      ),
    );
    if (picked == null) {
      controller.cancelRoute();
    } else {
      controller.chooseRoute(picked);
    }
  }

  Future<void> _askPromotion() async {
    final c = TableroColors.of(context);
    final controller = ref.read(matchProvider.notifier);
    final white = ref.read(matchProvider).toMove == 0;
    final options = [
      (Piece.queen, PieceKind.queen, tr('Dama')),
      (Piece.rook, PieceKind.rook, tr('Torre')),
      (Piece.bishop, PieceKind.bishop, tr('Alfil')),
      (Piece.knight, PieceKind.knight, tr('Caballo')),
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(tr('Coronar'), style: TType.title(c.ink)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (type, kind, name) in options)
              Semantics(
                label: name,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(type),
                  child: Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.boardLight, borderRadius: BorderRadius.circular(12)),
                    child: PieceIcon(kind, white: white, size: 48),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null) {
      controller.cancelPromotion();
    } else {
      controller.choosePromotion(picked);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final c = TableroColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title, style: TType.title(c.ink)),
        content: Text(body, style: TType.body(c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancelar'))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _offerDraw(MatchView v) async {
    final controller = ref.read(matchProvider.notifier);
    if (v.config.isOnline) {
      controller.offerDraw(accepted: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Oferta de tablas enviada a tu rival.'))),
      );
      return;
    }
    if (v.config.opponent == Opponent.local) {
      final ok = await _confirm(tr('¿Tablas?'), tr('Pasa el teléfono a tu rival para que acepte o rechace.'), tr('Aceptar tablas'));
      if (ok) controller.offerDraw(accepted: true);
      return;
    }
    if (!controller.offerDraw(accepted: false) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('La IA rechaza las tablas. Solo acepta las que da el reglamento.'))),
      );
    }
  }

  /// Sale guardando: la partida queda en «Continuar» en Inicio.
  Future<void> _leave() async {
    await ref.read(matchProvider.notifier).flush();
    if (mounted) context.go('/');
  }

  Future<void> _resign() async {
    final ok = await _confirm(tr('¿Rendirse?'), tr('La partida se dará por perdida.'), tr('Rendirse'));
    if (ok) ref.read(matchProvider.notifier).resign();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MatchView>(matchProvider, _onChange);
    final v = ref.watch(matchProvider);
    final settings = ref.watch(settingsProvider);
    final c = TableroColors.of(context);
    _game
      ?..showCoordinates = settings.showCoordinates
      ..dragEnabled = settings.dragPieces
      ..reduceMotion = MediaQuery.disableAnimationsOf(context)
      ..updateColors(_boardColors(c, settings.boardTheme));
    final log = v.config.kind == GameKind.chess && settings.spanishNotation
        ? [for (final m in v.moveLog) spanishSan(m)]
        : v.moveLog;
    final cfg = v.config;
    final isStar = cfg.kind == GameKind.chineseCheckers;

    // Jugador de abajo: la persona (o blancas en local, salvo tablero girado).
    final bottom = v.flipped ? 1 : 0;
    final top = 1 - bottom;

    String status(int player) {
      if (v.result != null) return tr('Partida terminada');
      if (v.toMove != player) return cfg.kind == GameKind.chess ? (player == 0 ? tr('Blancas') : tr('Negras')) : tr('Esperando');
      if (v.aiThinking) return tr('Pensando…');
      if (v.waitingForOpponent) return tr('Esperando rival');
      return cfg.isHuman(player) ? tr('Tu turno') : tr('Su turno');
    }

    Widget bar(int player) => PlayerBar(
          name: v.nameOf(player),
          subtitle: v.playerRatings == null ? status(player) : '${status(player)} · ${v.playerRatings![player]}',
          active: v.toMove == player && v.result == null,
          clock: v.clocks?[player],
          avatarColor: isStar ? c.players[player] : null,
        );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          AppIconButton(icon: AppIcons.back, tooltip: tr('Salir'), onPressed: _leave),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cfg.title, style: TType.title(c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(cfg.subtitle, style: TType.bodySm(c.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          AppIconButton(icon: AppIcons.rules, tooltip: tr('Reglas'), onPressed: () => showRulesSheet(context, cfg)),
          if (!isStar)
            AppIconButton(
              icon: AppIcons.flip,
              tooltip: tr('Girar tablero'),
              onPressed: ref.read(matchProvider.notifier).flip,
            ),
        ],
      ),
    );

    final board = AspectRatio(
      aspectRatio: 1,
      child: Semantics(
        label: tr('Tablero de {p0}', {'p0': cfg.title.toLowerCase()}),
        child: GameWidget(game: _game!),
      ),
    );

    final banners = <Widget>[
      if (v.waitingForOpponent) _WaitingBanner(code: v.onlineCode),
      if (v.canDeclineChallenge) _ChallengeBanner(onDecline: () => _declineChallenge(v)),
      if (v.drawOffered)
        _DrawOfferBanner(
          onAccept: () => ref.read(matchProvider.notifier).respondToDraw(accept: true),
          onDecline: () => ref.read(matchProvider.notifier).respondToDraw(accept: false),
        ),
      if (v.mustCapture && v.humanToMove)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              AppIcon(AppIcons.info, color: c.brand, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cfg.draughtsVariant.captureRule == CaptureRule.free
                      ? tr('Debes capturar. Puedes elegir la secuencia.')
                      : tr('Debes capturar. Solo valen las secuencias que toman más piezas.'),
                  style: TType.bodySm(c.ink),
                ),
              ),
            ],
          ),
        ),
    ];

    final starBars = SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cfg.playerCount,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 180, child: bar(i)),
      ),
    );

    final actions = _ActionBar(
      canUndo: v.canUndo,
      showDraw: !isStar && !v.myDrawOfferPending && !v.waitingForOpponent,
      canHint: v.humanToMove && cfg.opponent == Opponent.ai && !_hintBusy,
      onHint: _hint,
      onUndo: ref.read(matchProvider.notifier).undo,
      onDraw: () => _offerDraw(v),
      onResign: _resign,
      onChat: cfg.isOnline && !v.waitingForOpponent ? () => _openPhrases(v) : null,
    );

    // Atrás del sistema (gesto predictivo de Android 16 incluido): pasa por
    // _leave para terminar de guardar antes de salir.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Dos columnas en tablet o en horizontal: el tablero usa toda la
            // altura y la información va al lado.
            final twoPane = box.maxWidth >= 840 || (box.maxWidth > box.maxHeight && box.maxWidth >= 600);
            if (!twoPane) {
              return Column(
                children: [
                  header,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          if (isStar) starBars else bar(top),
                          const SizedBox(height: 12),
                          Expanded(child: Center(child: board)),
                          const SizedBox(height: 12),
                          ...banners,
                          if (!isStar) ...[
                            bar(bottom),
                            const SizedBox(height: 8),
                            MoveStrip(moves: log),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions,
                ],
              );
            }
            final panelWidth = box.maxWidth >= 1100 ? 400.0 : 340.0;
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: board),
                  ),
                ),
                SizedBox(
                  width: panelWidth,
                  child: Column(
                    children: [
                      header,
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            if (isStar)
                              for (var i = 0; i < cfg.playerCount; i++) ...[bar(i), const SizedBox(height: 8)]
                            else ...[
                              bar(top),
                              const SizedBox(height: 8),
                              bar(bottom),
                            ],
                            const SizedBox(height: 16),
                            ...banners,
                            if (!isStar) ...[
                              Text(tr('Jugadas'), style: TType.caption(c.inkMuted)),
                              const SizedBox(height: 8),
                              MoveList(moves: log),
                            ],
                          ],
                        ),
                      ),
                      actions,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool canUndo;
  final bool showDraw;
  final bool canHint;
  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onDraw;
  final VoidCallback onResign;
  final VoidCallback? onChat;

  const _ActionBar({
    this.onChat,
    required this.canUndo,
    required this.showDraw,
    required this.canHint,
    required this.onHint,
    required this.onUndo,
    required this.onDraw,
    required this.onResign,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    Widget action(AppIcons icon, String label, VoidCallback? onTap, {Color? color}) {
      final fg = onTap == null ? c.inkMuted.withAlpha(110) : (color ?? c.ink);
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, color: fg, size: 22),
                const SizedBox(height: 4),
                Text(label, style: TType.caption(fg)),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      child: Row(
        children: [
          action(AppIcons.undo, tr('Deshacer'), canUndo ? onUndo : null),
          action(AppIcons.hint, tr('Pista'), canHint ? onHint : null),
          if (showDraw) action(AppIcons.draw, tr('Tablas'), onDraw),
          if (onChat != null) action(AppIcons.chat, tr('Frases'), onChat),
          action(AppIcons.resign, tr('Rendirse'), onResign, color: c.danger),
        ],
      ),
    );
  }
}


class _WaitingBanner extends StatelessWidget {
  final String? code;
  const _WaitingBanner({required this.code});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Esperando a tu rival'), style: TType.label(c.ink)),
                Text(tr('Comparte el enlace o el código para que se una:'), style: TType.bodySm(c.inkMuted)),
                const SizedBox(height: 4),
                Text(code ?? '······', style: TType.clock(c.ink)),
              ],
            ),
          ),
          if (code != null)
            IconButton(
              tooltip: tr('Copiar enlace de invitación'),
              icon: const AppIcon(AppIcons.copy),
              onPressed: () async {
                Metrics.onlineInvite();
                await Clipboard.setData(ClipboardData(
                    text: tr('Juega conmigo en Escaque: {p0} (código {code})', {'p0': AppEnv.inviteLink(code!), 'code': code})));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Invitación copiada: pégala en un chat'))),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _DrawOfferBanner extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _DrawOfferBanner({required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: Text(tr('Tu rival ofrece tablas'), style: TType.label(c.ink))),
          TextButton(onPressed: onDecline, child: Text(tr('Rechazar'))),
          TextButton(onPressed: onAccept, child: Text(tr('Aceptar'))),
        ],
      ),
    );
  }
}


/// Reto de un amigo: se puede rechazar antes de tu primera jugada.
class _ChallengeBanner extends StatelessWidget {
  final VoidCallback onDecline;
  const _ChallengeBanner({required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text(tr('Te han retado. ¿No quieres jugar?'), style: TType.bodySm(c.ink))),
        TextButton(onPressed: onDecline, child: Text(tr('Rechazar reto'))),
      ]),
    );
  }
}
