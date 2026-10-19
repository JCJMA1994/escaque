import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../online/online_repository.dart';
import 'auth_service.dart';
import '../l10n/l10n.dart';

/// Ajustes → Cuenta.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final status = ref.watch(accountStatusProvider);
    final user = ref.watch(authUserProvider).valueOrNull;
    final username = ref.watch(usernameProvider);
    final available = ref.watch(firebaseReadyProvider);

    Widget card(List<Widget> children) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    final content = switch (status) {
      AccountStatus.none => card([
          Text(tr('Juegas sin cuenta'), style: TType.label(c.ink)),
          const SizedBox(height: 4),
          Text(tr('Tus partidas se guardan en este teléfono. Crea una cuenta para jugar online; no perderás nada.'),
              style: TType.bodySm(c.inkMuted)),
          if (available) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/account?next=/'),
                child: Text(tr('Crear cuenta o iniciar sesión')),
              ),
            ),
          ],
        ]),
      AccountStatus.loading => card([
          Row(children: [
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(tr('Cargando tu cuenta…'), style: TType.bodySm(c.inkMuted)),
          ]),
        ]),
      AccountStatus.needsUsername => card([
          Text(user?.email ?? '', style: TType.label(c.ink)),
          const SizedBox(height: 4),
          Text(tr('Elige tu nombre de usuario para jugar online.'), style: TType.bodySm(c.inkMuted)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/account/username?next=/'),
              child: Text(tr('Elegir nombre de usuario')),
            ),
          ),
          TextButton(onPressed: () => _signOut(context, ref), child: Text(tr('Cerrar sesión'))),
        ]),
      AccountStatus.unverified => card([
          if (username != null) Text('@$username', style: TType.title(c.ink)),
          Text(user?.email ?? '', style: TType.label(c.ink)),
          const SizedBox(height: 4),
          Text(tr('Verifica tu correo para jugar online.'), style: TType.bodySm(c.inkMuted)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/account/verify?next=/'),
              child: Text(tr('Verificar mi correo')),
            ),
          ),
          TextButton(onPressed: () => _signOut(context, ref), child: Text(tr('Cerrar sesión'))),
        ]),
      AccountStatus.ready => card([
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username == null ? '' : '@$username', style: TType.title(c.ink)),
                    Text(user?.email ?? '', style: TType.bodySm(c.inkMuted)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push('/account/username?change=1&next=/'),
                child: Text(tr('Cambiar')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => _signOut(context, ref), child: Text(tr('Cerrar sesión'))),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: c.danger),
              onPressed: () => _delete(context, ref),
              child: Text(tr('Eliminar cuenta')),
            ),
          ),
        ]),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Cuenta'), style: TType.caption(c.inkMuted)),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authServiceProvider).signOut();
    if (context.mounted) _snack(context, tr('Sesión cerrada. Puedes seguir jugando sin cuenta.'));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final c = TableroColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(tr('¿Eliminar tu cuenta?'), style: TType.title(c.ink)),
        content: Text(
          tr('Pierdes las partidas online en curso (gana tu rival), se cancelan las que esperan rival, tu nombre desaparece de todas y tu nombre de usuario queda libre para otra persona. Las partidas guardadas en este teléfono se conservan. No se puede deshacer.'),
          style: TType.body(c.ink),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancelar'))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Eliminar cuenta')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final auth = ref.read(authServiceProvider);
    try {
      await auth.deleteAccount();
    } on AuthFailure catch (e) {
      if (!e.needsRecentLogin) {
        if (context.mounted) _snack(context, e.message);
        return;
      }
      // Firebase pide confirmar la identidad: contraseña o Google, y se reintenta.
      if (!context.mounted || !await _reauthenticate(context, ref)) return;
      try {
        await auth.deleteAccount();
      } on AuthFailure catch (e2) {
        if (context.mounted) _snack(context, e2.message);
        return;
      }
    }
    if (context.mounted) _snack(context, tr('Cuenta eliminada.'));
  }

  Future<bool> _reauthenticate(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authServiceProvider);
    final c = TableroColors.of(context);
    try {
      if (!auth.usesPassword) {
        await auth.reauthenticate();
        return true;
      }
      final ctrl = TextEditingController();
      final password = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(tr('Confirma que eres tú'), style: TType.title(c.ink)),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(labelText: tr('Contraseña')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Cancelar'))),
            TextButton(onPressed: () => Navigator.of(context).pop(ctrl.text), child: Text(tr('Confirmar'))),
          ],
        ),
      );
      ctrl.dispose();
      if (password == null || password.isEmpty) return false;
      await auth.reauthenticate(password: password);
      return true;
    } on AuthFailure catch (e) {
      if (context.mounted) _snack(context, e.message);
      return false;
    }
  }
}
