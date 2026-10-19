/// Contrato común a todos los juegos. La IA, el historial, el deshacer y el
/// modo online solo conocen estas interfaces.
library;

/// Resultado de una partida terminada.
class GameResult {
  /// Índice del jugador ganador; `null` si son tablas.
  final int? winner;

  /// Motivo legible: «jaque mate», «triple repetición»…
  final String reason;

  const GameResult.win(int this.winner, this.reason);
  const GameResult.draw(this.reason) : winner = null;

  bool get isDraw => winner == null;

  @override
  String toString() =>
      isDraw ? 'Tablas ($reason)' : 'Gana el jugador $winner ($reason)';
}

/// Estado inmutable de una partida.
abstract interface class GameState {
  /// Índice del jugador al que le toca mover (0, 1, …).
  int get toMove;

  /// Número de jugadores de la partida.
  int get playerCount;
}

/// Reglas de un juego. Todas las funciones son puras: [apply] devuelve un
/// estado nuevo y nunca modifica el recibido.
abstract interface class GameRules<S extends GameState, M> {
  S initialState();
  List<M> legalMoves(S state);
  S apply(S state, M move);

  /// `null` mientras la partida sigue.
  GameResult? result(S state);
}
