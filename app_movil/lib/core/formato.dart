import 'package:intl/intl.dart';

/// Conversión y formato de los datos que llegan de la API.
///
/// PostgreSQL devuelve los NUMERIC como texto ("185000.00"), así que todo
/// número pasa por [aNum] antes de usarse.

double aNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int aInt(dynamic v) => aNum(v).round();

DateTime? aFecha(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

// Se formatea en inglés y se cambian las comas por puntos: el formato "es"
// de intl no agrupa los miles en números de 4 cifras (1500 en vez de 1.500).
final _miles = NumberFormat('#,##0', 'en_US');

/// 185000 -> "$ 185.000"
String dinero(num v) => '\$ ${_miles.format(v.round()).replaceAll(',', '.')}';

String fecha(DateTime? d) => d == null ? '—' : DateFormat("d MMM y", 'es').format(d);
String fechaHora(DateTime? d) => d == null ? '—' : DateFormat("d MMM y · h:mm a", 'es').format(d);
String fechaApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Deja solo dígitos: "$ 1.250.000" -> 1250000
int? leerDinero(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^0-9]'), '');
  return limpio.isEmpty ? null : int.parse(limpio);
}

String capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const nombresMetodo = {
  'efectivo': 'Efectivo',
  'transferencia': 'Transferencia',
  'nequi': 'Nequi',
  'daviplata': 'Daviplata',
  'tarjeta': 'Tarjeta',
  'wompi': 'Wompi',
};

const nombresCanal = {'whatsapp': 'WhatsApp', 'punto_fisico': 'Punto físico'};
