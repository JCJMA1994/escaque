import 'package:flutter/material.dart';

import '../app/theme.dart';

String formatClock(Duration d) {
  final total = d.inMilliseconds <= 0 ? 0 : (d.inMilliseconds / 1000).ceil();
  final m = total ~/ 60, s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Barra de jugador: avatar, nombre, estado y reloj.
class PlayerBar extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool active;
  final Duration? clock;
  final Color? avatarColor;

  const PlayerBar({
    super.key,
    required this.name,
    required this.subtitle,
    required this.active,
    this.clock,
    this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final low = clock != null && clock! < const Duration(seconds: 10);
    final plain = name.startsWith('@') ? name.substring(1) : name;
    final initials = plain.length >= 2 ? plain.substring(0, 2).toUpperCase() : plain.toUpperCase();
    return Semantics(
      container: true,
      label: '$name, $subtitle${clock != null ? ', ${formatClock(clock!)}' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? c.brand : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: avatarColor ?? c.surfaceRaised,
                shape: BoxShape.circle,
                border: avatarColor != null ? Border.all(color: c.pieceOutline, width: 1.5) : null,
              ),
              child: avatarColor == null
                  ? Text(initials, style: TType.label(c.ink).copyWith(fontSize: 14))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TType.label(c.ink).copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TType.bodySm(c.inkMuted)),
                ],
              ),
            ),
            if (clock != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: low ? c.danger : (active ? c.brand : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatClock(clock!),
                  style: TType.clock(low ? c.bg : (active ? c.brandInk : c.ink)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
