import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/api.dart';
import 'core/sesion.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

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
  await Sesion.i.restaurar();
  runApp(const EssenceApp());
}

const colorMarca = Color(0xFF7A2E55); // ciruela: el tono de la marca

class EssenceApp extends StatelessWidget {
  const EssenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final esquema = ColorScheme.fromSeed(seedColor: colorMarca);
    return MaterialApp(
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
      // La sesión decide qué se ve: login o la app. Al iniciar o cerrar
      // sesión, Sesion avisa y esto se vuelve a construir.
      home: ListenableBuilder(
        listenable: Sesion.i,
        builder: (_, __) => Sesion.i.activa
            // La key cambia con el usuario: si alguien cierra sesión y entra
            // otra persona con otro rol, las pestañas se arman desde cero.
            ? HomeShell(key: ValueKey(Sesion.i.usuario?.id))
            : const LoginScreen(),
      ),
    );
  }
}
