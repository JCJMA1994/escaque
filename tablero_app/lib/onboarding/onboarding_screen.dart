import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/app_flags.dart';
import '../app/theme.dart';
import '../online/api_client.dart';
import '../online/online_repository.dart';
import '../ui/app_icon.dart';
import '../ui/piece_art.dart';
import '../l10n/l10n.dart';

/// Presentación de la primera vez: los juegos, los modos y cómo empezar
/// (sin cuenta u online con cuenta).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  Future<void> _offline() async {
    await AppFlags.completeOnboarding();
    if (mounted) context.go('/');
  }

  Future<void> _online() async {
    await AppFlags.completeOnboarding();
    if (mounted) context.go('/account?next=/online');
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final onlineAvailable = ref.watch(firebaseReadyProvider) && ApiClient.configured;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: _page < _count - 1
                    ? TextButton(
                        onPressed: () => _pages.animateToPage(_count - 1,
                            duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                        child: Text(tr('Saltar')),
                      )
                    : const SizedBox(height: 48),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _GamesPage(),
                  const _ModesPage(),
                  _StartPage(onlineAvailable: onlineAvailable, onOffline: _offline, onOnline: _online),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Semantics(
                    label: tr('Página {p0} de {_count}', {'p0': _page + 1, '_count': _count}),
                    child: Row(
                      children: [
                        for (var i = 0; i < _count; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _page ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? c.brand : c.lineStrong,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_page < _count - 1)
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(140, 52)),
                      onPressed: _next,
                      child: Text(tr('Siguiente')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final String title;
  final String lead;
  final List<Widget> children;
  const _Page({required this.title, required this.lead, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      children: [
        Text(title, style: TType.display(c.ink)),
        const SizedBox(height: 8),
        Text(lead, style: TType.body(c.inkMuted)),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final Widget leading;
  final String title;
  final String body;
  const _Row({required this.leading, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 48, child: leading),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TType.title(c.ink)),
                const SizedBox(height: 2),
                Text(body, style: TType.bodySm(c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GamesPage extends StatelessWidget {
  const _GamesPage();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    Widget tile(Widget child) => Container(
          decoration: BoxDecoration(color: c.boardLight, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: child,
        );
    return _Page(
      title: tr('Escaque'),
      lead: tr('Juegos de mesa clásicos con las reglas de sus reglamentos oficiales.'),
      children: [
        _Row(
          leading: tile(const PieceIcon(PieceKind.knight, size: 38)),
          title: tr('Ajedrez'),
          body: tr('Leyes del Ajedrez de la FIDE: enroque, captura al paso, tablas por repetición y por 50 jugadas.'),
        ),
        _Row(
          leading: Container(
            decoration: BoxDecoration(color: c.boardDark, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c.pieceLight,
                shape: BoxShape.circle,
                border: Border.all(color: c.pieceOutline, width: 1.5),
              ),
            ),
          ),
          title: tr('Damas'),
          body: tr('Tres variantes: internacional (10×10), inglesa y española (8×8), cada una con sus reglas de captura.'),
        ),
        _Row(
          leading: tile(AppIcon(AppIcons.star, color: c.players[0], size: 28)),
          title: tr('Damas chinas'),
          body: tr('Tablero de estrella para 2, 3, 4 o 6 jugadores. Gana quien llena primero la punta opuesta.'),
        ),
      ],
    );
  }
}

class _ModesPage extends StatelessWidget {
  const _ModesPage();

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    Widget icon(AppIcons i) => Container(
          decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: AppIcon(i, color: c.brand),
        );
    return _Page(
      title: tr('Contra quién'),
      lead: tr('Elige rival en cada partida.'),
      children: [
        _Row(
          leading: icon(AppIcons.ai),
          title: tr('Contra la IA'),
          body: tr('Cinco niveles, desde principiante hasta uno que piensa hasta 3 segundos por jugada. Con pistas.'),
        ),
        _Row(
          leading: icon(AppIcons.local),
          title: tr('En local'),
          body: tr('Dos personas en el mismo teléfono, pasándolo por turnos. En damas chinas, hasta seis.'),
        ),
        _Row(
          leading: icon(AppIcons.online),
          title: tr('Online con amigos'),
          body: tr('Partidas por turnos con un código de invitación. Te avisamos cuando te toca. Necesita cuenta.'),
        ),
      ],
    );
  }
}

class _StartPage extends StatelessWidget {
  final bool onlineAvailable;
  final VoidCallback onOffline;
  final VoidCallback onOnline;
  const _StartPage({required this.onlineAvailable, required this.onOffline, required this.onOnline});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    Widget option({
      required String title,
      required List<String> points,
      required Widget action,
      bool main = false,
    }) =>
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: main ? c.brand : Colors.transparent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TType.title(c.ink)),
              const SizedBox(height: 8),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: AppIcon(AppIcons.check, size: 18, color: c.brand),
                      ),
                      Expanded(child: Text(p, style: TType.bodySm(c.ink))),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: action),
            ],
          ),
        );

    return _Page(
      title: tr('Cómo empezar'),
      lead: tr('Puedes cambiar de idea cuando quieras en Ajustes → Cuenta.'),
      children: [
        option(
          title: tr('Sin cuenta'),
          points: [
            tr('Contra la IA y en local'),
            tr('Todo se guarda en este teléfono'),
            tr('Sin registro: empieza ya'),
          ],
          action: OutlinedButton(onPressed: onOffline, child: Text(tr('Jugar sin cuenta'))),
        ),
        option(
          title: tr('Con cuenta'),
          main: true,
          points: [
            tr('Todo lo anterior'),
            tr('Tu nombre de usuario único, como @ana_88'),
            tr('Partidas online con amigos y avisos de turno'),
            tr('Tus partidas online en cualquier teléfono'),
          ],
          action: onlineAvailable
              ? FilledButton(onPressed: onOnline, child: Text(tr('Crear cuenta o iniciar sesión')))
              : Text(tr('El modo online no está disponible en esta versión.'), style: TType.bodySm(c.inkMuted)),
        ),
      ],
    );
  }
}
