import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/auth_service.dart';
import '../ads/banner_slot.dart';
import '../app/metrics.dart';
import '../app/play_games.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../ui/app_icon.dart';
import '../ui/escaque_nav_bar.dart';
import '../ui/layout.dart';
import '../puzzles/puzzle_list_screen.dart';
import '../ui/piece_art.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import '../l10n/l10n.dart';

/// Inicio: Juegos, Historial y Ajustes. Barra inferior en teléfono y
/// navegación lateral en pantallas expandidas.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _destinations = [
    (AppIcons.home, 'Inicio'),
    (AppIcons.history, 'Historial'),
    (AppIcons.settings, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final wide = WindowSize.of(context) == WindowSize.expanded;
    final body = IndexedStack(
      index: _tab,
      children: const [_GamesTab(), SafeArea(child: HistoryTab()), SafeArea(child: SettingsTab())],
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: c.surface,
              indicatorColor: c.surfaceRaised,
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Image.asset('assets/icon/icon_full.png', width: 40, height: 40, semanticLabel: tr('Escaque')),
              ),
              destinations: [
                for (final (icon, label) in _destinations)
                  NavigationRailDestination(
                    icon: AppIcon(icon, color: c.inkMuted),
                    selectedIcon: AppIcon(icon, color: c.brand),
                    label: Text(tr(label)),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: c.line),
            Expanded(child: Column(children: [Expanded(child: SafeArea(left: false, child: body)), const BannerSlot()])),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerSlot(),
          EscaqueNavBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: _destinations,
          ),
        ],
      ),
    );
  }
}

class _GamesTab extends ConsumerWidget {
  const _GamesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final ongoing = ref.watch(inProgressProvider).valueOrNull;
    final size = WindowSize.of(context);
    final columns = size == WindowSize.compact ? 1 : 2;
    final games = [
      _GameCard(kind: GameKind.chess, name: 'Ajedrez', meta: tr('Leyes FIDE · 2 jugadores'), art: _ChessArt()),
      _GameCard(kind: GameKind.draughts, name: 'Damas', meta: tr('Internacional, inglesa y española'), art: _DraughtsArt()),
      _GameCard(kind: GameKind.chineseCheckers, name: 'Damas chinas', meta: tr('De 2 a 6 jugadores'), art: _StarArt()),
    ];
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _FeltHeader()),
        SliverPadding(
          padding: pagePadding(context, top: 20, bottom: 24),
          sliver: SliverToBoxAdapter(
            child: ContentWidth(
              maxWidth: 880,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ongoing != null) ...[
                    _ContinueCard(game: ongoing),
                    const SizedBox(height: 12),
                  ],
                  const _StatsConsentCard(),
                  const DailyPuzzleCard(),
                  const SizedBox(height: 24),
                  Text(tr('Juegos'), style: TType.title(c.ink)),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) {
                      const gap = 12.0;
                      final w = (box.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [for (final g in games) SizedBox(width: w, child: g)],
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push('/learn'),
                      child: Text(tr('¿Nuevo en estos juegos? Aprende a jugar')),
                    ),
                  ),
                  if (PlayGames.configured)
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(onPressed: PlayGames.showAchievements, child: Text(tr('Logros'))),
                        OutlinedButton(onPressed: PlayGames.showLeaderboards, child: Text(tr('Clasificaciones'))),
                      ],
                    ),
                  const SizedBox(height: 12),
                  const _OnlineCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La banda de fieltro: el único elemento llamativo de la pantalla.
