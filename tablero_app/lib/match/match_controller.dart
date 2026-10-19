import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tablero_engine/tablero_engine.dart';

import '../app/metrics.dart';
import '../app/telemetry.dart';
import '../data/game_store.dart';
import '../online/online_repository.dart';
import 'adapters/match_adapter.dart';
import 'board_view.dart';
import 'match_config.dart';
import '../l10n/l10n.dart';

/// Configuración de la partida que se va a abrir. «Nueva partida» la fija
/// antes de navegar a la pantalla de juego.
final matchConfigProvider = StateProvider<MatchConfig?>((ref) => null);

final matchProvider =
    NotifierProvider.autoDispose<MatchController, MatchView>(MatchController.new);

/// Estado de la partida tal como lo pinta la interfaz.
class MatchView {
  final MatchConfig config;
  final BoardSnapshot board;
  final int toMove;
  final Set<int> movable;
  final int? selected;
  final List<int> targets;
  final bool aiThinking;
  final List<String> moveLog;

  /// Jugadas reproducibles, para guardar o revisar la partida.
  final List<String> moveCodes;
  final GameResult? result;
  final List<Duration>? clocks;
  final bool mustCapture;

  /// Coronación pendiente de elegir (solo ajedrez).
  final ({int from, int to})? pendingPromotion;

  /// Última jugada en lenguaje natural (TalkBack).
  final String? spokenMove;

  /// Damas: varios recorridos posibles hasta el mismo destino.
  final ({int from, int to, List<String> routes})? pendingRoute;
  final bool canUndo;
  final bool flipped;

  /// Nombres reales (partidas online); si es `null` se usan los de la config.
  final List<String>? playerNames;

  /// Online: el rival ofrece tablas.
  final bool drawOffered;

  /// Online: ya ofrecí tablas y espero respuesta.
  final bool myDrawOfferPending;

  /// Online: la partida espera a que alguien se una con [onlineCode].
  final bool waitingForOpponent;
  final String? onlineCode;

  /// Reto de un amigo que aún se puede rechazar (no has movido).
  final bool canDeclineChallenge;

  /// Último error de red, para mostrarlo una vez.
  final String? onlineError;

  /// Online: últimas frases fijas y, en partidas valoradas, la valoración de
  /// cada jugador al empezar.
  final List<({int seat, String phrase, DateTime? at})> emotes;
  final List<int>? playerRatings;

  const MatchView({
    this.emotes = const [],
    this.playerRatings,
    this.playerNames,
    this.drawOffered = false,
    this.myDrawOfferPending = false,
    this.waitingForOpponent = false,
    this.onlineCode,
    this.canDeclineChallenge = false,
    this.onlineError,
    required this.config,
    required this.board,
    required this.toMove,
    required this.movable,
    required this.selected,
    required this.targets,
    required this.aiThinking,
    required this.moveLog,
    this.moveCodes = const [],
    required this.result,
    required this.clocks,
    required this.mustCapture,
    required this.pendingPromotion,
    this.pendingRoute,
    this.spokenMove,
    required this.canUndo,
    required this.flipped,
  });

  bool get humanToMove =>
      result == null && !aiThinking && !waitingForOpponent && config.isHuman(toMove);

  /// Online: `@usuario` (con «(tú)» en el propio). Offline: el de la config.
  String nameOf(int player) {
    final n = playerNames;
    if (n != null && player < n.length && n[player].isNotEmpty) {
      final name = n[player] == 'Cuenta eliminada' ? tr('Cuenta eliminada') : '@${n[player]}';
      return player == config.humanSeat ? tr('{name} (tú)', {'name': name}) : name;
    }
    return config.playerName(player);
  }

  /// Vista de solo lectura para la pantalla de revisión.
  factory MatchView.readOnly({
    required MatchConfig config,
    required BoardSnapshot board,
    required int toMove,
    required List<String> moveLog,
    required bool flipped,
  }) =>
      MatchView(
        config: config,
        board: board,
        toMove: toMove,
        movable: const {},
        selected: null,
        targets: const [],
        aiThinking: false,
        moveLog: moveLog,
        result: null,
        clocks: null,
        mustCapture: false,
        pendingPromotion: null,
        canUndo: false,
        flipped: flipped,
      );
}

