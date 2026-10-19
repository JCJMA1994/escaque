import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../data/game_store.dart';
import '../match/match_config.dart';
import '../ui/layout.dart';
import '../ui/app_icon.dart';
import '../l10n/l10n.dart';

String formatDate(DateTime d) {
  const es = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour.toString().padLeft(2, '0'), m = d.minute.toString().padLeft(2, '0');
  return L10n.lang == 'en'
      ? '${en[d.month - 1]} ${d.day}, ${d.year}, $h:$m'
      : '${d.day} ${es[d.month - 1]} ${d.year}, $h:$m';
}

String resultLine(SavedGame g) {
  // Los motivos se guardan en español (motor, servidor): se traducen al mostrarlos.
  if (g.winner == null) return tr('Tablas por {reason}', {'reason': tr(g.reason ?? 'acuerdo')});
  return tr('{winner} por {reason}', {'winner': g.config.winnerText(g.winner!), 'reason': tr(g.reason ?? 'final de partida')});
}

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final games = ref.watch(historyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Text(tr('Historial'), style: TType.display(c.ink)),
        ),
        Expanded(
          child: games.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('No se pudo leer el historial: {e}', {'e': e}), style: TType.body(c.ink)),
              ),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      tr('Las partidas que termines aparecerán aquí, listas para revisarlas o exportarlas.'),
                      style: TType.body(c.inkMuted),
                    ),
                  )
                : ListView.separated(
                    padding: pagePadding(context, bottom: 24),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => ContentWidth(
                      maxWidth: 720,
                      child: i == 0 ? _Stats(games: list) : _HistoryTile(game: list[i - 1]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final SavedGame game;
  const _HistoryTile({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    return Dismissible(
      key: ValueKey(game.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(20)),
        child: Text(tr('Borrar'), style: TType.label(c.bg)),
      ),
      onDismissed: (_) async {
        await ref.read(gameStoreProvider).delete(game.id!);
        ref.invalidate(historyProvider);
      },
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/review', extra: game),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(game.config.title, style: TType.title(c.ink)),
                      const SizedBox(height: 2),
                      Text(resultLine(game), style: TType.bodySm(c.ink)),
                      Text(
                        tr('{p0} · {p1} jugadas', {'p0': formatDate(game.updatedAt), 'p1': (game.moves.length + 1) ~/ 2}),
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
      ),
    );
  }
}


/// Resumen por juego desde tu punto de vista: victorias, tablas y derrotas
/// contra la IA y online (las partidas locales no tienen «tú»).
class _Stats extends StatelessWidget {
  final List<SavedGame> games;
  const _Stats({required this.games});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final rows = <(String, int, int, int)>[];
    for (final kind in GameKind.values) {
      var w = 0, d = 0, l = 0;
      for (final g in games) {
        final cfg = g.config;
        if (cfg.kind != kind || cfg.opponent == Opponent.local || !g.finished) continue;
        if (g.winner == null) {
          d++;
        } else if (g.winner == cfg.humanSeat) {
          w++;
        } else {
          l++;
        }
      }
      if (w + d + l > 0) {
        rows.add((switch (kind) { GameKind.chess => tr('Ajedrez'), GameKind.draughts => tr('Damas'), _ => tr('Damas chinas') }, w, d, l));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    Widget num(String label, int n, Color color) => Expanded(
          child: Column(
            children: [
              Text('$n', style: TType.titleLg(color)),
              Text(label, style: TType.caption(c.inkMuted)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Tu balance'), style: TType.title(c.ink)),
          const SizedBox(height: 4),
          Text(tr('Contra la IA y online'), style: TType.bodySm(c.inkMuted)),
          for (final (name, w, d, l) in rows) ...[
            const SizedBox(height: 12),
            Text(name, style: TType.label(c.ink)),
            const SizedBox(height: 6),
            Semantics(
              label: tr('{name}: {w} victorias, {d} tablas, {l} derrotas', {'name': name, 'w': w, 'd': d, 'l': l}),
              child: ExcludeSemantics(
                child: Row(children: [num(tr('Victorias'), w, c.brand), num(tr('Tablas'), d, c.ink), num(tr('Derrotas'), l, c.danger)]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
