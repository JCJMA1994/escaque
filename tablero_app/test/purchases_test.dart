import 'package:flutter_test/flutter_test.dart';
import 'package:tablero_app/purchases/purchases.dart';

/// Debe coincidir con PurchaseService.accountHash del servidor (mismo valor en
/// tablero_server/test/purchases_test.dart): si no, toda compra con cuenta se
/// rechazaría como «de otra cuenta».
void main() {
  test('identificador de cuenta ofuscado igual que en el servidor', () {
    expect(AdFreeController.accountHash('ana'), 'b4d31b99ce2a24f26f45134ed73eb4051125746c');
  });
}
