import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../l10n/l10n.dart';

/// Lista horizontal de jugadas con la última resaltada.
class MoveStrip extends StatefulWidget {
  final List<String> moves;
  final bool numbered;

  const MoveStrip({super.key, required this.moves, this.numbered = true});

  @override
  State<MoveStrip> createState() => _MoveStripState();
}

class _MoveStripState extends State<MoveStrip> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(MoveStrip old) {
    super.didUpdateWidget(old);
    if (old.moves.length != widget.moves.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    final items = <Widget>[];
    for (var i = 0; i < widget.moves.length; i++) {
      if (widget.numbered && i.isEven) {
        items.add(Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text('${i ~/ 2 + 1}.', style: TType.notation(c.inkMuted)),
        ));
      }
      final last = i == widget.moves.length - 1;
      items.add(Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: last ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(widget.moves[i], style: TType.notation(last ? c.accentInk : c.ink)),
      ));
    }
    return SizedBox(
      height: 32,
      child: widget.moves.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('Sin jugadas todavía'), style: TType.bodySm(c.inkMuted)),
            )
          : ListView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              children: [for (final w in items) Center(child: w)],
            ),
    );
  }
}


/// Lista vertical de jugadas a dos columnas (panel lateral en tablet).
class MoveList extends StatelessWidget {
  final List<String> moves;
  const MoveList({super.key, required this.moves});

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
    if (moves.isEmpty) return Text(tr('Sin jugadas todavía'), style: TType.bodySm(c.inkMuted));
    final rows = (moves.length + 1) ~/ 2;
    Widget cell(int i) {
      if (i >= moves.length) return const SizedBox.shrink();
      final last = i == moves.length - 1;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: last ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(moves[i], style: TType.notation(last ? c.accentInk : c.ink)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                SizedBox(width: 36, child: Text('${r + 1}.', style: TType.notation(c.inkMuted))),
                Expanded(child: Align(alignment: Alignment.centerLeft, child: cell(2 * r))),
                Expanded(child: Align(alignment: Alignment.centerLeft, child: cell(2 * r + 1))),
              ],
            ),
        ],
      ),
    );
  }
}
