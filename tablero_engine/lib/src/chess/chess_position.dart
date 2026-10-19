/// Representación de una posición de ajedrez (Leyes del Ajedrez FIDE).
///
/// Tablero de 64 casillas: a1 = 0, b1 = 1 … h8 = 63.
/// Piezas: positivas = blancas, negativas = negras.
library;

abstract final class Piece {
  static const empty = 0;
  static const pawn = 1;
  static const knight = 2;
  static const bishop = 3;
  static const rook = 4;
  static const queen = 5;
  static const king = 6;
}

/// Color: 1 = blancas, -1 = negras.
abstract final class ChessColor {
  static const white = 1;
  static const black = -1;
}

/// Bits de derechos de enroque.
abstract final class Castling {
  static const whiteKing = 1; // K
  static const whiteQueen = 2; // Q
  static const blackKing = 4; // k
  static const blackQueen = 8; // q
}

const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

int square(int file, int rank) => rank * 8 + file;
int fileOf(int sq) => sq % 8;
int rankOf(int sq) => sq ~/ 8;

String squareName(int sq) =>
    '${String.fromCharCode(97 + fileOf(sq))}${rankOf(sq) + 1}';

int parseSquare(String name) {
  if (name.length != 2) throw FormatException('Casilla inválida: $name');
  final f = name.codeUnitAt(0) - 97;
  final r = name.codeUnitAt(1) - 49;
  if (f < 0 || f > 7 || r < 0 || r > 7) {
    throw FormatException('Casilla inválida: $name');
  }
  return square(f, r);
}

class ChessPosition {
  /// 64 casillas, a1 = 0.
  final List<int> board;

  /// 1 = mueven blancas, -1 = mueven negras.
  final int side;

  /// Combinación de bits de [Castling].
  final int castling;

  /// Casilla de captura al paso, o -1.
  final int ep;

  /// Medias jugadas desde la última captura o movimiento de peón.
  final int halfmove;

  /// Número de jugada completa (empieza en 1).
  final int fullmove;

  ChessPosition({
    required List<int> board,
    required this.side,
    required this.castling,
    required this.ep,
    required this.halfmove,
    required this.fullmove,
  }) : board = List.unmodifiable(board) {
    if (board.length != 64) throw ArgumentError('El tablero debe tener 64 casillas');
  }

  /// Constructor interno del motor: NO copia [board]. El llamador entrega una
  /// lista nueva y no vuelve a modificarla.
  ChessPosition.unsafe({
    required this.board,
    required this.side,
    required this.castling,
    required this.ep,
    required this.halfmove,
    required this.fullmove,
  });

  static final ChessPosition start = ChessPosition.fromFen(startFen);

  factory ChessPosition.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) throw FormatException('FEN incompleto: $fen');
    final board = List<int>.filled(64, Piece.empty);
    final rows = parts[0].split('/');
    if (rows.length != 8) throw FormatException('FEN con filas inválidas: $fen');
    const letters = {'p': 1, 'n': 2, 'b': 3, 'r': 4, 'q': 5, 'k': 6};
    for (var i = 0; i < 8; i++) {
      final rank = 7 - i;
      var file = 0;
      for (final ch in rows[i].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          file += digit;
          continue;
        }
        final type = letters[ch.toLowerCase()];
        if (type == null || file > 7) throw FormatException('FEN inválido: $fen');
        board[square(file, rank)] = ch == ch.toUpperCase() ? type : -type;
        file++;
      }
      if (file != 8) throw FormatException('FEN con fila incompleta: $fen');
    }
    final side = switch (parts[1]) {
      'w' => ChessColor.white,
      'b' => ChessColor.black,
      _ => throw FormatException('Turno inválido en FEN: $fen'),
    };
    var castling = 0;
    if (parts[2] != '-') {
      for (final ch in parts[2].split('')) {
        castling |= switch (ch) {
          'K' => Castling.whiteKing,
          'Q' => Castling.whiteQueen,
          'k' => Castling.blackKing,
          'q' => Castling.blackQueen,
          _ => throw FormatException('Enroque inválido en FEN: $fen'),
        };
      }
    }
    final ep = parts[3] == '-' ? -1 : parseSquare(parts[3]);
    final halfmove = parts.length > 4 ? int.parse(parts[4]) : 0;
    final fullmove = parts.length > 5 ? int.parse(parts[5]) : 1;
    return ChessPosition(
      board: board,
      side: side,
      castling: castling,
      ep: ep,
      halfmove: halfmove,
      fullmove: fullmove,
    );
  }

  /// Parte de colocación de piezas del FEN.
  String placementFen() {
    final sb = StringBuffer();
    for (var rank = 7; rank >= 0; rank--) {
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final v = board[square(file, rank)];
        if (v == 0) {
          empty++;
          continue;
        }
        if (empty > 0) {
          sb.write(empty);
          empty = 0;
        }
        final letter = 'pnbrqk'[v.abs() - 1];
        sb.write(v > 0 ? letter.toUpperCase() : letter);
      }
      if (empty > 0) sb.write(empty);
      if (rank > 0) sb.write('/');
    }
    return sb.toString();
  }

  String castlingFen() {
    if (castling == 0) return '-';
    final sb = StringBuffer();
    if (castling & Castling.whiteKing != 0) sb.write('K');
    if (castling & Castling.whiteQueen != 0) sb.write('Q');
    if (castling & Castling.blackKing != 0) sb.write('k');
    if (castling & Castling.blackQueen != 0) sb.write('q');
    return sb.toString();
  }

  String toFen() =>
      '${placementFen()} ${side == 1 ? 'w' : 'b'} ${castlingFen()} '
      '${ep < 0 ? '-' : squareName(ep)} $halfmove $fullmove';

  @override
  String toString() => toFen();
}
