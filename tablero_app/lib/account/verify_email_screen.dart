import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import 'auth_service.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

/// Espera a que la persona abra el enlace de verificación. Comprueba sola al
/// volver a la app.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String next;
  const VerifyEmailScreen({super.key, this.next = '/'});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> with WidgetsBindingObserver {
  static const _cooldown = 60;
  int _wait = _cooldown;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Vuelve del cliente de correo: comprobar sin que tenga que tocar nada.
    if (state == AppLifecycleState.resumed) _check(silent: true);
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _wait = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final ok = await ref.read(authServiceProvider).refreshVerification();
      if (!mounted) return;
      if (ok) {
        final route = await ref.read(authServiceProvider).nextStep(widget.next);
        if (mounted) context.go(route);
      } else if (!silent) {
        _snack(tr('Aún no aparece verificado. Abre el enlace del correo y vuelve aquí.'));
      }
    } on AuthFailure catch (e) {
      if (!silent && mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authServiceProvider).resendVerification();
      _snack(tr('Te enviamos otro correo.'));
      _startCooldown();
    } on AuthFailure catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final email = ref.watch(authUserProvider).valueOrNull?.email ?? tr('tu correo');
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            AppIcon(AppIcons.mail, size: 48, color: c.brand),
            const SizedBox(height: 16),
            Text(tr('Revisa tu correo'), style: TType.display(c.ink)),
            const SizedBox(height: 8),
            Text(
              tr('Te enviamos un enlace a {email}. Ábrelo para verificar la cuenta y vuelve aquí. Si no lo ves, mira en la carpeta de spam.', {'email': email}),
              style: TType.body(c.inkMuted),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _checking ? null : () => _check(),
                child: Text(tr('Ya lo verifiqué')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _wait > 0 ? null : _resend,
                child: Text(_wait > 0 ? tr('Reenviar correo en {_wait} s', {'_wait': _wait}) : tr('Reenviar correo')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (context.mounted) context.go('/account?next=${Uri.encodeComponent(widget.next)}');
                },
                child: Text(tr('Usar otra cuenta')),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.go('/'),
                child: Text(tr('Jugar sin conexión mientras tanto')),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
