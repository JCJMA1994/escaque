import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/auth_service.dart';
import '../app/metrics.dart';
import '../app/theme.dart';
import '../online/online_repository.dart';
import 'online_game_loader.dart';
import '../l10n/l10n.dart';

/// Enlace de invitación `https://<web>/j/CÓDIGO` (Android App Links): se une
/// a la partida y la abre. Sin cuenta lista, pasa antes por el flujo de cuenta
/// y vuelve aquí.
class JoinInviteScreen extends ConsumerStatefulWidget {
  final String code;
  const JoinInviteScreen({super.key, required this.code});

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  String? _error;

  String get _code => widget.code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    setState(() => _error = null);
    if (_code.length != 6) {
      setState(() => _error = tr('El enlace no tiene un código válido.'));
      return;
    }
    final here = '/j/$_code';
    final next = await ref.read(authServiceProvider).nextStep(here);
    if (!mounted) return;
    if (next != here) {
      context.go(next); // cuenta, nombre de usuario o verificación; luego vuelve aquí
      return;
    }
    try {
      final j = await ref.read(onlineRepositoryProvider).joinByCode(_code);
      Metrics.onlineJoin(via: 'link');
      openOnlineGame(ref, id: j.id, kind: j.kind, variantId: j.variantId, seat: j.seat);
      if (mounted) context.go('/game');
    } on OnlineException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('No se pudo unir a la partida. Revisa tu conexión.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(tr('Uniéndote a la partida {_code}…', {'_code': _code}), style: TType.body(c.ink)),
                    ])
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('No se pudo usar la invitación'), style: TType.title(c.ink)),
                        const SizedBox(height: 8),
                        Text(_error!, style: TType.body(c.inkMuted)),
                        const SizedBox(height: 24),
                        Row(children: [
                          FilledButton(onPressed: _join, child: Text(tr('Reintentar'))),
                          const SizedBox(width: 12),
                          TextButton(onPressed: () => context.go('/online'), child: Text(tr('Ir a online'))),
                        ]),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
