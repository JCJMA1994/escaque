import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../account/auth_service.dart';
import '../app/metrics.dart';
import '../app/remote_flags.dart';
import '../app/theme.dart';
import '../match/match_config.dart';
import '../online/api_client.dart';
import '../online/online_repository.dart';
import '../online/push_service.dart';
import 'online_game_loader.dart';
import '../widgets/segmented.dart';
import '../social/friends_screen.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

final _myGamesProvider = StreamProvider.autoDispose<List<OnlineGame>>(
  (ref) => ref.watch(onlineRepositoryProvider).myGames(),
);

/// Partidas online por turnos con amigos: crear y compartir un código, unirse
/// con un código y retomar las partidas abiertas.
class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  final _code = TextEditingController();
  GameKind _kind = GameKind.chess;
  DraughtsVariant _variant = DraughtsVariant.spanish;
  int _seat = 0;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on OnlineException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(tr('No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open({required String id, required GameKind kind, required String variantId, required int seat}) async {
    await _maybeAskForNotifications();
    if (!mounted) return;
    openOnlineGame(ref, id: id, kind: kind, variantId: variantId, seat: seat);
    context.push('/game');
  }

  /// Una sola vez, en el momento en que tiene sentido: al empezar a jugar online.
  Future<void> _maybeAskForNotifications() async {
    final push = ref.read(pushServiceProvider);
    try {
      if (!await push.shouldAsk() || !mounted) return;
      final c = TableroColors.of(context);
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(tr('¿Te avisamos cuando te toque?'), style: TType.title(c.ink)),
          content: Text(
            tr('Las partidas online son por turnos. Te enviaremos un aviso cuando tu rival mueva, se una o proponga tablas.'),
            style: TType.body(c.ink),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Ahora no'))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Avisarme'))),
          ],
        ),
      );
      if (yes == true) await push.requestPermission();
    } catch (_) {
      // Sin permiso se puede jugar igual.
    }
  }

  Future<void> _create() => _run(() async {
        final g = await ref.read(onlineRepositoryProvider).create(
              kind: _kind,
              variantId: _variant.id,
              seat: _seat,
            );
        if (mounted) await _open(id: g.id, kind: _kind, variantId: _variant.id, seat: _seat);
      });

  Future<void> _join() => _run(() async {
        final code = _code.text.trim();
        if (code.length != 6) throw OnlineException(tr('El código tiene 6 caracteres.'));
        final j = await ref.read(onlineRepositoryProvider).joinByCode(code);
        Metrics.onlineJoin(via: 'code');
        if (mounted) await _open(id: j.id, kind: j.kind, variantId: j.variantId, seat: j.seat);
      });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final ready = ref.watch(firebaseReadyProvider) && ApiClient.configured;
    final flags = RemoteFlagsService.flags.value;
    final account = ref.watch(accountStatusProvider);
    final username = ref.watch(usernameProvider);

    Widget section(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TType.caption(c.inkMuted)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    final field = InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.lineStrong, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.lineStrong, width: 1.5),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('Volver'),
                    icon: const AppIcon(AppIcons.back),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  Text(tr('Online'), style: TType.titleLg(c.ink)),
                ],
              ),
            ),
            Expanded(
              child: ready && !flags.onlineEnabled
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr(flags.onlineMessage), style: TType.body(c.ink)),
                    )
                  : ready && account != AccountStatus.ready
                  ? _AccountGate(status: account)
                  : !ready
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr('El modo online no está configurado en esta compilación. Sigue GUIA_CONFIGURACION.md (Firebase y servidor).'),
                        style: TType.body(c.ink),
                      ),
                    )
                  : Theme(
                      data: Theme.of(context).copyWith(inputDecorationTheme: field),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Text(tr('Juegas como @{username}. Cámbialo en Ajustes → Cuenta.', {'username': username ?? ''}),
                                style: TType.bodySm(c.inkMuted)),
                          ),
                          const _SocialRow(),
                          const SizedBox(height: 24),
                          section(
                            tr('Crear partida'),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Segmented<GameKind>(
                                  semanticLabel: tr('Juego'),
                                  value: _kind,
                                  onChanged: (k) => setState(() => _kind = k),
                                  options: [
                                    (GameKind.chess, tr('Ajedrez')),
                                    (GameKind.draughts, tr('Damas')),
                                    (GameKind.chineseCheckers, tr('Chinas')),
                                  ],
                                ),
                                if (_kind == GameKind.draughts) ...[
                                  const SizedBox(height: 8),
                                  Segmented<DraughtsVariant>(
                                    semanticLabel: tr('Variante'),
                                    value: _variant,
                                    onChanged: (v) => setState(() => _variant = v),
                                    options: [for (final v in DraughtsVariant.all) (v, v.name)],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Segmented<int>(
                                  semanticLabel: tr('Juegas con'),
                                  value: _seat,
                                  onChanged: (s) => setState(() => _seat = s),
                                  options: _kind == GameKind.chineseCheckers
                                      ? [(0, tr('Naranja (empieza)')), (1, tr('Azul'))]
                                      : [(0, tr('Blancas')), (1, tr('Negras'))],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _busy ? null : _create,
                                    child: Text(tr('Crear y compartir código')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          section(
                            tr('Unirme con un código'),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _code,
                                    maxLength: 6,
                                    textCapitalization: TextCapitalization.characters,
                                    style: TType.clock(c.ink).copyWith(fontSize: 22),
                                    decoration: const InputDecoration(hintText: 'ABC234', counterText: ''),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _busy ? null : _join,
                                  child: Text(tr('Unirme')),
                                ),
                              ],
                            ),
                          ),
                          section(tr('Tus partidas'), const _MyGames()),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      )),
    );
  }
}

