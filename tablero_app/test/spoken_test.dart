import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/match/spoken.dart';

void main() {
  test('ajedrez en lenguaje natural', () {
    expect(Spoken.chess('Nf3'), 'Caballo a f3');
    expect(Spoken.chess('exd5'), 'Peón captura en d5');
    expect(Spoken.chess('e8=Q+'), 'Peón a e8, corona en dama, jaque');
    expect(Spoken.chess('Qh4#'), 'Dama a h4, jaque mate');
    expect(Spoken.chess('O-O'), 'Enroque corto');
    expect(Spoken.chess('O-O-O+'), 'Enroque largo, jaque');
    expect(Spoken.chess('Nbd2'), 'Caballo a d2');
  });

  test('damas en lenguaje natural', () {
    expect(Spoken.draughts('32-28', 0), 'De 32 a 28');
    expect(Spoken.draughts('28x19', 1), 'Captura de 28 a 19, toma 1 pieza');
    expect(Spoken.draughts('28x10', 2), 'Captura de 28 a 10, toma 2 piezas');
  });
}
