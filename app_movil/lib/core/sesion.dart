import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class Usuario {
  Usuario({required this.id, required this.nombre, required this.correo, required this.rol});
  final int id;
  final String nombre;
  final String correo;
  final String rol;

  factory Usuario.desdeJson(Map<String, dynamic> j) => Usuario(
        id: (j['id_usuario'] as num).toInt(),
        nombre: j['nombre'] ?? '',
        correo: j['correo'] ?? '',
        rol: j['rol'] ?? '',
      );
}

/// Estado de la sesión. Es un ChangeNotifier: cuando cambia (login o
/// logout), main.dart lo escucha y muestra la pantalla que corresponde.
class Sesion extends ChangeNotifier {
  Sesion._();
  static final Sesion i = Sesion._();

  static const _clave = 'token';
  Usuario? usuario;
  bool get activa => Api.i.token != null;

  /// Al abrir la app: si hay un token guardado, se valida contra la API.
  Future<void> restaurar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_clave);
    if (token == null) return;
    Api.i.token = token;
    try {
      final r = await Api.i.get('/api/auth/yo');
      usuario = Usuario.desdeJson(r['datos']);
    } on ApiException catch (e) {
      // 401: el token venció. Otro error (sin internet): se deja entrar y
      // cada pantalla mostrará el problema con su botón de reintentar.
      if (e.status == 401) {
        Api.i.token = null;
        await prefs.remove(_clave);
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
    notifyListeners();
  }

  Future<void> cerrar() async {
    Api.i.token = null;
    usuario = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
    notifyListeners();
  }
}