class _MyGames extends ConsumerWidget {
  const _MyGames();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final uid = ref.read(onlineRepositoryProvider).uid;
    final games = ref.watch(_myGamesProvider);
    return games.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(tr('No se pudieron cargar tus partidas.'), style: TType.bodySm(c.inkMuted)),
      data: (list) {
        final open = list.where((g) => !g.finished).toList();
        if (open.isEmpty) {
          return Text(tr('Aún no tienes partidas online abiertas.'), style: TType.bodySm(c.inkMuted));
        }
        return Column(
          children: [
            for (final g in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GameTile(game: g, uid: uid ?? ''),
              ),
          ],
        );
      },
    );
  }
}

class _GameTile extends ConsumerWidget {
  final OnlineGame game;
  final String uid;
  const _GameTile({required this.game, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final seat = game.seatOf(uid);
    final rawRival = game.names[1 - seat.clamp(0, 1)];
    final rival = rawRival == 'Cuenta eliminada' ? tr('Cuenta eliminada') : (rawRival.isEmpty ? rawRival : '@$rawRival');
    final title = switch (game.kind) {
      GameKind.chess => tr('Ajedrez'),
      GameKind.draughts => tr('Damas'),
      GameKind.chineseCheckers => tr('Damas chinas'),
    };
    final left = game.deadline?.difference(DateTime.now());
    final due = left == null
        ? ''
        : left.inHours >= 24
            ? tr(' · {inDays} d para mover', {'inDays': left.inDays})
            : tr(' · {p0} h para mover', {'p0': left.inHours.clamp(0, 23)});
    final status = game.waiting
        ? tr('Esperando rival · código {code}', {'code': game.code})
        : game.toMove == seat
            ? tr('Tu turno contra {rival}{due}', {'rival': rival, 'due': due})
            : tr('Turno de {rival}{due}', {'rival': rival, 'due': due});
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          openOnlineGame(ref, id: game.id, kind: game.kind, variantId: game.variantId, seat: seat);
          context.push('/game');
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TType.title(c.ink)),
                    Text(status,
                        style: TType.bodySm(!game.waiting && game.toMove == seat ? c.brand : c.inkMuted)),
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


/// Sin cuenta lista: explica por qué hace falta y lleva a crearla o verificarla.
class _AccountGate extends StatelessWidget {
  final AccountStatus status;
  const _AccountGate({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    if (status == AccountStatus.loading) return const Center(child: CircularProgressIndicator());
    final (title, body, button, route) = switch (status) {
      AccountStatus.needsUsername => (
          tr('Elige tu nombre de usuario'),
          tr('Es como te verán tus rivales. Solo hace falta elegirlo una vez.'),
          tr('Elegir nombre de usuario'),
          '/account/username?next=/online',
        ),
      AccountStatus.unverified => (
          tr('Verifica tu correo'),
          tr('Abre el enlace que te enviamos y vuelve: en cuanto esté verificado podrás crear partidas y unirte.'),
          tr('Verificar mi correo'),
          '/account/verify?next=/online',
        ),
      _ => (
          tr('Online necesita una cuenta'),
          tr('Con una cuenta tus partidas online no se pierden si cambias de teléfono o reinstalas la app, y podemos avisarte cuando te toca. Jugar contra la IA o en local sigue sin necesitarla.'),
          tr('Crear cuenta o iniciar sesión'),
          '/account?next=/online',
        ),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppIcon(AppIcons.online, size: 40, color: c.brand),
        const SizedBox(height: 12),
        Text(title, style: TType.title(c.ink)),
        const SizedBox(height: 8),
        Text(body, style: TType.body(c.inkMuted)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => context.push(route), child: Text(button)),
        ),
      ],
    );
  }
}


/// Amigos (con las solicitudes pendientes) y clasificación.
class _SocialRow extends ConsumerWidget {
  const _SocialRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = (ref.watch(friendsProvider).valueOrNull ?? const []).where((f) => f.state == 'incoming').length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
        onPressed: () => context.push('/friends'),
        icon: const AppIcon(AppIcons.friends, size: 20),
        label: Text(incoming == 0 ? tr('Amigos') : tr('Amigos ({n} solicitudes)', {'n': incoming})),
      ),
      OutlinedButton.icon(
        onPressed: () => context.push('/leaderboards'),
        icon: const AppIcon(AppIcons.trophy, size: 20),
        label: Text(tr('Clasificación')),
      ),
    ]);
  }
}
