import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modelos.dart';

/// Carrito de compras del Cliente.
///
/// Vive fuera de las pantallas (un solo carrito para toda la app), así que no
/// se pierde al cambiar de pestaña, al salir de un producto o al cerrar la
/// app: se guarda en el teléfono, uno por usuario. Es un ChangeNotifier: el
/// ícono con el número y la barra del carrito se redibujan solos.
class Carrito extends ChangeNotifier {
  Carrito._();
  static final Carrito i = Carrito._();

  final List<LineaCarrito> lineas = [];
  int? _usuario;

  String get _clave => 'carrito_$_usuario';
  bool get vacio => lineas.isEmpty;
  int get unidades => lineas.fold(0, (s, l) => s + l.cantidad);
  double get total => lineas.fold(0, (s, l) => s + l.subtotal);
  int cantidadDe(int idProducto) => lineas.where((l) => l.producto.id == idProducto).fold(0, (s, l) => s + l.cantidad);

  /// Al entrar un Cliente: carga su carrito guardado.
  Future<void> cargar(int idUsuario) async {
    if (_usuario == idUsuario && lineas.isNotEmpty) return;
    _usuario = idUsuario;
    lineas.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_clave);
      if (texto != null) {
        for (final e in jsonDecode(texto) as List) {
          final m = e as Map<String, dynamic>;
          lineas.add(LineaCarrito(Producto.desdeJson(m['producto'] as Map<String, dynamic>), cantidad: m['cantidad'] as int));
        }
      }
    } catch (_) {
      lineas.clear(); // guardado dañado: se empieza vacío
    }
    notifyListeners();
  }

  /// Al cerrar sesión: se suelta de memoria (queda guardado para la próxima).
  void soltar() {
    _usuario = null;
    lineas.clear();
    notifyListeners();
  }

  /// Agrega unidades. Devuelve false si se pasaría del stock disponible.
  bool agregar(Producto p, {int cantidad = 1}) {
    final i = lineas.indexWhere((l) => l.producto.id == p.id);
    final actual = i >= 0 ? lineas[i].cantidad : 0;
    if (actual + cantidad > p.stock) return false;
    if (i >= 0) {
      lineas[i].cantidad += cantidad;
    } else {
      lineas.add(LineaCarrito(p, cantidad: cantidad));
    }
    _cambio();
    return true;
  }

  void cambiarCantidad(LineaCarrito l, int cantidad) {
    if (cantidad <= 0) {
      lineas.remove(l);
    } else {
      l.cantidad = cantidad > l.producto.stock ? l.producto.stock : cantidad;
    }
    _cambio();
  }

  void quitar(LineaCarrito l) {
    lineas.remove(l);
    _cambio();
  }

  void vaciar() {
    lineas.clear();
    _cambio();
  }

  void _cambio() {
    notifyListeners();
    _guardar();
  }

  Future<void> _guardar() async {
    if (_usuario == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lineas.isEmpty) {
        await prefs.remove(_clave);
      } else {
        await prefs.setString(
          _clave,
          jsonEncode([
            for (final l in lineas) {'producto': l.producto.aJson(), 'cantidad': l.cantidad},
          ]),
        );
      }
    } catch (_) {/* si no se puede guardar, el carrito sigue en memoria */}
  }
}
