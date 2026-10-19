import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ads/ads_service.dart';
import '../app/play_games.dart';
import '../purchases/purchases.dart';
import '../online/online_repository.dart';
import 'online_game_loader.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../match/match_config.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

/// Datos que la pantalla de partida pasa al resultado.
class MatchSummary {
  final MatchConfig config;
  final String headline;
  final String reason;
  final int plies;
  final List<Duration>? clocks;

  /// La partida completa, para revisarla.
  final SavedGame game;

  const MatchSummary({
    required this.game,
    required this.config,
    required this.headline,
    required this.reason,
    required this.plies,
    this.clocks,
  });
}

class ResultScreen extends ConsumerWidget {
  final MatchSummary summary;
  const ResultScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El intersticial solo aparece aquí, entre partidas, y con frecuencia limitada.
    Future<void> thenGo(FutureOr<void> Function() navigate) async {
      await ref.read(adsServiceProvider).maybeShowInterstitial();
      if (context.mounted) await navigate();
    }

    final c = TableroColors.of(context);
    final cfg = summary.config;
    Widget row(String k, String v, {bool mono = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k, style: TType.bodySm(c.inkMuted)),
              Text(v, style: mono ? TType.notation(c.ink) : TType.label(c.ink).copyWith(fontSize: 14)),
            ],
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(summary.headline, style: TType.display(c.ink), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(tr('por {reason}', {'reason': tr(summary.reason)}), style: TType.body(c.inkMuted), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    row(tr('Juego'), cfg.title),
                    Divider(height: 1, color: c.line),
                    row(tr('Rival'), switch (cfg.opponent) {
                      Opponent.ai => 'IA',
                      Opponent.local => tr('Local'),
                      Opponent.online => tr('Online'),
                    }),
                    Divider(height: 1, color: c.line),
                    row(tr('Jugadas'), '${(summary.plies + 1) ~/ 2}', mono: true),
                    if (cfg.clock != null) ...[
                      Divider(height: 1, color: c.line),
                      row(tr('Ritmo'), cfg.clock!.label, mono: true),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => thenGo(() async {
                    if (!cfg.isOnline) {
                      context.pushReplacement('/game');
                      return;
                    }
                    // Online: misma pareja, colores cambiados, sin código.
                    PlayGames.unlock(PlayAchievement.firstRematch);
                    try {
                      final r = await ref.read(onlineRepositoryProvider).rematch(cfg.onlineGameId!);
                      openOnlineGame(ref, id: r.id, kind: cfg.kind, variantId: cfg.draughtsVariant.id, seat: r.seat);
                      if (context.mounted) context.pushReplacement('/game');
                    } on OnlineException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  }),
                  child: Text(tr('Revancha')),
                ),
              ),
              // Tras un intersticial, la salida: quitar anuncios (solo si no se compró).
              if (!ref.watch(adFreeProvider.select((s) => s.adFree)) &&
                  ref.watch(adFreeProvider.select((s) => s.price)) != null)
                TextButton(
                  onPressed: () => context.push('/remove-ads'),
                  child: Text(tr('¿Sin anuncios? Quítalos con un pago único')),
                ),
              if (cfg.isOnline) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => thenGo(() => context.pushReplacement('/online')),
                    child: Text(tr('Otra partida online')),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.push('/review', extra: summary.game),
                  child: Text(tr('Revisar partida')),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => thenGo(() => context.go('/')),
                  child: Text(tr('Volver al inicio')),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
