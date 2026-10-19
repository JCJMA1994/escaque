import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../l10n/l10n.dart';
import '../match/match_config.dart';
import '../online/online_repository.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../widgets/segmented.dart';

final friendsProvider = StreamProvider.autoDispose<List<Friend>>((ref) => ref.watch(onlineRepositoryProvider).friends());

/// Mis partidas, para mostrar junto a cada amigo las que tenemos en curso.
final _myGamesForFriendsProvider =
    StreamProvider.autoDispose<List<OnlineGame>>((ref) => ref.watch(onlineRepositoryProvider).myGames());

/// Amigos: añadir por @usuario, aceptar solicitudes, retar, quitar y bloquear.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  OnlineRepository get _repo => ref.read(onlineRepositoryProvider);

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on OnlineException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      final status = await _repo.requestFriend(name);
      _name.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'accepted' ? tr('¡Ya sois amigos!') : tr('Solicitud enviada.')),
      ));
    });
  }

  Future<void> _challenge(Friend f) async {
    final picked = await showModalBottomSheet<({GameKind kind, String variant, int seat, bool rated})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: TableroColors.of(context).surface,
      builder: (context) => _ChallengeSheet(friend: f, defaultVariant: ref.read(settingsProvider).draughtsVariant),
    );
    if (picked == null) return;
    await _run(() async {
      final g = await _repo.challenge(f.uid, kind: picked.kind, variant: picked.variant, seat: picked.seat, rated: picked.rated);
      if (mounted) context.push('/online/game/${g.id}');
    });
  }

  Future<void> _menu(Friend f) async {
    final c = TableroColors.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(tr('Quitar de amigos')), onTap: () => Navigator.pop(context, 'remove')),
          ListTile(
            title: Text(tr('Bloquear'), style: TextStyle(color: c.danger)),
            subtitle: Text(tr('No podrá enviarte solicitudes ni retarte. No se le avisa.')),
            onTap: () => Navigator.pop(context, 'block'),
          ),
        ]),
      ),
    );
    if (action == 'remove') await _run(() => _repo.removeFriend(f.uid));
    if (action == 'block') await _run(() => _repo.blockFriend(f.uid), done: tr('Bloqueado.'));
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final all = ref.watch(friendsProvider);
    final me = ref.watch(onlineRepositoryProvider).uid;
    final games = ref.watch(_myGamesForFriendsProvider).valueOrNull ?? const <OnlineGame>[];
    // Partidas en curso con cada amigo y si me toca en alguna.
    List<OnlineGame> withFriend(String uid) =>
        [for (final g in games) if (g.status == 'active' && g.players.contains(uid) && g.players.contains(me)) g];
    String? gamesLine(String uid) {
      final list = withFriend(uid);
      if (list.isEmpty) return null;
      final mine = list.where((g) => g.players.length > g.toMove && g.players[g.toMove] == me).length;
      if (mine > 0) return tr(mine == 1 ? 'Te toca en 1 partida' : 'Te toca en {n} partidas', {'n': mine});
      return tr(list.length == 1 ? 'Le toca en 1 partida' : 'Le toca en {n} partidas', {'n': list.length});
    }
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 640,
          child: all.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(tr('No se pudo cargar la lista de amigos.'), style: TType.body(c.ink))),
            data: (list) {
              final incoming = list.where((f) => f.state == 'incoming').toList();
              final friends = list.where((f) => f.state == 'friend').toList();
              final outgoing = list.where((f) => f.state == 'outgoing').toList();
              final blocked = list.where((f) => f.state == 'blocked').toList();
              Widget header(String t) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                    child: Text(t, style: TType.title(c.ink)),
                  );
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Row(children: [
                      AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                      Expanded(child: Text(tr('Amigos'), style: TType.titleLg(c.ink))),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          textInputAction: TextInputAction.send,
                          autocorrect: false,
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(labelText: tr('Añadir por nombre de usuario'), prefixText: '@'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _busy ? null : _add, child: Text(tr('Añadir'))),
                    ]),
                  ),
                  if (incoming.isNotEmpty) ...[
                    header(tr('Solicitudes')),
                    for (final f in incoming)
                      ListTile(
                        title: Text('@${f.username}', style: TType.label(c.ink)),
                        subtitle: Text(tr('Quiere ser tu amigo'), style: TType.bodySm(c.inkMuted)),
                        trailing: Wrap(spacing: 4, children: [
                          TextButton(
                              onPressed: _busy ? null : () => _run(() => _repo.respondFriend(f.uid, accept: false)),
                              child: Text(tr('Rechazar'))),
                          FilledButton(
                              onPressed: _busy ? null : () => _run(() => _repo.respondFriend(f.uid, accept: true)),
                              child: Text(tr('Aceptar'))),
                        ]),
                      ),
                  ],
                  header(tr('Tus amigos')),
                  if (friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(tr('Añade a alguien por su @usuario para retarle directamente, sin códigos.'),
                          style: TType.bodySm(c.inkMuted)),
                    ),
                  for (final f in friends)
                    ListTile(
                      leading: AppIcon(AppIcons.account, color: c.inkMuted),
                      title: Text('@${f.username}', style: TType.label(c.ink)),
                      subtitle: gamesLine(f.uid) == null ? null : Text(gamesLine(f.uid)!, style: TType.bodySm(c.inkMuted)),
                      // Con una partida en curso, tocar al amigo la abre.
                      onTap: withFriend(f.uid).isEmpty ? null : () => context.push('/online/game/${withFriend(f.uid).first.id}'),
                      onLongPress: () => _menu(f),
                      trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        FilledButton(onPressed: _busy ? null : () => _challenge(f), child: Text(tr('Retar'))),
                        IconButton(
                          tooltip: tr('Más opciones'),
                          onPressed: () => _menu(f),
                          icon: AppIcon(AppIcons.settings, color: c.inkMuted, size: 20),
                        ),
                      ]),
                    ),
                  if (outgoing.isNotEmpty) ...[
                    header(tr('Enviadas')),
                    for (final f in outgoing)
                      ListTile(
                        title: Text('@${f.username}', style: TType.label(c.ink)),
                        subtitle: Text(tr('Pendiente'), style: TType.bodySm(c.inkMuted)),
                        trailing: TextButton(
                            onPressed: _busy ? null : () => _run(() => _repo.removeFriend(f.uid)), child: Text(tr('Cancelar'))),
                      ),
                  ],
                  if (blocked.isNotEmpty) ...[
                    header(tr('Bloqueados')),
                    for (final f in blocked)
                      ListTile(
                        title: Text(f.username.isEmpty ? tr('Cuenta bloqueada') : '@${f.username}', style: TType.label(c.ink)),
                        trailing: TextButton(
                            onPressed: _busy ? null : () => _run(() => _repo.unblockFriend(f.uid)), child: Text(tr('Desbloquear'))),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Juego, variante, color y si es valorada.
class _ChallengeSheet extends StatefulWidget {
  final Friend friend;
  final DraughtsVariant defaultVariant;
  const _ChallengeSheet({required this.friend, required this.defaultVariant});

  @override
  State<_ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<_ChallengeSheet> {
  GameKind _kind = GameKind.chess;
  late DraughtsVariant _variant = widget.defaultVariant;
  int _seat = 0;
  bool _rated = false;

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Retar a @{name}', {'name': widget.friend.username}), style: TType.title(c.ink)),
            const SizedBox(height: 12),
            Segmented<GameKind>(
              semanticLabel: tr('Juego'),
              value: _kind,
              options: [
                (GameKind.chess, tr('Ajedrez')),
                (GameKind.draughts, tr('Damas')),
                (GameKind.chineseCheckers, tr('Damas chinas')),
              ],
              onChanged: (k) => setState(() {
                _kind = k;
                if (k == GameKind.chineseCheckers) _rated = false;
              }),
            ),
            if (_kind == GameKind.draughts) ...[
              const SizedBox(height: 12),
              Segmented<DraughtsVariant>(
                semanticLabel: tr('Variante'),
                value: _variant,
                options: [
                  (DraughtsVariant.spanish, tr('Española')),
                  (DraughtsVariant.international, tr('Internacional')),
                  (DraughtsVariant.english, tr('Inglesa')),
                ],
                onChanged: (v) => setState(() => _variant = v),
              ),
            ],
            const SizedBox(height: 12),
            Segmented<int>(
              semanticLabel: tr('Color'),
              value: _seat,
              options: [(0, tr('Juego con blancas')), (1, tr('Juego con negras'))],
              onChanged: (s) => setState(() => _seat = s),
            ),
            if (_kind != GameKind.chineseCheckers)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Partida valorada'), style: TType.body(c.ink)),
                subtitle: Text(tr('Cuenta para tu valoración y la clasificación (mínimo 10 jugadas cada uno).'),
                    style: TType.bodySm(c.inkMuted)),
                value: _rated,
                onChanged: (v) => setState(() => _rated = v),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (
                  kind: _kind,
                  variant: _kind == GameKind.draughts ? _variant.id : '',
                  seat: _seat,
                  rated: _rated,
                )),
                child: Text(tr('Enviar reto')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
