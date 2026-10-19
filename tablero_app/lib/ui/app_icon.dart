import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Iconos propios de Escaque (assets/icons/*.svg): rejilla de 24, trazo 1,75,
/// extremos redondeados. Toman el color con `currentColor`.
enum AppIcons {
  back, chevronRight, chevronLeft, first, last, online, flip, copy, eye, eyeOff, undo, settings,
  local, ai, mail, hint, info, home, history, draw, resign, error, check, checkCircle, cancel,
  account, rules, stats, board, chess, draughts, star, bell, sound, logout, drag, chat, friends, trophy;

  /// Nombre del archivo: camelCase → snake_case.
  String get asset => 'assets/icons/${name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}.svg';
}

class AppIcon extends StatelessWidget {
  final AppIcons icon;
  final double size;
  final Color? color;

  /// Texto para lectores de pantalla; `null` = decorativo.
  final String? semanticLabel;

  const AppIcon(this.icon, {super.key, this.size = 24, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    return SvgPicture.asset(
      icon.asset,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// Botón de icono con objetivo táctil de 48 dp y descripción obligatoria.
class AppIconButton extends StatelessWidget {
  final AppIcons icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const AppIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: AppIcon(icon, color: onPressed == null ? Theme.of(context).disabledColor : color),
      );
}
