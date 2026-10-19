import 'package:flutter/material.dart';

/// Clases de ventana de Material 3: compacta (< 600 dp, teléfono vertical),
/// media (600–839: teléfono horizontal, tablet pequeña, plegable abierto) y
/// expandida (≥ 840: tablet horizontal, escritorio).
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double w) => w >= 840
      ? WindowSize.expanded
      : w >= 600
          ? WindowSize.medium
          : WindowSize.compact;

  bool get isCompact => this == WindowSize.compact;
}

/// Contenido centrado con un ancho máximo legible: formularios y listas no se
/// estiran a todo el ancho de una tablet.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ContentWidth({super.key, required this.child, this.maxWidth = 560});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// Márgenes laterales según el ancho: 16 en teléfono, 24 en tablet.
EdgeInsets pagePadding(BuildContext context, {double top = 0, double bottom = 0}) {
  final h = WindowSize.of(context).isCompact ? 16.0 : 24.0;
  return EdgeInsets.fromLTRB(h, top, h, bottom);
}
