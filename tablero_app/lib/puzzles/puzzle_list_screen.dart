import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import 'puzzles.dart';
import '../l10n/l10n.dart';

/// Todos los problemas, con los resueltos marcados.
class PuzzleListScreen extends ConsumerWidget {
  const PuzzleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final all = ref.watch(puzzlesProvider).valueOrNull ?? const <Puzzle>[];
    final progress = ref.watch(puzzleProgressProvider).valueOrNull ?? const PuzzleProgress();
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 720,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                  child: Row(
                    children: [
                      AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                      Expanded(child: Text(tr('Problemas'), style: TType.titleLg(c.ink))),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    tr(progress.currentStreak(now) == 1
                            ? '{solved} de {total} resueltos · racha de {n} día'
                            : '{solved} de {total} resueltos · racha de {n} días',
                        {'solved': progress.solved.length, 'total': all.length, 'n': progress.currentStreak(now)}),
                    style: TType.bodySm(c.inkMuted),
                  ),
                ),
              ),
              for (final (label, items) in [
                (tr('Ajedrez'), all.where((p) => !p.isDraughts).toList()),
                (tr('Damas'), all.where((p) => p.isDraughts).toList()),
              ]) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(label, style: TType.title(c.ink)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 76,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PuzzleTile(puzzle: items[i], index: i + 1, done: progress.solved.contains(items[i].id)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta del problema del día para Inicio.
class DailyPuzzleCard extends ConsumerWidget {
  const DailyPuzzleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final all = ref.watch(puzzlesProvider).valueOrNull;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final progress = ref.watch(puzzleProgressProvider).valueOrNull ?? const PuzzleProgress();
    final now = DateTime.now();
    final daily = dailyPuzzle(all, now);
    final done = progress.dailySolvedOn(now);
    final streak = progress.currentStreak(now);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/puzzles/${daily.id}?daily=1'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? c.brand : c.accent, borderRadius: BorderRadius.circular(12)),
                child: AppIcon(done ? AppIcons.check : AppIcons.hint, color: done ? c.brandInk : c.accentInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(done ? tr('Problema del día resuelto') : tr('Problema del día'), style: TType.title(c.ink)),
                    Text(
                      done
                          ? tr(streak == 1 ? 'Racha de {n} día. Vuelve mañana.' : 'Racha de {n} días. Vuelve mañana.',
                              {'n': streak})
                          : '${daily.title} · ${daily.sideText.toLowerCase()}'
                              '${streak > 0 ? tr(' · racha de {n}', {'n': streak}) : ''}',
                      style: TType.bodySm(c.inkMuted),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: () => context.push('/puzzles'), child: Text(tr('Todos'))),
            ],
          ),
        ),
      ),
    );
  }
}


class _PuzzleTile extends StatelessWidget {
  final Puzzle puzzle;
  final int index;
  final bool done;
  const _PuzzleTile({required this.puzzle, required this.index, required this.done});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    // M1/M2 = mate en 1/2; G = golpe de damas. Los puntos indican la dificultad.
    final tag = puzzle.isDraughts ? 'G' : 'M${puzzle.mateIn}';
    return Semantics(
      button: true,
      label: tr(done ? 'Problema {id}, {title}, resuelto' : 'Problema {id}, {title}', {'id': index, 'title': puzzle.title}),
      child: ExcludeSemantics(
        child: Material(
          color: done ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/puzzles/${puzzle.id}'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$index', style: TType.title(done ? c.brandInk : c.ink)),
                Text('$tag ${'•' * puzzle.rating}', style: TType.caption(done ? c.brandInk : c.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
