/// Tablero de estrella de damas chinas: 121 casillas en coordenadas cúbicas
/// (x + y + z = 0). Hexágono central de radio 4 más seis puntas de 10 casillas.
library;

class Hex {
  final int x, y, z;
  const Hex(this.x, this.y, this.z);

  Hex operator +(Hex o) => Hex(x + o.x, y + o.y, z + o.z);
  Hex scale(int k) => Hex(x * k, y * k, z * k);
  int coord(int i) => i == 0 ? x : (i == 1 ? y : z);
  int distanceTo(Hex o) {
    final dx = (x - o.x).abs(), dy = (y - o.y).abs(), dz = (z - o.z).abs();
    return dx > dy ? (dx > dz ? dx : dz) : (dy > dz ? dy : dz);
  }

  /// Coordenadas axiales para dibujar: q = x, r = z.
  int get q => x;
  int get r => z;

  @override
  bool operator ==(Object other) =>
      other is Hex && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Hex($x, $y, $z)';
}

class StarBoard {
  static const directions = [
    Hex(1, -1, 0), Hex(1, 0, -1), Hex(0, 1, -1),
    Hex(-1, 1, 0), Hex(-1, 0, 1), Hex(0, -1, 1),
  ];

  /// Puntas en orden circular: (coordenada, signo). La opuesta de k es k + 3.
  static const _corners = [(0, 1), (2, -1), (1, 1), (0, -1), (2, 1), (1, -1)];

  /// Las 121 casillas.
  final List<Hex> cells;

  /// Índices de las casillas de cada punta (6 × 10).
  final List<List<int>> corners;

  /// Vecinos de cada casilla.
  final List<List<int>> neighbors;

  /// Saltos posibles desde cada casilla: (casilla saltada, aterrizaje).
  final List<List<(int, int)>> jumps;

  /// Casilla extrema de cada punta (la más alejada del centro).
  final List<int> tips;

  final Map<Hex, int> _index;

  StarBoard._(this.cells, this.corners, this.neighbors, this.jumps, this.tips,
      this._index);

  static final StarBoard instance = StarBoard._build();

  int? indexOf(Hex h) => _index[h];

  static bool _inCorner(Hex h, int k) {
    final (i, sign) = _corners[k];
    final main = h.coord(i) * sign;
    if (main < 5 || main > 8) return false;
    for (var j = 0; j < 3; j++) {
      if (j == i) continue;
      final o = h.coord(j) * sign;
      if (o < -4 || o > -1) return false;
    }
    return true;
  }

  factory StarBoard._build() {
    final cells = <Hex>[];
    for (var x = -8; x <= 8; x++) {
      for (var y = -8; y <= 8; y++) {
        final z = -x - y;
        if (z.abs() > 8) continue;
        final h = Hex(x, y, z);
        final inHexagon = x.abs() <= 4 && y.abs() <= 4 && z.abs() <= 4;
        if (inHexagon || List.generate(6, (k) => _inCorner(h, k)).contains(true)) {
          cells.add(h);
        }
      }
    }
    final index = {for (var i = 0; i < cells.length; i++) cells[i]: i};
    final corners = List.generate(
      6,
      (k) => [for (var i = 0; i < cells.length; i++) if (_inCorner(cells[i], k)) i],
    );
    final neighbors = [
      for (final h in cells)
        [for (final d in directions) if (index.containsKey(h + d)) index[h + d]!]
    ];
    final jumps = [
      for (final h in cells)
        [
          for (final d in directions)
            if (index.containsKey(h + d) && index.containsKey(h + d.scale(2)))
              (index[h + d]!, index[h + d.scale(2)]!)
        ]
    ];
    final tips = [
      for (var k = 0; k < 6; k++)
        corners[k].firstWhere((i) => cells[i].coord(_corners[k].$1).abs() == 8)
    ];
    assert(cells.length == 121);
    return StarBoard._(cells, corners, neighbors, jumps, tips, index);
  }
}
