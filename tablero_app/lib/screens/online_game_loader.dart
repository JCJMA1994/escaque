import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../account/auth_service.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../online/online_repository.dart';
import '../l10n/l10n.dart';

/// Abre una partida online por su id (desde una notificación).
class OnlineGameLoader extends ConsumerStatefulWidget {
  final String gameId;
  const OnlineGameLoader({super.key, required this.gameId});

  @override
  ConsumerState<OnlineGameLoader> createState() => _OnlineGameLoaderState();
}

class _OnlineGameLoaderState extends ConsumerState<OnlineGameLoader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(onlineRepositoryProvider);
      final g = await repo.getGame(widget.gameId);
      final seat = g?.seatOf(repo.uid ?? '') ?? -1;
      if (g == null || seat < 0) {
        setState(() => _error = tr('Esa partida ya no está disponible.'));
        return;
      }
      openOnlineGame(ref, id: g.id, kind: g.kind, variantId: g.variantId, seat: seat);
      if (mounted) context.pushReplacement('/game');
    } on OnlineException catch (e) {
      // Sin sesión (p. ej. cerró sesión y tocó una notificación antigua).
      if (e.code == 'account_required' && mounted) {
        final route = await ref.read(authServiceProvider).nextStep('/online/game/${widget.gameId}');
        if (mounted) context.pushReplacement(route);
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('No se pudo abrir la partida. Revisa tu conexión.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TType.body(c.ink), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => context.go('/online'), child: Text(tr('Ir a mis partidas'))),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Fija la configuración de una partida online antes de navegar a `/game`.
void openOnlineGame(
  WidgetRef ref, {
  required String id,
  required GameKind kind,
  required String variantId,
  required int seat,
}) {
  ref.read(resumeGameProvider.notifier).state = null;
  ref.read(matchConfigProvider.notifier).state = MatchConfig(
    kind: kind,
    draughtsVariant: DraughtsVariant.all.firstWhere(
      (v) => v.id == variantId,
      orElse: () => DraughtsVariant.spanish,
    ),
    opponent: Opponent.online,
    humanSeat: seat,
    onlineGameId: id,
  );
}
