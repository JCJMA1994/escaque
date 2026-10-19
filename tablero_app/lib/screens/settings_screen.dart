import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../account/account_section.dart';
import '../ads/ads_service.dart';
import '../account/auth_service.dart';
import '../app/metrics.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../online/online_repository.dart';
import '../online/push_service.dart';
import '../purchases/purchases.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../ui/piece_art.dart';
import '../widgets/segmented.dart';
import '../l10n/l10n.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);

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

    Widget toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
        Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          child: SwitchListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(title, style: TType.label(c.ink)),
            subtitle: Text(subtitle, style: TType.bodySm(c.inkMuted)),
            value: value,
            onChanged: onChanged,
          ),
        );

    return ListView(
      padding: pagePadding(context, top: 32, bottom: 24),
      children: [
       ContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ajustes'), style: TType.display(c.ink)),
        const SizedBox(height: 24),
        const AccountSection(),
        section(
          tr('Idioma'),
          Segmented<String>(
            semanticLabel: tr('Idioma'),
            value: s.language,
            onChanged: ctrl.setLanguage,
            // Cada idioma con su propio nombre, para encontrarlo aunque no se entienda el actual.
            options: [('system', tr('Sistema')), ('es', 'Español'), ('en', 'English')],
          ),
        ),
        section(
          tr('Tema'),
          Segmented<ThemeMode>(
            semanticLabel: tr('Tema'),
            value: s.themeMode,
            onChanged: ctrl.setThemeMode,
            options: [
              (ThemeMode.system, tr('Sistema')),
              (ThemeMode.light, tr('Claro')),
              (ThemeMode.dark, tr('Oscuro')),
            ],
          ),
        ),
        section(
          tr('Tablero'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Segmented<BoardTheme>(
                semanticLabel: tr('Tema del tablero'),
                value: s.boardTheme,
                onChanged: ctrl.setBoardTheme,
                options: [for (final t in BoardTheme.values) (t, tr(t.label))],
              ),
              const SizedBox(height: 8),
              _BoardPreview(theme: s.boardTheme),
              const SizedBox(height: 8),
              toggle(tr('Coordenadas'), tr('Letras y números en el borde del tablero de ajedrez'),
                  s.showCoordinates, ctrl.setShowCoordinates),
              const SizedBox(height: 8),
              toggle(tr('Arrastrar piezas'), tr('Además de tocar la pieza y su destino'), s.dragPieces, ctrl.setDragPieces),
            ],
          ),
        ),
        section(
          tr('Sonido'),
          toggle(tr('Sonidos de juego'), tr('Movimiento, captura, jaque y final de partida'),
              s.sound, ctrl.setSound),
        ),
        if (ref.watch(firebaseReadyProvider) && ref.watch(accountStatusProvider) == AccountStatus.ready)
          section(
            tr('Partidas online'),
            Column(
              children: [
                toggle(tr('Avisos de partida'), tr('Cuando te toca, tu rival se une o propone tablas'),
                    s.onlineAlerts, (v) async {
                  ctrl.setOnlineAlerts(v);
                  final push = ref.read(pushServiceProvider);
                  if (v && !await push.hasPermission()) await push.requestPermission();
                  await push.savePreferences(notify: v, reminders: s.onlineReminders);
                }),
                const SizedBox(height: 8),
                toggle(tr('Recordatorios'), tr('Un aviso 24 h antes de que venza tu plazo para mover'),
                    s.onlineReminders, (v) async {
                  ctrl.setOnlineReminders(v);
                  await ref.read(pushServiceProvider).savePreferences(notify: s.onlineAlerts, reminders: v);
                }),
                const SizedBox(height: 8),
                toggle(tr('Frases del rival'), tr('Mostrar las frases rápidas que te envían en las partidas online'),
                    s.showPhrases, (v) async => ref.read(settingsProvider.notifier).setShowPhrases(v)),
                const SizedBox(height: 8),
                toggle(tr('Solicitudes de amistad'), tr('Que otras personas puedan añadirte por tu @usuario'),
                    ref.watch(profileProvider).valueOrNull?.friendRequests ?? true, (v) async {
                  await ref.read(pushServiceProvider).saveFriendRequests(v);
                }),
              ],
            ),
          ),
        section(
          tr('Notación de ajedrez'),
          toggle(tr('Letras en español'), tr('R, D, T, A y C en lugar de K, Q, R, B y N'),
              s.spanishNotation, ctrl.setSpanishNotation),
        ),
        section(
          tr('Variante de damas por defecto'),
          Segmented<String>(
            semanticLabel: tr('Variante de damas por defecto'),
            value: s.defaultDraughtsVariant,
            onChanged: ctrl.setDefaultVariant,
            options: [for (final v in DraughtsVariant.all) (v.id, v.name)],
          ),
        ),
        section(tr('Sin anuncios'), const AdFreeSection()),
        section(
          tr('Privacidad'),
          Column(children: [
            toggle(tr('Enviar informes de errores'), tr('Datos técnicos de los fallos para corregirlos, sin identificarte.'),
                s.crashReports, ctrl.setCrashReports),
            const SizedBox(height: 8),
            const _UsageStatsToggle(),
          ]),
        ),
        const _PrivacyOptions(),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextButton(
            onPressed: () => GoRouter.of(context).go('/welcome'),
            child: Text(tr('Ver la presentación de nuevo')),
          ),
        ),
        section(
          tr('Datos'),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.danger,
                side: BorderSide(color: c.danger, width: 1.5),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text(tr('¿Borrar el historial?'), style: TType.title(c.ink)),
                    content: Text(tr('Se borran todas las partidas terminadas. La partida en curso se conserva.'),
                        style: TType.body(c.ink)),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancelar'))),
                      TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Borrar historial'))),
                    ],
                  ),
                );
                if (ok != true) return;
                await ref.read(gameStoreProvider).clearHistory();
                ref.invalidate(historyProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Historial borrado'))),
                  );
                }
              },
              child: Text(tr('Borrar historial')),
            ),
          ),
        ),
       ])),
      ],
    );
  }
}


