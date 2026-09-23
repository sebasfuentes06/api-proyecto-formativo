import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:essence_movil/screens/login_screen.dart';

/// Prueba de interfaz: la pantalla de login se dibuja y valida los campos
/// sin necesitar la API.
void main() {
  testWidgets('el login pide correo y contraseña', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Essence Don Aire'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });
}
