import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../l10n/l10n.dart';
import 'app_icon.dart';

/// Barra de navegación flotante moderna para Escaque.
///
/// Combina un estilo dock flotante con esquinas redondeadas, sombras sutiles
/// y microinteracciones táctiles (retroalimentación háptica, píldora animada
/// y acento dorado para la pestaña activa).
class EscaqueNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<(AppIcons, String)> destinations;

  const EscaqueNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(33),
            border: Border.all(
              color: isDark ? c.line.withValues(alpha: 0.5) : c.lineStrong.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
                spreadRadius: 1,
              ),
              BoxShadow(
                color: c.brand.withValues(alpha: isDark ? 0.12 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++) ...[
                  Expanded(
                    child: _NavBarItem(
                      icon: destinations[i].$1,
                      label: destinations[i].$2,
                      isSelected: selectedIndex == i,
                      onTap: () {
                        if (selectedIndex != i) {
                          HapticFeedback.selectionClick();
                          onDestinationSelected(i);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final AppIcons icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final localizedLabel = tr(label);

    return Semantics(
      button: true,
      selected: isSelected,
      label: localizedLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          splashColor: c.brand.withValues(alpha: 0.12),
          highlightColor: c.brand.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? c.brand.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              border: isSelected
                  ? Border.all(color: c.brand.withValues(alpha: 0.22), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      child: AppIcon(
                        icon,
                        size: 22,
                        color: isSelected ? c.brand : c.inkMuted,
                        semanticLabel: null,
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: c.accent.withValues(alpha: 0.6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: isSelected ? 0.2 : 0,
                    color: isSelected ? c.brand : c.inkMuted,
                  ),
                  child: Text(
                    localizedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
