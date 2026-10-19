import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import 'auth_service.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

/// Elegir (o cambiar) el nombre de usuario: único, lo ven los rivales.
/// La disponibilidad se comprueba en el servidor mientras se escribe.
class UsernameScreen extends ConsumerStatefulWidget {
  final String next;

  /// Cambiar uno existente (en lugar de elegir el primero).
  final bool change;
  const UsernameScreen({super.key, this.next = '/', this.change = false});

  @override
  ConsumerState<UsernameScreen> createState() => _UsernameScreenState();
}

enum _Check { idle, checking, available, unavailable, error }

class _UsernameScreenState extends ConsumerState<UsernameScreen> {
  final _field = TextEditingController();
  Timer? _debounce;
  _Check _check = _Check.idle;
  String? _reason;
  String _checked = '';
  bool _saving = false;

  // Mismas reglas que el servidor, para avisar antes de preguntar.
  static final _allowed = RegExp(r'[a-z0-9_]');
  static final _valid = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  String? _localProblem(String u) {
    if (u.length < 3) return tr('Usa al menos 3 caracteres.');
    if (!_valid.hasMatch(u)) return tr('Empieza por una letra; solo letras sin tilde, números y _.');
    if (u.contains('__')) return tr('No uses dos guiones bajos seguidos.');
    return null;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final u = value.trim().toLowerCase();
    final local = u.isEmpty ? null : _localProblem(u);
    setState(() {
      _check = u.isEmpty ? _Check.idle : (local != null ? _Check.unavailable : _Check.checking);
      _reason = local;
    });
    if (u.isEmpty || local != null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _ask(u));
  }

  Future<void> _ask(String u) async {
    try {
      final r = await ref.read(authServiceProvider).checkUsername(u);
      if (!mounted || _field.text.trim().toLowerCase() != u) return; // ya escribió otra cosa
      setState(() {
        _checked = r.username;
        _check = r.available ? _Check.available : _Check.unavailable;
        _reason = r.reason;
      });
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _check = _Check.error;
          _reason = e.message;
        });
      }
    }
  }

  Future<void> _save() async {
    final u = _field.text.trim().toLowerCase();
    if (_check != _Check.available || _checked != u) return;
    setState(() => _saving = true);
    try {
      await ref.read(authServiceProvider).setUsername(u);
      if (!mounted) return;
      if (widget.change) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Ahora eres @{u}.', {'u': u}))));
        context.canPop() ? context.pop() : context.go(widget.next);
        return;
      }
      context.go(await ref.read(authServiceProvider).nextStep(widget.next));
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _check = _Check.unavailable;
          _reason = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final current = ref.watch(usernameProvider);
    final (icon, color, text) = switch (_check) {
      _Check.idle => (null, c.inkMuted, tr('3 a 20 caracteres: letras sin tilde, números y _.')),
      _Check.checking => (null, c.inkMuted, tr('Comprobando…')),
      _Check.available => (AppIcons.checkCircle, c.brand, tr('@{u} está libre.', {'u': _checked})),
      _Check.unavailable => (AppIcons.cancel, c.danger, _reason ?? 'No disponible.'),
      _Check.error => (AppIcons.error, c.danger, _reason ?? 'No se pudo comprobar.'),
    };
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            if (widget.change)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: tr('Volver'),
                  icon: const AppIcon(AppIcons.back),
                  onPressed: () => context.canPop() ? context.pop() : context.go(widget.next),
                ),
              ),
            const SizedBox(height: 16),
            Text(widget.change ? tr('Cambiar nombre de usuario') : tr('Elige tu nombre de usuario'), style: TType.titleLg(c.ink)),
            const SizedBox(height: 8),
            Text(
              widget.change
                  ? tr('Ahora eres {u}. Solo puedes cambiarlo una vez cada 30 días; el anterior quedará libre para otra persona.',
                      {'u': current == null ? '' : '@$current'})
                  : tr('Es como te verán tus rivales y con lo que te reconocerán tus amigos. Es único.'),
              style: TType.body(c.inkMuted),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _field,
              autofocus: true,
              maxLength: 20,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.done,
              inputFormatters: [
                // Minúsculas y solo caracteres válidos, mientras se escribe.
                TextInputFormatter.withFunction((old, value) {
                  final lower = value.text.toLowerCase();
                  final filtered = lower.split('').where(_allowed.hasMatch).join();
                  if (filtered == value.text) return value;
                  return TextEditingValue(
                    text: filtered,
                    selection: TextSelection.collapsed(offset: filtered.length),
                  );
                }),
              ],
              decoration: InputDecoration(
                prefixText: '@',
                counterText: '',
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
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  if (icon != null) ...[AppIcon(icon, size: 18, color: color), const SizedBox(width: 6)],
                  if (_check == _Check.checking) ...[
                    SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(text, style: TType.bodySm(color))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _check == _Check.available && !_saving ? _save : null,
                child: Text(widget.change ? tr('Guardar') : tr('Continuar')),
              ),
            ),
            if (!widget.change) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/'),
                  child: Text(tr('Más tarde (podrás jugar sin conexión)')),
                ),
              ),
            ],
          ],
        ),
      )),
    );
  }
}
