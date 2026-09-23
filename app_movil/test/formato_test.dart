import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:essence_movil/core/contacto.dart';
import 'package:essence_movil/core/formato.dart';
import 'package:essence_movil/models/modelos.dart';

/// Pruebas de las funciones puras de la app: `flutter test`
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('dinero usa punto de miles y sin decimales', () {
    expect(dinero(185000), '\$ 185.000');
    expect(dinero(1250000.4), '\$ 1.250.000');
  });

  test('aNum entiende los NUMERIC que llegan como texto', () {
    expect(aNum('185000.00'), 185000);
    expect(aNum(null), 0);
    expect(aNum(12), 12);
  });

  test('leerDinero ignora símbolos y puntos', () {
    expect(leerDinero('\$ 1.250.000'), 1250000);
    expect(leerDinero(''), isNull);
  });

  test('teléfono colombiano se convierte al formato de WhatsApp', () {
    expect(telefonoWhatsApp('300 123 4567'), '573001234567');
    expect(telefonoWhatsApp('+57 300 123 4567'), '573001234567');
    expect(telefonoWhatsApp(null), isNull);
  });

  test('Venta.desdeJson calcula si debe', () {
    final v = Venta.desdeJson({
      'id_venta': 1,
      'numero_factura': 'FV-000001',
      'estado': 'confirmada',
      'subtotal': '100000.00',
      'descuento': '0.00',
      'total': '100000.00',
      'pagado': '40000.00',
      'saldo': '60000.00',
      'estado_pago': 'parcial',
      'id_cliente': 3,
      'cliente': 'Laura',
    });
    expect(v.debe, isTrue);
    expect(v.saldo, 60000);
  });

  test('el carrito calcula subtotales con precio especial', () {
    final p = Producto.desdeJson({
      'id_producto': 1, 'sku': 'A', 'nombre': 'Rosa', 'precio': '100000.00', 'stock': 5, 'stock_minimo': 1,
      'estado': true, 'id_categoria': 1, 'categoria': 'Floral', 'id_proveedor': 1, 'proveedor': 'X',
    });
    final l = LineaCarrito(p, cantidad: 2, precio: 90000);
    expect(l.subtotal, 180000);
    expect(l.aJson()['precio_unitario'], 90000);
  });
}
