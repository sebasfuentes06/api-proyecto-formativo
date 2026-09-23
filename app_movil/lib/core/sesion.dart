import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Roles del proyecto (los mismos de la app web).
class Rol {
  static const admin = 'Administrador';
  static const vendedor = 'Vendedor';
  static const cliente = 'Cliente';
  static const todos = [admin, vendedor, cliente];
}

class Usuario {
  Usuario({required this.id, required this.nombre, required this.correo, required this.rol, this.idCliente});
  final int id;
  final String nombre;
  final String correo;
  final String rol;

  /// Solo para el rol Cliente: su ficha en la tabla de clientes.
  final int? idCliente;

  Map<String, dynamic> aJson() => {'id_usuario': id, 'nombre': nombre, 'correo': correo, 'rol': rol, 'id_cliente': idCliente};

  factory Usuario.desdeJson(Map<String, dynamic> j) => Usuario(
        id: (j['id_usuario'] as num).toInt(),
        nombre: j['nombre'] ?? '',
        correo: j['correo'] ?? '',
        rol: j['rol'] ?? '',
        idCliente: (j['id_cliente'] as num?)?.toInt(),
      );
}

/// Estado de la sesión. Es un ChangeNotifier: cuando cambia (login o
/// logout), main.dart lo escucha y muestra la pantalla que corresponde.
class Sesion extends ChangeNotifier {
  Sesion._();
  static final Sesion i = Sesion._();

  static const _clave = 'token';
  static const _claveUsuario = 'usuario';
  Usuario? usuario;
  bool get activa => Api.i.token != null;

  // Atajos para decidir qué mostrar. La API igual valida cada permiso: esto
  // solo evita mostrar botones que responderían "no tienes permiso".
  bool get esAdmin => usuario?.rol == Rol.admin;
  bool get esVendedor => usuario?.rol == Rol.vendedor;
  bool get esCliente => usuario?.rol == Rol.cliente;

  /// Administrador o Vendedor: el equipo que atiende la tienda.
  bool get esEquipo => esAdmin || esVendedor;

  /// Al abrir la app: si hay un token guardado, se valida contra la API.
  Future<void> restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_clave);
    if (token == null) return;
    Api.i.token = token;
    // Primero el usuario guardado: sin internet, la app igual sabe qué rol
    // tiene y qué pestañas mostrar.
    final guardado = prefs.getString(_claveUsuario);
    if (guardado != null) usuario = Usuario.desdeJson(jsonDecode(guardado));
    try {
      final r = await Api.i.get('/api/auth/yo');
      usuario = Usuario.desdeJson(r['datos']);
      await prefs.setString(_claveUsuario, jsonEncode(usuario!.aJson()));
    } on ApiException catch (e) {
      // 401: el token venció. Otro error (sin internet): se deja entrar y
      // cada pantalla mostrará el problema con su botón de reintentar.
      if (e.status == 401 || e.status == 403 || usuario == null) {
        Api.i.token = null;
        usuario = null;
        await prefs.remove(_clave);
        await prefs.remove(_claveUsuario);
      }
    }
  }

  Future<void> iniciar(String correo, String password) async {
    final r = await Api.i.post('/api/auth/login', {'correo': correo.trim(), 'password': password});
    final datos = r['datos'] as Map<String, dynamic>;
    Api.i.token = datos['token'];
    usuario = Usuario.desdeJson(datos['usuario']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, Api.i.token!);
    await prefs.setString(_claveUsuario, jsonEncode(usuario!.aJson()));
    notifyListeners();
  }

  Future<void> cerrar() async {
    Api.i.token = null;
    usuario = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
    await prefs.remove(_claveUsuario);
    notifyListeners();
  }
}
