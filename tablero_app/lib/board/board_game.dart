import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../app/theme.dart';
import '../match/board_view.dart';
import '../match/match_controller.dart';
import 'board_component.dart';
import 'board_layout.dart';
import 'piece_component.dart';

/// Tablero en Flame. Solo dibuja y anima lo que el motor ya validó: los
/// toques se envían a [onCellTap] y el estado llega por [sync].
class BoardGame extends FlameGame {
  static const double extent = 800;

  final void Function(int cell) onCellTap;
  TableroColors colors;
  bool _showCoordinates = true;

  /// Arrastrar piezas (Ajustes). Tocar origen y destino funciona siempre.
  bool dragEnabled = true;

  /// «Quitar animaciones» del sistema: las piezas cambian de casilla sin moverse.
  bool reduceMotion = false;

  bool get showCoordinates => _showCoordinates;

  set showCoordinates(bool value) {
    if (value == _showCoordinates) return;
    _showCoordinates = value;
    _wake();
  }

  BoardGame({required this.onCellTap, required this.colors})
      : super(camera: CameraComponent.withFixedResolution(width: extent, height: extent));

  MatchView? _view;
  BoardLayout? _layout;
  BoardComponent? _board;
  final _pieces = <int, PieceComponent>{};
  int _shownVersion = -1;
  bool _animating = false;
  int _idleFrames = 0;

  // Arrastre en curso.
  PieceComponent? _dragging;
  int? _dragFrom;
  Vector2? _dragPoint;

  /// La jugada se soltó ya en su destino: no se anima el desplazamiento.
  bool _skipNextAnimation = false;

