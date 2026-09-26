import 'package:essence_movil/core/carrito.dart';
import 'package:essence_movil/models/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

Producto producto(int id, double precio, int stock) => Producto(
      id: id,
      sku: 'P$id',
      nombre: 'Perfume $id',
      precio: precio,
      stock: stock,
      stockMinimo: 1,
      estado: true,
      idCategoria: 1,
      categoria: 'Floral',
      idProveedor: 1,
      proveedor: 'Proveedor',
    );

void main() {
  setUp(() => Carrito.i.vaciar());

  test('suma unidades del mismo producto y calcula el total', () {
    final a = producto(1, 100000, 5);
    final b = producto(2, 50000, 5);
    Carrito.i.agregar(a);
    Carrito.i.agregar(a);
    Carrito.i.agregar(b);
    expect(Carrito.i.lineas.length, 2);
    expect(Carrito.i.unidades, 3);
    expect(Carrito.i.total, 250000);
  });

  test('no deja pasar del stock', () {
    final a = producto(1, 100000, 2);
    expect(Carrito.i.agregar(a, cantidad: 2), isTrue);
    expect(Carrito.i.agregar(a), isFalse);
    expect(Carrito.i.unidades, 2);
  });

  test('bajar a 0 quita el producto', () {
    final a = producto(1, 100000, 5);
    Carrito.i.agregar(a);
    Carrito.i.cambiarCantidad(Carrito.i.lineas.first, 0);
    expect(Carrito.i.vacio, isTrue);
  });
}
