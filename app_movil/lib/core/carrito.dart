import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modelos.dart';

/// Carrito de compras (igual que en la web).
///
/// Vive fuera de las pantallas (un solo carrito para toda la app), así que no
/// se pierde al cambiar de pestaña, al salir de un producto o al cerrar la
/// app: se guarda en el teléfono, uno por usuario. Es un ChangeNotifier: el
/// ícono con el número y la barra del carrito se redibujan solos.
///
/// Un visitante sin sesión también tiene carrito (el de la vitrina). Cuando
/// entra como Cliente, lo que agregó pasa a su carrito y se le abre para que
/// termine el pedido.
class Carrito extends ChangeNotifier {
  Carrito._();
  static final Carrito i = Carrito._();

  static const _invitado = 'invitado';

  final List<LineaCarrito> lineas = [];
  String? _dueno;

  /// La vitrina la marca cuando el visitante toca "Registrarme para
  /// continuar": al entrar, la app le abre el carrito.
  bool abrirAlEntrar = false;

  String _clave(String dueno) => 'carrito_$dueno';
  bool get vacio => lineas.isEmpty;
  int get unidades => lineas.fold(0, (s, l) => s + l.cantidad);
  double get total => lineas.fold(0, (s, l) => s + l.subtotal);
  int cantidadDe(int idProducto) => lineas.where((l) => l.producto.id == idProducto).fold(0, (s, l) => s + l.cantidad);

  Future<List<LineaCarrito>> _leer(SharedPreferences prefs, String dueno) async {
    final texto = prefs.getString(_clave(dueno));
    if (texto == null) return [];
    try {
      return [
        for (final e in jsonDecode(texto) as List)
          LineaCarrito(
            Producto.desdeJson((e as Map<String, dynamic>)['producto'] as Map<String, dynamic>),
            cantidad: e['cantidad'] as int,
          ),
      ];
    } catch (_) {
      return []; // guardado dañado: se empieza vacío
    }
  }

  /// Carrito del visitante de la vitrina (sin sesión).
  Future<void> cargarInvitado() => _cargar(_invitado);

  /// Al entrar: carga el carrito guardado de esa persona. Si es un Cliente y
  /// venía con un carrito de visitante, se suman (sin pasar el stock).
  Future<void> cargar(int idUsuario, {bool unirInvitado = false}) => _cargar('$idUsuario', unirInvitado: unirInvitado);

  Future<void> _cargar(String dueno, {bool unirInvitado = false}) async {
    if (_dueno == dueno && lineas.isNotEmpty) return;
    _dueno = dueno;
    lineas.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      lineas.addAll(await _leer(prefs, dueno));
      if (unirInvitado && dueno != _invitado) {
        final invitado = await _leer(prefs, _invitado);
        for (final l in invitado) {
          final i = lineas.indexWhere((x) => x.producto.id == l.producto.id);
          if (i >= 0) {
            final suma = lineas[i].cantidad + l.cantidad;
            lineas[i].cantidad = suma > l.producto.stock ? l.producto.stock : suma;
          } else {
            lineas.add(l);
          }
        }
        if (invitado.isNotEmpty) {
          await prefs.remove(_clave(_invitado));
          await _guardar();
        }
      }
    } catch (_) {
      lineas.clear();
    }
    notifyListeners();
  }

  /// Al cerrar sesión: se suelta de memoria (queda guardado para la próxima).
  /// Solo si el carrito en memoria es de esa persona: la vitrina pudo haber
  /// cargado ya el del visitante.
  void soltar(int idUsuario) {
    if (_dueno != '$idUsuario') return;
    _dueno = null;
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
    final dueno = _dueno;
    if (dueno == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lineas.isEmpty) {
        await prefs.remove(_clave(dueno));
      } else {
        await prefs.setString(
          _clave(dueno),
          jsonEncode([
            for (final l in lineas) {'producto': l.producto.aJson(), 'cantidad': l.cantidad},
          ]),
        );
      }
    } catch (_) {/* si no se puede guardar, el carrito sigue en memoria */}
  }
}
