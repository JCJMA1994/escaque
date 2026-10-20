import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../data/game_store.dart';
import '../match/match_config.dart';
import '../match/match_controller.dart';
import '../widgets/segmented.dart';
import 'rules_sheet.dart';
import '../ui/app_icon.dart';
import '../ui/layout.dart';
import '../l10n/l10n.dart';

enum _Side { white, black, random }

class NewGameScreen extends ConsumerStatefulWidget {
  final GameKind kind;
  const NewGameScreen({super.key, required this.kind});

  @override
  ConsumerState<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends ConsumerState<NewGameScreen> {
  DraughtsVariant _variant = DraughtsVariant.spanish;
  Opponent _opponent = Opponent.ai;
  int _level = 3;
  _Side _side = _Side.white;
  TimeControl? _clock = TimeControl.presets[1];
  int _players = 2;

  bool get _isStar => widget.kind == GameKind.chineseCheckers;

  @override
  void initState() {
    super.initState();
    _variant = ref.read(settingsProvider).draughtsVariant;
  }


  void _start() {
    final seat = switch (_side) {
      _Side.white => 0,
      _Side.black => 1,
      _Side.random => Random().nextInt(2),
    };
    ref.read(resumeGameProvider.notifier).state = null;
    ref.read(matchConfigProvider.notifier).state = MatchConfig(
      kind: widget.kind,
      draughtsVariant: _variant,
      opponent: _opponent,
      aiLevel: _level,
      humanSeat: _isStar ? 0 : seat,
      clock: _isStar ? null : _clock,
      players: _players,
    );
    context.push('/game');
  }

  @override
  Widget build(BuildContext context) {
    final c = TableroColors.of(context);
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

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('Volver'),
                    icon: const AppIcon(AppIcons.back),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(child: Text(tr('Nueva partida'), style: TType.titleLg(c.ink))),
                  AppIconButton(
                    icon: AppIcons.rules,
                    tooltip: tr('Reglas'),
                    onPressed: () => showRulesSheet(
                      context,
                      MatchConfig(kind: widget.kind, draughtsVariant: _variant, players: _players),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (widget.kind == GameKind.draughts)
                    section(
                      tr('Variante'),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Segmented<DraughtsVariant>(
                            semanticLabel: tr('Variante'),
                            value: _variant,
                            onChanged: (v) => setState(() => _variant = v),
                            options: [for (final v in DraughtsVariant.all) (v, v.name)],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(variantSummary(_variant), style: TType.bodySm(c.inkMuted)),
                          ),
                        ],
                      ),
                    ),
                  if (_isStar)
                    section(
                      tr('Jugadores'),
                      Segmented<int>(
                        semanticLabel: tr('Número de jugadores'),
                        value: _players,
                        onChanged: (v) => setState(() => _players = v),
                        options: const [(2, '2'), (3, '3'), (4, '4'), (6, '6')],
                      ),
                    ),
                  section(
                    tr('Rival'),
                    Segmented<Opponent>(
                      semanticLabel: tr('Rival'),
                      value: _opponent,
                      onChanged: (v) => setState(() => _opponent = v),
                      options: [(Opponent.ai, 'IA'), (Opponent.local, tr('Local'))],
                    ),
                  ),
                  if (_opponent == Opponent.ai && !_isStar)
                    section(
                      tr('Nivel de la IA'),
                      ChoiceRow<int>(
                        value: _level,
                        onChanged: (v) => setState(() => _level = v),
                        options: [for (var i = 1; i <= 5; i++) (i, '$i')],
                      ),
                    ),
                  if (_opponent == Opponent.ai && !_isStar)
                    section(
                      tr('Juegas con'),
                      Segmented<_Side>(
                        semanticLabel: tr('Color'),
                        value: _side,
                        onChanged: (v) => setState(() => _side = v),
                        options: [
                          (_Side.white, tr('Blancas')),
                          (_Side.black, tr('Negras')),
                          (_Side.random, tr('Al azar')),
                        ],
                      ),
                    ),
                  if (!_isStar)
                    section(
                      tr('Reloj'),
                      ChoiceRow<TimeControl?>(
                        value: _clock,
                        mono: true,
                        onChanged: (v) => setState(() => _clock = v),
                        options: [
                          (null, tr('Sin reloj')),
                          for (final t in TimeControl.presets) (t, t.label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _start, child: Text(tr('Jugar'))),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
