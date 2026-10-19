import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Control segmentado del design system (VariantPicker y similares).
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (v, label) in options)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Option(
                    label: label,
                    selected: v == value,
                    onTap: () => onChanged(v),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Option({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: selected ? BorderSide(color: c.brand, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(label,
                  style: TType.label(c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de opciones tipo chip (niveles, relojes).
class ChoiceRow<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool mono;

  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in options)
          Semantics(
            selected: v == value,
            button: true,
            child: Material(
              color: v == value ? c.brand : c.surface,
              shape: StadiumBorder(
                side: BorderSide(color: v == value ? c.brand : c.lineStrong, width: 1.5),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Text(
                    label,
                    style: (mono ? TType.notation : TType.label)(v == value ? c.brandInk : c.ink),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