  @override
  Color backgroundColor() => colors.bg;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    final v = _view;
    if (v != null) _install(v);
  }

  /// Recibe cada estado nuevo de la partida.
  void sync(MatchView v) {
    final prev = _view;
    _view = v;
    if (!isLoaded) return;
    if (_board == null || prev == null || prev.flipped != v.flipped || prev.board.shape != v.board.shape) {
      _install(v);
      return;
    }
    _board!.view = v;
    final boardChanged = prev.board.version != v.board.version;
    final marksChanged = prev.selected != v.selected ||
        !listEquals(prev.targets, v.targets) ||
        prev.mustCapture != v.mustCapture;
    // Coronación o recorrido cancelados tras soltar la pieza: vuelve a su casilla.
    final choiceClosed = (prev.pendingPromotion != null && v.pendingPromotion == null) ||
        (prev.pendingRoute != null && v.pendingRoute == null);
    if (!boardChanged && choiceClosed) {
      _rebuild(v.board);
    }
    if (!boardChanged && !marksChanged) return;
    _wake();
    if (!boardChanged || _animating) return; // al terminar la animación se aplica lo pendiente
    _show(v.board);
  }

  /// Nuevos colores tras un cambio de tema claro/oscuro.
  void updateColors(TableroColors c) {
    if (identical(c, colors)) return;
    colors = c;
    final v = _view;
    if (isLoaded && v != null) _install(v);
  }

  void _install(MatchView v) {
    _layout = BoardLayout(
      shape: v.board.shape,
      size: v.board.size,
      flipped: v.flipped,
      extent: extent,
    );
    _board?.removeFromParent();
    _board = BoardComponent(layout: _layout!, colors: colors)..view = v;
    world.add(_board!);
    _animating = false;
    _rebuild(v.board);
    _wake();
  }

  void _show(BoardSnapshot b) {
    if (_skipNextAnimation || reduceMotion) {
      _skipNextAnimation = false;
      _rebuild(b);
      return;
    }
    if (b.version == _shownVersion + 1 && b.lastPath.length >= 2) {
      _animate(b);
    } else {
      _rebuild(b);
    }
  }

  void _rebuild(BoardSnapshot b) {
    for (final p in _pieces.values) {
      p.removeFromParent();
    }
    _pieces.clear();
    final layout = _layout!;
    final ratio = _pixelRatio();
    for (final piece in b.pieces) {
      final c = PieceComponent(
        view: piece,
        colors: colors,
        radius: layout.pieceRadius,
        position: layout.center(piece.cell),
        pixelRatio: ratio,
      );
      _pieces[piece.cell] = c;
      world.add(c);
    }
    _shownVersion = b.version;
  }

  void _animate(BoardSnapshot b) {
    final layout = _layout!;
    final mover = _pieces.remove(b.lastPath.first);
    if (mover == null) {
      _rebuild(b);
      return;
    }
    _animating = true;
    mover.priority = 10;
    final hops = <Effect>[
      for (final cell in b.lastPath.skip(1))
        MoveEffect.to(
          layout.center(cell),
          EffectController(duration: 0.18, curve: Curves.easeOutCubic),
        ),
    ];
    mover.add(SequenceEffect(hops, onComplete: () {
      for (final cell in b.lastCaptured) {
        final victim = _pieces.remove(cell);
        if (victim != null) {
          victim.add(ScaleEffect.to(
            Vector2.zero(),
            EffectController(duration: 0.2),
            onComplete: victim.removeFromParent,
          ));
        }
      }
      world.add(TimerComponent(
        period: b.lastCaptured.isEmpty ? 0.02 : 0.22,
        removeOnFinish: true,
        onTick: () => _finishAnimation(b),
      ));
    }));
  }

  void _finishAnimation(BoardSnapshot animated) {
    _animating = false;
    _rebuild(animated);
    final latest = _view?.board;
    if (latest != null && latest.version != animated.version) _show(latest);
  }

  /// Píxeles físicos por unidad del mundo: las piezas se rasterizan a ese tamaño.
  double _pixelRatio() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr = views.isEmpty ? 2.0 : views.first.devicePixelRatio;
    final logical = size.x > 0 ? size.x / extent : 0.5;
    return dpr * logical;
  }

  // ---- Arrastrar y soltar ------------------------------------------------

  void beginDrag(int cell, Vector2 at) {
    final v = _view;
    if (!dragEnabled || v == null || _animating || !v.movable.contains(cell)) return;
    if (v.selected != cell) onCellTap(cell); // selecciona y muestra destinos
    final piece = _pieces[cell];
    if (piece == null) return;
    _dragging = piece;
    _dragFrom = cell;
    _dragPoint = at.clone();
    piece
      ..priority = 20
      ..scale = Vector2.all(1.12)
      ..position = at.clone();
    _wake();
  }

  void updateDrag(Vector2 delta) {
    final p = _dragging, point = _dragPoint;
    if (p == null || point == null) return;
    point.add(delta);
    p.position = point.clone();
    _wake();
  }

  void endDrag({bool cancelled = false}) {
    final p = _dragging, from = _dragFrom, at = _dragPoint, layout = _layout;
    _dragging = null;
    _dragFrom = null;
    _dragPoint = null;
    if (p == null || from == null || at == null || layout == null) return;
    p.scale = Vector2.all(1);
    final target = cancelled ? null : layout.cellAt(at);
    if (target != null && target != from && (_view?.targets.contains(target) ?? false)) {
      p.position = layout.center(target);
      _skipNextAnimation = true;
      onCellTap(target);
      // Coronación pendiente o jugada rechazada: la vista no cambia de versión.
      if (_view?.board.version == _shownVersion) _skipNextAnimation = false;
    } else {
      p
        ..priority = 1
        ..position = layout.center(from);
    }
    _wake();
  }

  void _wake() {
    _idleFrames = 0;
    if (paused) resumeEngine();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Un juego por turnos no necesita 60 fps continuos: se duerme en reposo.
    if (_animating) {
      _idleFrames = 0;
    } else if (++_idleFrames > 4) {
      pauseEngine();
    }
  }
}