/// Botón para cambiar el consentimiento de anuncios, solo donde la
/// normativa lo exige (UMP indica si hace falta).
class _PrivacyOptions extends ConsumerWidget {
  const _PrivacyOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final ads = ref.read(adsServiceProvider);
    return FutureBuilder<bool>(
      future: ads.privacyOptionsRequired(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Privacidad'), style: TType.caption(c.inkMuted)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: ads.showPrivacyOptions,
                  child: Text(tr('Cambiar consentimiento de anuncios')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Muestra del tema de tablero elegido: una fila de casillas con piezas.
class _BoardPreview extends StatelessWidget {
  final BoardTheme theme;
  const _BoardPreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context).withBoard(theme);
    const kinds = [PieceKind.rook, PieceKind.knight, PieceKind.bishop, PieceKind.queen, PieceKind.king, PieceKind.pawn];
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          color: c.boardFrame,
          child: Row(
            children: [
              for (var i = 0; i < 6; i++)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ColoredBox(
                      color: i.isEven ? c.boardLight : c.boardDark,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: FittedBox(child: PieceIcon(kinds[i], white: i < 3)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Estadísticas de uso (Analytics). El valor por defecto depende de la región.
class _UsageStatsToggle extends StatefulWidget {
  const _UsageStatsToggle();

  @override
  State<_UsageStatsToggle> createState() => _UsageStatsToggleState();
}

class _UsageStatsToggleState extends State<_UsageStatsToggle> {
  bool _on = Metrics.enabled;

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _on,
      onChanged: (v) async {
        setState(() => _on = v);
        await Metrics.setEnabled(v);
      },
      title: Text(tr('Estadísticas de uso'), style: TType.label(c.ink)),
      subtitle: Text(tr('Qué juegos y funciones se usan, sin tu nombre, correo ni cuenta. Desactivadas hasta que las aceptes.'),
          style: TType.bodySm(c.inkMuted)),
    );
  }
}


/// Compra «quitar anuncios»: precio, comprar y restaurar.
class AdFreeSection extends ConsumerWidget {
  const AdFreeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = TableroColors.of(context);
    final s = ref.watch(adFreeProvider);
    final ctrl = ref.read(adFreeProvider.notifier);
    if (s.adFree) {
      return Row(children: [
        AppIcon(AppIcons.checkCircle, color: c.brand),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('Gracias por apoyar Escaque: no verás anuncios.'), style: TType.body(c.ink))),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Un pago único quita los banners y los anuncios entre partidas, y las pistas pasan a ser directas. Con cuenta, vale en todos tus teléfonos.'),
          style: TType.bodySm(c.inkMuted),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: s.busy || s.price == null ? null : ctrl.buy,
            child: Text(s.price == null ? tr('Quitar anuncios') : tr('Quitar anuncios · {price}', {'price': s.price})),
          ),
          TextButton(onPressed: s.busy ? null : ctrl.restore, child: Text(tr('Restaurar compras'))),
        ]),
        if (s.message != null) ...[
          const SizedBox(height: 6),
          Semantics(liveRegion: true, child: Text(s.message!, style: TType.bodySm(c.inkMuted))),
        ],
      ],
    );
  }
}


/// Pantalla propia de «quitar anuncios» (enlace desde el resultado).
class RemoveAdsScreen extends StatelessWidget {
  const RemoveAdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 24),
            children: [
              Row(children: [
                AppIconButton(icon: AppIcons.back, tooltip: tr('Volver'), onPressed: () => context.pop()),
                Expanded(child: Text(tr('Sin anuncios'), style: TType.titleLg(c.ink))),
              ]),
              const Padding(padding: EdgeInsets.fromLTRB(12, 12, 0, 0), child: AdFreeSection()),
            ],
          ),
        ),
      ),
    );
  }
}
