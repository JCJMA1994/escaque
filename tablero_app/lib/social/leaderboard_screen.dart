import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../l10n/l10n.dart';
import '../online/online_repository.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../widgets/segmented.dart';

final myRatingsProvider = StreamProvider.autoDispose<Map<String, ({int rating, int games, bool provisional})>>(
    (ref) => ref.watch(onlineRepositoryProvider).myRatings());

final leaderboardProvider = FutureProvider.autoDispose.family<List<({String username, int rating, int games})>, String>(
    (ref, key) => ref.watch(onlineRepositoryProvider).leaderboard(key));

String ratingKeyName(String key) => switch (key) {
      'chess' => tr('Ajedrez'),
      'draughts_international' => tr('Damas internacionales'),
      'draughts_english' => tr('Damas inglesas'),
      _ => tr('Damas españolas'),
    };

/// Tus valoraciones y las 100 mejores de cada juego (se actualizan a diario).
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _key = 'chess';

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final mine = ref.watch(myRatingsProvider).valueOrNull ?? const {};
    final board = ref.watch(leaderboardProvider(_key));
    final me = mine[_key];
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(children: [
                  AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                  Expanded(child: Text(tr('Clasificación'), style: TType.titleLg(c.ink))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Segmented<String>(
                  semanticLabel: tr('Juego'),
                  value: _key,
                  options: [
                    ('chess', tr('Ajedrez')),
                    ('draughts_spanish', tr('Española')),
                    ('draughts_international', tr('Internacional')),
                    ('draughts_english', tr('Inglesa')),
                  ],
                  onChanged: (k) => setState(() => _key = k),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    me == null
                        ? tr('Aún no tienes valoración en {game}. Juega partidas valoradas con tus amigos.',
                            {'game': ratingKeyName(_key)})
                        : me.provisional
                            ? tr('Tu valoración: {r} (provisional, {n} partidas)', {'r': me.rating, 'n': me.games})
                            : tr('Tu valoración: {r} ({n} partidas)', {'r': me.rating, 'n': me.games}),
                    style: TType.body(c.ink),
                  ),
                ),
              ),
              board.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('No se pudo cargar la clasificación.'), style: TType.body(c.ink)),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(tr('Todavía no hay nadie en la clasificación: hacen falta 5 partidas valoradas.'),
                            style: TType.bodySm(c.inkMuted)),
                      )
                    : Column(children: [
                        for (final (i, e) in [for (var i = 0; i < list.length; i++) (i, list[i])])
                          ListTile(
                            dense: true,
                            leading: SizedBox(width: 32, child: Text('${i + 1}', style: TType.label(c.inkMuted))),
                            title: Text('@${e.username}', style: TType.label(c.ink)),
                            trailing: Text('${e.rating}', style: TType.notation(c.ink)),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
