import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../widgets/segmented.dart';
import 'auth_service.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

enum _Mode { register, login }

/// Crear cuenta o iniciar sesión: Google o correo y contraseña.
class AuthScreen extends ConsumerStatefulWidget {
  /// Ruta a la que volver al terminar.
  final String next;
  const AuthScreen({super.key, this.next = '/'});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.register;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      final route = await ref.read(authServiceProvider).nextStep(widget.next);
      if (mounted) context.go(route);
    } on AuthFailure catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack(tr('No se pudo completar. Inténtalo de nuevo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = ref.read(authServiceProvider);
    await _run(() => _mode == _Mode.register
        ? auth.register(email: _email.text, password: _password.text)
        : auth.signInWithEmail(email: _email.text, password: _password.text));
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _snack(tr('Escribe tu correo arriba y vuelve a tocar «¿Olvidaste tu contraseña?».'));
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      // Mismo mensaje exista o no la cuenta: no revela qué correos están registrados.
      _snack(tr('Si hay una cuenta con {email}, te llegará un enlace para cambiar la contraseña.', {'email': email}));
    } on AuthFailure catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final register = _mode == _Mode.register;
    final field = InputDecoration(
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
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('Volver'),
                    icon: const AppIcon(AppIcons.back),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      Text(tr('Tu cuenta'), style: TType.display(c.ink)),
                      const SizedBox(height: 8),
                      Text(tr('Para jugar online con amigos y seguir tus partidas en cualquier teléfono.'),
                          style: TType.body(c.inkMuted)),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(ref.read(authServiceProvider).signInWithGoogle),
                          icon: const AppIcon(AppIcons.account),
                          label: Text(tr('Continuar con Google')),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: Divider(color: c.line)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(tr('o con tu correo'), style: TType.bodySm(c.inkMuted)),
                          ),
                          Expanded(child: Divider(color: c.line)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Segmented<_Mode>(
                        semanticLabel: tr('Crear cuenta o iniciar sesión'),
                        value: _mode,
                        onChanged: (m) => setState(() => _mode = m),
                        options: [(_Mode.register, tr('Crear cuenta')), (_Mode.login, tr('Iniciar sesión'))],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: field.copyWith(labelText: tr('Correo')),
                        validator: (v) {
                          final e = (v ?? '').trim();
                          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? null : tr('Escribe un correo válido.');
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                        decoration: field.copyWith(
                          labelText: tr('Contraseña'),
                          helperText: register ? tr('Mínimo {minPasswordLength} caracteres', {'minPasswordLength': AuthService.minPasswordLength}) : null,
                          suffixIcon: IconButton(
                            tooltip: _showPassword ? tr('Ocultar contraseña') : tr('Mostrar contraseña'),
                            icon: AppIcon(_showPassword ? AppIcons.eyeOff : AppIcons.eye),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (v) {
                          final p = v ?? '';
                          if (p.isEmpty) return tr('Escribe tu contraseña.');
                          if (register && p.length < AuthService.minPasswordLength) {
                            return tr('Usa al menos {minPasswordLength} caracteres.', {'minPasswordLength': AuthService.minPasswordLength});
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (!register)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: _busy ? null : _forgot, child: Text(tr('¿Olvidaste tu contraseña?'))),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brandInk),
                                )
                              : Text(register ? tr('Crear cuenta') : tr('Iniciar sesión')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(onPressed: () => context.go('/'), child: Text(tr('Ahora no, jugar sin cuenta'))),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