class _FeltHeader extends StatelessWidget {
  const _FeltHeader();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    // Iconos de la barra de estado claros sobre el fieltro.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        color: c.felt,
        padding: EdgeInsets.fromLTRB(pagePadding(context).left, top + 28, pagePadding(context).right, 28),
        child: Stack(
          children: [
            // Damero apenas visible, como en el icono.
            Positioned.fill(child: CustomPaint(painter: _CheckerPainter(c.feltInk.withAlpha(14)))),
            ContentWidth(
              maxWidth: 880,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Escaque'), style: TType.display(c.feltInk)),
                        const SizedBox(height: 6),
                        Text(tr('Ajedrez y damas con las reglas de sus reglamentos oficiales.'),
                            style: TType.bodySm(c.feltInk.withAlpha(220))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const ExcludeSemantics(child: PieceIcon(PieceKind.knight, size: 64)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  final Color color;
  _CheckerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 28.0;
    final p = Paint()..color = color;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = (y % 2); x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.color != color;
}

class _ContinueCard extends ConsumerWidget {
  final SavedGame game;
  const _ContinueCard({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final cfg = game.config;
    final plies = game.moves.length;
    return Semantics(
      button: true,
      label: tr('Continuar partida de {p0}', {'p0': cfg.title.toLowerCase()}),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.brand, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            ref.read(resumeGameProvider.notifier).state = game;
            ref.read(matchConfigProvider.notifier).state = cfg;
            context.push('/game');
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(12)),
                  child: AppIcon(AppIcons.chevronRight, color: c.brandInk),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Continuar: {p0}', {'p0': cfg.title.toLowerCase()}), style: TType.title(c.ink)),
                      Text(tr('{subtitle} · jugada {p1}', {'subtitle': cfg.subtitle, 'p1': plies ~/ 2 + 1}), style: TType.bodySm(c.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameKind kind;
  final String name;
  final String meta;
  final Widget art;

  const _GameCard({required this.kind, required this.name, required this.meta, required this.art});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/new/${kind.name}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(dimension: 68, child: art),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TType.titleLg(c.ink)),
                    const SizedBox(height: 2),
                    Text(meta, style: TType.bodySm(c.inkMuted)),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevronRight, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineCard extends ConsumerWidget {
  const _OnlineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final username = ref.watch(usernameProvider);
    return Material(
      color: c.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/online'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              AppIcon(AppIcons.online, color: c.brand, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Jugar online con amigos'), style: TType.title(c.ink)),
                    Text(
                      username == null ? tr('Partidas por turnos con un código de invitación') : tr('Juegas como @{username}', {'username': username}),
                      style: TType.bodySm(c.inkMuted),
                    ),
                  ],
                ),
              ),
              AppIcon(AppIcons.chevronRight, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChessArt extends StatelessWidget {
  const _ChessArt();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Stack(
      children: [
        GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 4; i++) ColoredBox(color: (i ~/ 2 + i % 2).isEven ? c.boardLight : c.boardDark),
          ],
        ),
        const Center(child: PieceIcon(PieceKind.knight, size: 52)),
      ],
    );
  }
}

class _DraughtsArt extends StatelessWidget {
  const _DraughtsArt();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    Widget disc(Color fill) => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: c.pieceOutline, width: 1.5),
          ),
        );
    return ColoredBox(
      color: c.boardDark,
      child: Stack(
        children: [
          Positioned(left: 8, top: 8, child: disc(c.pieceDark)),
          Positioned(right: 8, bottom: 8, child: disc(c.pieceLight)),
        ],
      ),
    );
  }
}

class _StarArt extends StatelessWidget {
  const _StarArt();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return ColoredBox(
      color: c.boardLight,
      child: Center(child: AppIcon(AppIcons.star, size: 44, color: c.players[0])),
    );
  }
}


/// Pregunta única por las estadísticas de uso (consentimiento previo y expreso).
/// Desaparece al responder; la respuesta se cambia en Ajustes → Privacidad.
class _StatsConsentCard extends StatefulWidget {
  const _StatsConsentCard();

  @override
  State<_StatsConsentCard> createState() => _StatsConsentCardState();
}

class _StatsConsentCardState extends State<_StatsConsentCard> {
  bool _hidden = !Metrics.needsAnswer;

  Future<void> _answer(bool yes) async {
    setState(() => _hidden = true);
    await Metrics.setEnabled(yes);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final c = TableroColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.lineStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('¿Nos ayudas a mejorar Escaque?'), style: TType.title(c.ink)),
            const SizedBox(height: 6),
            Text(
              tr('Con tu permiso, contamos qué juegos y funciones se usan (por ejemplo, partidas terminadas o problemas resueltos), sin tu nombre, correo ni cuenta. Puedes cambiarlo cuando quieras en Ajustes → Privacidad.'),
              style: TType.bodySm(c.inkMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(onPressed: () => _answer(true), child: Text(tr('Sí, acepto'))),
                const SizedBox(width: 12),
                TextButton(onPressed: () => _answer(false), child: Text(tr('No, gracias'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
