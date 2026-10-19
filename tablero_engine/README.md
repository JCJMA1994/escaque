# tablero_engine

Motor de reglas de **Tablero** en Dart puro (sin Flutter, Flame ni Firebase):

| Juego | Reglamento | Qué cubre |
| --- | --- | --- |
| Ajedrez | Leyes FIDE | Jugadas legales, enroque, captura al paso, coronación, mate, ahogado, posición muerta, 50/75 jugadas, triple/quíntuple repetición, caída de bandera, FEN, SAN, UCI |
| Damas internacionales | FMJD | 10×10, dama larga, peón captura atrás, captura máxima obligatoria, no corona de paso |
| Damas inglesas | WCDF | 8×8, dama corta, captura obligatoria libre, coronar termina el turno |
| Damas españolas | Federación española | 8×8, dama larga, captura máxima y luego más damas |
| Damas chinas | Reglamento estándar | Estrella de 121 casillas, 2/3/4/6 jugadores, saltos en cadena, regla de meta bloqueada |

Más una IA alfa-beta genérica con 5 niveles y una IA voraz para damas chinas multijugador.

## IA

`AlphaBeta` es genérica (sirve para cualquier `GameRules` de dos jugadores) y tiene:

- Profundización iterativa con **límite de tiempo** por jugada: devuelve la mejor jugada de la última profundidad completada.
- **Tabla de transposición** con hash Zobrist (`ChessState.hash`, `DraughtsState.hash`).
- **Búsqueda de quietud**: sigue capturas y coronaciones en las hojas para no cortar a mitad de un intercambio. En damas, las capturas obligatorias.
- Ordenación MVV-LVA en ajedrez y jugada de la tabla primero.
- `terminal`: reutiliza las jugadas legales para detectar el final sin generarlas dos veces.

| Nivel | Profundidad máx. | Tiempo máx. | Error aleatorio |
| --- | --- | --- | --- |
| 1 | 1 | 0,3 s | alto |
| 2 | 2 | 0,6 s | medio |
| 3 | 3 | 1,2 s | bajo (con quietud) |
| 4 | 5 | 2 s | mínimo |
| 5 | 8 | 3 s | ninguno |

Además, la legalidad se comprueba sobre un tablero de trabajo sin crear posiciones intermedias y las repeticiones se cuentan recorriendo solo las jugadas desde la última captura o movimiento de peón.

Otras piezas de la IA:

- `chessAi(level, timeLimit: …)` y `draughtsAi(rules, level, timeLimit: …)`: el límite opcional
  sustituye al del nivel (el análisis tras la partida usa 0,3 s por posición).
- `AlphaBeta.analyse(state)`: mejor jugada **y su puntuación** desde el bando en turno, sin ruido;
  `null` si la partida terminó. Es la base del análisis tras la partida.
- `chineseCheckersMove(rules, state, level)`: a dos jugadores y desde el nivel 3, alfa-beta con
  `chineseCheckersEvaluator` (diferencia de distancias a la meta) a 2, 3 o 4 medias jugadas; con más
  jugadores o en niveles bajos, la jugada que más acerca a la meta, al azar entre las 5, 3 o 2
  mejores según el nivel.

## Ejecución y depuración

### Desde la terminal
```bash
cd tablero_engine
dart pub get
dart test                    # Ejecuta los 44 tests de reglas, perft e IA
dart run example/main.dart   # Ejecuta partida de demostración
```

### Desde el IDE (VS Code / Antigravity)
En el panel **Ejecución y depuración** (`Ctrl+Shift+D`):
- **Engine: Tests unitarios**: ejecuta y depura los tests con breakpoints.
- **Engine: Ejemplo (main.dart)**: ejecuta la simulación con inspección de estado.

## Uso

```dart
const rules = ChessRules();
var state = rules.initialState();
final move = ChessEngine.fromSan(state.position, 'e4')!;
state = rules.apply(state, move);          // lanza ArgumentError si es ilegal
print(rules.result(state));                // null: la partida sigue
print(rules.claimableDraw(state));         // tablas reclamables (3 rep., 50 jug.)
```

Todos los juegos implementan `GameRules<S, M>` (`initialState`, `legalMoves`, `apply`, `result`), así que la IA, el historial y el deshacer son genéricos. Los estados son inmutables: deshacer = volver al estado anterior de una lista.

## Verificación

- Ajedrez: perft de 5 posiciones de referencia (inicial, Kiwipete, posiciones 3, 4 y 5).
- Damas: perft desde la posición inicial de las tres variantes y casos de captura por variante.
- Las reglas de captura y los números de perft se validaron con un prototipo independiente del mismo algoritmo.

## Pendiente

- Damas españolas: confirmar orientación del tablero y reglas de tablas con el reglamento oficial (`quietPliesForDraw` está en `null`).
- Damas internacionales: reglas de finales de 16 y 5 jugadas.
- Ajedrez: `canEverCheckmate` no detecta posiciones muertas por bloqueo de peones.
- IA: generación de jugadas con hacer/deshacer sobre un tablero mutable (siguiente salto de velocidad) y libro de aperturas.

## Integración con Flutter

Añade el paquete por ruta en la app:

```yaml
dependencies:
  tablero_engine:
    path: ../tablero_engine
```

La IA se ejecuta fuera del hilo de UI:

```dart
Future<ChessMove?> aiMove(ChessState state, int level) =>
    Isolate.run(() => chessAi(level).bestMove(state));
```

Esquema del controlador con Riverpod (la capa Flame solo lee `state` y llama a `play`):

```dart
class ChessController extends Notifier<ChessState> {
  static const rules = ChessRules();
  final _history = <ChessState>[];

  @override
  ChessState build() => rules.initialState();

  List<ChessMove> movesFrom(int square) =>
      rules.legalMoves(state).where((m) => m.from == square).toList();

  Future<void> play(ChessMove move) async {
    _history.add(state);
    state = rules.apply(state, move);
    if (rules.result(state) == null && state.toMove == 1) {
      final reply = await aiMove(state, 3);
      if (reply != null) state = rules.apply(state, reply);
    }
  }

  void undo() {
    if (_history.isNotEmpty) state = _history.removeLast();
  }
}
```
