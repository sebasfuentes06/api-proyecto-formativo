import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error que devuelve la API, ya traducido a un mensaje para mostrar.
class ApiException implements Exception {
  ApiException(this.status, this.mensaje, [this.detalles]);

  /// Código HTTP. 0 = no hubo respuesta (sin internet, tiempo agotado).
  final int status;
  final String mensaje;
  final Map<String, dynamic>? detalles;

  /// Mensaje principal + los detalles por campo, en líneas.
  String get completo {
    if (detalles == null || detalles!.isEmpty) return mensaje;
    return '$mensaje\n${detalles!.values.map((v) => '• $v').join('\n')}';
  }

  @override
  String toString() => completo;
}

/// Una página de resultados de un listado.
class Pagina<T> {
  Pagina(this.items, this.total, this.totalPaginas, [this.resumen = const {}]);
  final List<T> items;
  final int total;
  final int totalPaginas;
  final Map<String, dynamic> resumen;
}

/// Cliente HTTP de la app. Todas las pantallas hablan con la API por aquí.
///
/// Se encarga de: armar la URL, mandar el token, convertir el JSON y
/// transformar cualquier error en un ApiException con un mensaje legible.
class Api {
  Api._();
  static final Api i = Api._();

  String? token;

  /// Se llama cuando la API responde 401 (token vencido): la app vuelve al login.
  void Function()? alVencerSesion;

  /// Vercel + Neon pueden tardar unos segundos en "despertar" si llevan rato
  /// sin uso, por eso el tiempo de espera es generoso.
  static const _espera = Duration(seconds: 40);

  Uri uri(String ruta, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('${Config.apiUrl}$ruta').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _cabeceras => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String ruta, {Map<String, dynamic>? query}) =>
      _enviar(() => http.get(uri(ruta, query), headers: _cabeceras));

  Future<Map<String, dynamic>> post(String ruta, [Map<String, dynamic>? cuerpo]) =>
      _enviar(() => http.post(uri(ruta), headers: _cabeceras, body: jsonEncode(cuerpo ?? {})));

  Future<Map<String, dynamic>> put(String ruta, Map<String, dynamic> cuerpo) =>
      _enviar(() => http.put(uri(ruta), headers: _cabeceras, body: jsonEncode(cuerpo)));

  Future<Map<String, dynamic>> delete(String ruta) =>
      _enviar(() => http.delete(uri(ruta), headers: _cabeceras));

  /// Pide un listado paginado y convierte cada fila con [desdeJson].
  Future<Pagina<T>> pagina<T>(
    String ruta,
    T Function(Map<String, dynamic>) desdeJson, {
    Map<String, dynamic>? query,
  }) async {
    final r = await get(ruta, query: query);
    final filas = (r['datos'] as List? ?? []).cast<Map<String, dynamic>>();
    final pag = r['paginacion'] as Map<String, dynamic>? ?? {};
    return Pagina(
      filas.map(desdeJson).toList(),
      (pag['total'] as num?)?.toInt() ?? filas.length,
      (pag['totalPaginas'] as num?)?.toInt() ?? 1,
      (r['resumen'] as Map<String, dynamic>?) ?? {},
    );
  }

  Future<Map<String, dynamic>> _enviar(Future<http.Response> Function() peticion) async {
    http.Response respuesta;
    try {
      respuesta = await peticion().timeout(_espera);
    } on TimeoutException {
      throw ApiException(0, 'La API tardó demasiado en responder. Revisa tu conexión e inténtalo de nuevo.');
    } on SocketException {
      throw ApiException(0, 'Sin conexión a internet.');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'No se pudo conectar con la API (${e.message}).');
    } on HandshakeException {
      throw ApiException(0, 'Conexión segura rechazada. Revisa la fecha y hora del teléfono.');
    } catch (e) {
      throw ApiException(0, 'No se pudo conectar con la API ($e).');
    }

    Map<String, dynamic> datos;
    try {
      datos = jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(respuesta.statusCode, 'Respuesta inesperada del servidor (${respuesta.statusCode}).');
    }

    if (respuesta.statusCode >= 400 || datos['ok'] == false) {
      if (respuesta.statusCode == 401 && token != null) alVencerSesion?.call();
      final detalles = datos['detalles'];
      throw ApiException(
        respuesta.statusCode,
        (datos['error'] ?? datos['mensaje'] ?? 'Error ${respuesta.statusCode}').toString(),
        detalles is Map<String, dynamic> ? detalles : null,
      );
    }
    return datos;
  }
}
