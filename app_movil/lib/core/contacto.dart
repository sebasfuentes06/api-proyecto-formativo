import 'package:url_launcher/url_launcher.dart';

/// Abre WhatsApp, el marcador o el navegador.

/// "300 123 4567" -> "573001234567" (formato internacional que pide wa.me).
String? telefonoWhatsApp(String? telefono) {
  if (telefono == null) return null;
  var d = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.length == 10 && d.startsWith('3')) d = '57$d';
  return d;
}

/// Abre un chat de WhatsApp con el mensaje escrito. Sin teléfono, abre
/// WhatsApp para que se elija el contacto.
Future<bool> abrirWhatsApp(String? telefono, String mensaje) {
  final numero = telefonoWhatsApp(telefono) ?? '';
  final url = Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(mensaje)}');
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<bool> llamar(String telefono) =>
    launchUrl(Uri(scheme: 'tel', path: telefono.replaceAll(' ', '')));

Future<bool> abrirUrl(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
