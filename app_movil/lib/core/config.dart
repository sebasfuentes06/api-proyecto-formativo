/// Configuración de la app.
///
/// La URL de la API se puede cambiar sin tocar código al correr la app:
///   flutter run --dart-define=API_URL=http://10.0.2.2:3000
/// (10.0.2.2 es "localhost de tu PC" visto desde el emulador de Android).
class Config {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api-proyecto-formativo.vercel.app',
  );

  // Datos del negocio (ficha del proyecto). Salen en la factura y reportes.
  static const String negocio = 'Essence Don Aire';
  static const String direccion = 'Avenida 30 # 31-16, La Pintada, Antioquia';
  static const String telefono = '311 452 2577';
}