class MatchController extends AutoDisposeNotifier<MatchView> {
  late MatchConfig _config;
  late MatchAdapter _adapter;
  int? _selected;
  List<int> _targets = const [];
  bool _thinking = false;
  ({int from, int to})? _pendingPromotion;
  ({int from, int to, List<String> routes})? _pendingRoute;
  GameResult? _forcedResult;
  List<Duration>? _clocks;
  Timer? _timer;
  DateTime _lastTick = DateTime.now();
  bool _flipped = false;
  late GameStore _store;
  int? _savedId;
  DateTime _startedAt = DateTime.now();
  Future<void> _saving = Future.value();
  bool _disposed = false;

  // Online
  StreamSubscription<OnlineGame>? _remoteSub;
  OnlineGame? _remote;
  String? _onlineError;
  bool _submitting = false;

  bool get _online => _config.isOnline;

  @override
  MatchView build() {
    _store = ref.read(gameStoreProvider);
    final resume = ref.read(resumeGameProvider);
    _config = resume?.config ??
        ref.read(matchConfigProvider) ??
        const MatchConfig(kind: GameKind.chess);
    _adapter = MatchAdapter.create(_config);
    if (resume != null) {
      for (final code in resume.moves) {
        if (!_adapter.replay(code)) break; // partida guardada corrupta: se corta ahí
      }
      _savedId = resume.id;
      _startedAt = resume.startedAt;
    }
    // Riverpod no permite modificar otros providers durante build.
    Future.microtask(() {
      if (resume != null) {
        ref.read(resumeGameProvider.notifier).state = null;
        ref.read(matchConfigProvider.notifier).state = resume.config;
      }
    });
    if (_online) {
      final id = _config.onlineGameId!;
      _remoteSub = ref.read(onlineRepositoryProvider).watch(id).listen(
            _onRemote,
            onError: (Object e) => _reportError(tr('Sin conexión con la partida: {e}', {'e': e})),
          );
    } else if (resume == null) {
      // Va primero en la cadena de escrituras: nunca borra la partida nueva.
      _saving = _saving.then((_) => _store.discardInProgress()).catchError((Object _) {});
    }
    // Online se mide con online_invite / online_join (reabrir no es empezar).
    if (resume == null && !_online) {
      Metrics.gameStart(
        kind: _config.kind.name,
        mode: _config.opponent.name,
        aiLevel: _config.opponent == Opponent.ai ? _config.aiLevel : null,
      );
    }
    _flipped = _config.opponent != Opponent.local &&
        _config.humanSeat == 1 &&
        _config.kind != GameKind.chineseCheckers;
    final clock = _config.kind == GameKind.chineseCheckers ? null : _config.clock;
    if (clock != null) {
      final saved = resume?.clocksMs;
      _clocks = saved != null && saved.length == 2
          ? [for (final ms in saved) Duration(milliseconds: ms)]
          : List.filled(2, Duration(minutes: clock.minutes));
      _lastTick = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    }
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _remoteSub?.cancel();
    });
    Future.microtask(_maybeAi);
    return _view();
  }

  /// En online manda el servidor; el motor local solo se usa sin conexión.
  GameResult? get _result => _forcedResult ?? (_online ? null : _adapter.result);

  MatchView _view() => MatchView(
        config: _config,
        board: _adapter.snapshot(),
        toMove: _adapter.toMove,
        movable: _result == null && !_thinking && _config.isHuman(_adapter.toMove)
            ? _adapter.movableCells()
            : const {},
        selected: _selected,
        targets: _targets,
        aiThinking: _thinking,
        moveLog: _adapter.moveLog,
        moveCodes: _adapter.moveCodes,
        result: _result,
        clocks: _clocks == null ? null : List.unmodifiable(_clocks!),
        mustCapture: _result == null && _adapter.mustCapture,
        pendingPromotion: _pendingPromotion,
        pendingRoute: _pendingRoute,
        spokenMove: _adapter.lastMoveSpoken,
        canUndo: !_online && _adapter.canUndo && !_thinking && _result == null,
        flipped: _flipped,
        playerNames: _remote?.names,
        drawOffered: _remote?.drawOfferBy == 1 - _config.humanSeat && _result == null,
        myDrawOfferPending: _remote?.drawOfferBy == _config.humanSeat && _result == null,
        waitingForOpponent: _online && (_remote == null || _remote!.waiting),
        onlineCode: _remote?.code,
        canDeclineChallenge: _remote != null &&
            _remote!.challenger != null &&
            _remote!.players.length == 2 &&
            _remote!.challenger != _remote!.players[_config.humanSeat] &&
            _remote!.status == 'active' &&
            _remote!.moves.length <= _config.humanSeat,
        onlineError: _onlineError,
        emotes: _remote?.emotes ?? const [],
        playerRatings: (_remote?.rated ?? false) && (_remote?.ratingsAtStart.length ?? 0) == 2 ? _remote!.ratingsAtStart : null,
      );

  /// Las respuestas lentas (IA, pista, servidor) pueden llegar con la
  /// pantalla ya cerrada: escribir el estado entonces lanza una excepción.
  void _publish() {
    if (_disposed) return;
    state = _view();
  }

  /// Toque en una casilla del tablero.
  void tapCell(int cell) {
    if (!state.humanToMove || _pendingPromotion != null || _pendingRoute != null) return;
    if (_selected != null && _targets.contains(cell)) {
      final from = _selected!;
      final routes = _adapter.routesFor(from, cell);
      if (routes.length > 1) {
        _pendingRoute = (from: from, to: cell, routes: routes);
        _publish();
        return;
      }
      if (_adapter.needsPromotionChoice(from, cell)) {
        _pendingPromotion = (from: from, to: cell);
        _publish();
        return;
      }
      _commit(from, cell);
      return;
    }
    if (_adapter.movableCells().contains(cell)) {
      _selected = cell == _selected ? null : cell;
      _targets = _selected == null ? const [] : _adapter.targetsFrom(cell);
    } else {
      _selected = null;
      _targets = const [];
    }
    _publish();
  }

  void choosePromotion(int pieceType) {
    final p = _pendingPromotion;
    if (p == null) return;
    _pendingPromotion = null;
    _commit(p.from, p.to, promotion: pieceType);
  }

  void cancelPromotion() {
    _pendingPromotion = null;
    _publish();
  }

  void chooseRoute(int index) {
    final r = _pendingRoute;
    if (r == null) return;
    _pendingRoute = null;
    _commit(r.from, r.to, route: index);
  }

  void cancelRoute() {
    _pendingRoute = null;
    _publish();
  }

  void _commit(int from, int to, {int? promotion, int? route}) {
    final mover = _adapter.toMove;
    if (_submitting) return;
    if (!_adapter.play(from, to, promotion: promotion, route: route)) return;
    if (_online) _submit();
    _afterMove(mover);
  }

  // ---- Online ---------------------------------------------------------

  Future<void> _submit() async {
    final codes = _adapter.moveCodes;
    _submitting = true;
    try {
      // El servidor valida la jugada y calcula el resultado; aquí solo se envía.
      await ref.read(onlineRepositoryProvider).submitMove(
            id: _config.onlineGameId!,
            expectedPly: codes.length - 1,
            code: codes.last,
          );
    } on OnlineException catch (e) {
      if (_disposed) return;
      // stale: el rival movió antes; illegal_move: el motor local y el del
      // servidor discrepan. En ambos casos manda el servidor.
      _reportError(e.message);
      final remote = _remote;
      if (remote != null) _resyncFrom(remote);
    } catch (e, st) {
      Telemetry.nonFatal(e, st, reason: 'Enviar jugada online');
      if (_disposed) return;
      _reportError(tr('No se pudo enviar la jugada. Revisa tu conexión.'));
      final remote = _remote;
      if (remote != null) _resyncFrom(remote);
    } finally {
      _submitting = false;
    }
  }

  void _onRemote(OnlineGame g) {
    _remote = g;
    final local = _adapter.moveCodes;
    final remote = g.moves;
    final prefixMatches = local.length <= remote.length &&
        Iterable.generate(local.length).every((i) => local[i] == remote[i]);
    if (prefixMatches) {
      final before = local.length;
      for (var i = before; i < remote.length; i++) {
        if (!_adapter.replay(remote[i])) {
          // El servidor ya validó esta jugada: si aquí no entra, el estado local
          // está mal. Se reconstruye entero desde el servidor.
          _resyncFrom(g);
          break;
        }
      }
      if (remote.length > before) _lastTick = DateTime.now();
    } else if (!(_submitting && local.length == remote.length + 1)) {
      // Divergencia que no es nuestra jugada en vuelo: rehacer desde el servidor.
      _resyncFrom(g);
    }
    if (g.finished && _forcedResult == null) {
      _forcedResult = g.cancelled
          ? GameResult.draw(g.reason ?? 'partida cancelada') // p. ej. «reto rechazado»
          : g.winner == null
              ? GameResult.draw(g.reason ?? 'acuerdo mutuo')
              : GameResult.win(g.winner!, g.reason ?? 'final de partida');
      _persist();
    }
    _selected = null;
    _targets = const [];
    _publish();
  }

  void _resyncFrom(OnlineGame g) {
    _adapter = MatchAdapter.create(_config);
    for (final code in g.moves) {
      if (!_adapter.replay(code)) break;
    }
    _selected = null;
    _targets = const [];
    _publish();
  }

  void _reportError(String message) {
    _onlineError = message;
    _publish();
    _onlineError = null; // se muestra una sola vez
  }

  Future<void> respondToDraw({required bool accept}) async {
    final repo = ref.read(onlineRepositoryProvider);
    final id = _config.onlineGameId!;
    try {
      accept ? await repo.acceptDraw(id) : await repo.declineDraw(id);
    } catch (e) {
      _reportError(e is OnlineException ? e.message : tr('No se pudo responder a la oferta. Revisa tu conexión.'));
    }
  }

  void _afterMove(int mover) {
    final inc = _config.clock?.incrementSeconds ?? 0;
    if (_clocks != null && inc > 0) {
      _clocks![mover] += Duration(seconds: inc);
    }
    _selected = null;
    _targets = const [];
    _lastTick = DateTime.now();
    _publish();
    _persist();
    _maybeAi();
  }

  /// Guarda la partida (en curso o terminada). Las escrituras se encadenan
  /// para que nunca se creen dos filas de la misma partida.
  Future<void> _persist() {
    final result = _result;
    final moves = _adapter.moveCodes;
    if (moves.isEmpty && _savedId == null && result == null) return _saving;
    // Las partidas online viven en Firestore; aquí solo se archivan al terminar.
    if (_online && result == null) return _saving;
    final game = SavedGame(
      id: _savedId,
      config: _config,
      moves: moves,
      log: _adapter.moveLog,
      clocksMs: _clocks?.map((d) => d.inMilliseconds).toList(),
      finished: result != null,
      winner: result?.winner,
      reason: result?.reason,
      startedAt: _startedAt,
      updatedAt: DateTime.now(),
    );
    _saving = _saving.then((_) async {
      final id = await _store.save(game.id == null && _savedId != null ? game.withId(_savedId!) : game);
      _savedId = id;
      if (!_disposed) {
        ref.invalidate(inProgressProvider);
        ref.invalidate(historyProvider);
      }
    }).catchError((Object _) {
      // Guardar es de mejor esfuerzo: un fallo no debe romper la partida.
    });
    return _saving;
  }

  /// Espera a que terminen las escrituras pendientes (al salir de la pantalla).
  Future<void> flush() => _persist();

  int _aiFailures = 0;

  Future<void> _maybeAi() async {
    if (_disposed || _online || _result != null || _thinking || _config.isHuman(_adapter.toMove)) return;
    _thinking = true;
    _publish();
    final mover = _adapter.toMove;
    final before = _adapter.moveCodes.length;
    try {
      await _adapter.playAi(_config.aiLevel);
    } catch (e, st) {
      // Un isolate que falla no debe dejar la partida bloqueada en «Pensando…».
      Telemetry.nonFatal(e, st, reason: 'IA ${_config.kind.name} nivel ${_config.aiLevel}');
    } finally {
      _thinking = false;
    }
    if (_disposed) return;
    if (_forcedResult != null) {
      _publish();
      return;
    }
    if (_adapter.moveCodes.length == before) {
      _aiFailures++;
      if (_aiFailures <= 2) {
        Future.delayed(const Duration(milliseconds: 300), _maybeAi);
      } else {
        _reportError(tr('La IA no pudo mover. Deshaz una jugada o empieza otra partida.'));
      }
      return;
    }
    _aiFailures = 0;
    _afterMove(mover);
  }

  void _tick() {
    final clocks = _clocks;
    if (clocks == null || _result != null) {
      _timer?.cancel();
      return;
    }
    final now = DateTime.now();
    final player = _adapter.toMove;
    clocks[player] -= now.difference(_lastTick);
    _lastTick = now;
    if (clocks[player] <= Duration.zero) {
      clocks[player] = Duration.zero;
      _forcedResult = _adapter.timeout(player);
      _timer?.cancel();
      _publish();
      _persist();
      return;
    }
    _publish();
  }

  void undo() {
    if (!state.canUndo) return;
    _adapter.undo();
    // Contra la IA se deshace hasta volver al turno de la persona.
    while (!_config.isHuman(_adapter.toMove) && _adapter.canUndo) {
      _adapter.undo();
    }
    _selected = null;
    _targets = const [];
    _publish();
    _persist();
    _maybeAi();
  }

  void resign() {
    if (_result != null) return;
    if (_online) {
      ref
          .read(onlineRepositoryProvider)
          .resign(_config.onlineGameId!)
          .catchError((Object e) => _reportError(
              e is OnlineException ? e.message : tr('No se pudo abandonar. Revisa tu conexión.')));
      return; // el resultado llega por el stream
    }
    final loser = _config.opponent == Opponent.ai ? _config.humanSeat : _adapter.toMove;
    final winner = (loser + 1) % _adapter.playerCount;
    _forcedResult = GameResult.win(winner, 'abandono');
    _publish();
    _persist();
  }

  /// Ofrecer tablas. Contra la IA se aceptan solo si son reclamables por
  /// reglamento; en local la otra persona ya aceptó en el diálogo.
  /// Devuelve `false` si se rechazan.
  bool offerDraw({required bool accepted}) {
    if (_result != null) return false;
    if (_online) {
      ref
          .read(onlineRepositoryProvider)
          .offerDraw(_config.onlineGameId!)
          .catchError((Object e) => _reportError(
              e is OnlineException ? e.message : tr('No se pudo ofrecer tablas. Revisa tu conexión.')));
      return true;
    }
    final claim = _adapter.claimableDraw();
    if (claim != null) {
      _forcedResult = GameResult.draw(claim);
    } else if (accepted) {
      _forcedResult = const GameResult.draw('acuerdo mutuo');
    } else {
      return false;
    }
    _publish();
    _persist();
    return true;
  }

  bool _hinting = false;

  /// Calcula una pista y la deja seleccionada: la persona confirma tocando
  /// el destino. Devuelve `false` si no se pudo dar.
  Future<bool> showHint() async {
    if (!state.humanToMove || _hinting) return false;
    _hinting = true;
    final ply = _adapter.moveCodes.length;
    final hint = await _adapter.hint();
    _hinting = false;
    if (_disposed || hint == null || !state.humanToMove || _adapter.moveCodes.length != ply) return false;
    _selected = hint.$1;
    _targets = [hint.$2];
    _publish();
    return true;
  }

  void flip() {
    _flipped = !_flipped;
    _publish();
  }
}
