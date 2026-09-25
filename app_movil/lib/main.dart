import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/api.dart';
import 'core/sesion.dart';
import 'screens/acceso/landing_screen.dart';
import 'screens/home_shell.dart';

/// Punto de entrada de la app móvil de Essence Don Aire.
///
/// Uso exclusivo del administrador (ficha del proyecto, "Proceso Móvil"):
/// clientes, catálogo, pedidos, ventas y pagos/abonos desde el celular.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nombres de meses y días en español para las fechas.
  await initializeDateFormatting('es');
  // Si la API dice que el token venció, se cierra la sesión y main vuelve
  // a mostrar el login.
  Api.i.alVencerSesion = () => Sesion.i.cerrar();
  try {
    await Sesion.i.restaurar();
  } catch (e) {
    // Nunca dejar la app en negro por un problema al leer la sesión.
    debugPrint('No se pudo restaurar la sesión: $e');
  }
  runApp(const EssenceApp());
}

const colorMarca = Color(0xFF7A2E55); // ciruela: el tono de la marca

class EssenceApp extends StatefulWidget {
  const EssenceApp({super.key});

  @override
  State<EssenceApp> createState() => _EssenceAppState();
}

class _EssenceAppState extends State<EssenceApp> {
  final _navegador = GlobalKey<NavigatorState>();
  bool _activa = Sesion.i.activa;

  @override
  void initState() {
    super.initState();
    Sesion.i.addListener(_alCambiarSesion);
  }

  @override
  void dispose() {
    Sesion.i.removeListener(_alCambiarSesion);
    super.dispose();
  }

  /// Al entrar (desde el login que se abrió sobre la vitrina) o al salir
  /// (desde cualquier pantalla), se cierran las pantallas abiertas encima
  /// para que quede solo la de inicio que corresponde.
  void _alCambiarSesion() {
    if (Sesion.i.activa == _activa) return;
    _activa = Sesion.i.activa;
    _navegador.currentState?.popUntil((ruta) => ruta.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final esquema = ColorScheme.fromSeed(seedColor: colorMarca);
    return MaterialApp(
      navigatorKey: _navegador,
      title: 'Essence Don Aire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: esquema,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: esquema.surface,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      // La sesión decide qué se ve: la vitrina pública o la app. Al iniciar o cerrar
      // sesión, Sesion avisa y esto se vuelve a construir.
      home: ListenableBuilder(
        listenable: Sesion.i,
        builder: (_, __) => Sesion.i.activa
            // La key cambia con el usuario: si alguien cierra sesión y entra
            // otra persona con otro rol, las pestañas se arman desde cero.
            ? HomeShell(key: ValueKey(Sesion.i.usuario?.id))
            : const LandingScreen(),
      ),
    );
  }
}
