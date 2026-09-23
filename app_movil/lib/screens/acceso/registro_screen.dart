import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../widgets/comunes.dart';

/// Registrarse. La cuenta queda PENDIENTE: la administradora la revisa y,
/// cuando la aprueba, a la persona le llega un correo avisándole que ya puede
/// entrar.
class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _documento = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _ciudad = TextEditingController(text: 'La Pintada');
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _repetir = TextEditingController();
  bool _ver = false;
  bool _aceptaDatos = false;

  @override
  void dispose() {
    for (final c in [_nombre, _documento, _telefono, _direccion, _ciudad, _correo, _clave, _repetir]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    if (!_aceptaDatos) {
      mostrarMensaje(context, 'Debes aceptar el tratamiento de datos personales.', error: true);
      return;
    }
    final r = await conCarga(
      context,
      Api.i.post('/api/auth/registro', {
        'nombre': _nombre.text.trim(),
        'documento': _documento.text.trim(),
        'telefono': _telefono.text.trim(),
        'direccion': _direccion.text.trim(),
        'ciudad': _ciudad.text.trim(),
        'correo': _correo.text.trim(),
        'password': _clave.text,
        'acepta_datos': true,
      }),
      avisarCambio: false,
    );
    if (r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined, size: 40),
        title: const Text('Solicitud enviada'),
        content: Text(r['mensaje'] ?? 'Te avisaremos por correo cuando tu cuenta esté aprobada.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
    if (mounted) Navigator.pop(context, _correo.text.trim());
  }

  void _verPolitica() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tratamiento de datos personales'),
        content: const SingleChildScrollView(
          child: Text(
            'Essence Don Aire (La Pintada, Antioquia) usará tu nombre, documento, teléfono, dirección y correo '
            'únicamente para gestionar tus pedidos, compras, pagos y facturas, y para contactarte sobre ellos.\n\n'
            'No compartimos tus datos con terceros. Puedes conocer, actualizar, rectificar o pedir la eliminación '
            'de tus datos escribiéndonos por WhatsApp, conforme a la Ley 1581 de 2012 (Habeas Data).',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            'Llena tus datos. La administradora revisará tu solicitud y te avisaremos por correo cuando puedas entrar.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const TituloSeccion('Tus datos'),
          TextFormField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre completo *', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe tu nombre completo' : null,
          ),
          espacio,
          TextFormField(
            controller: _documento,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Documento (opcional)', prefixIcon: Icon(Icons.badge_outlined)),
          ),
          espacio,
          TextFormField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Celular / WhatsApp *', prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) => RegExp(r'^[+()\d\s-]{7,20}$').hasMatch((v ?? '').trim()) ? null : 'Escribe un teléfono válido',
          ),
          espacio,
          TextFormField(
            controller: _direccion,
            decoration: const InputDecoration(labelText: 'Dirección', prefixIcon: Icon(Icons.home_outlined)),
          ),
          espacio,
          TextFormField(
            controller: _ciudad,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ciudad / vereda', prefixIcon: Icon(Icons.location_city_outlined)),
          ),
          const TituloSeccion('Tu acceso'),
          TextFormField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo *', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : 'Correo no válido',
          ),
          espacio,
          TextFormField(
            controller: _clave,
            obscureText: !_ver,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Contraseña (mínimo 8) *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(icon: Icon(_ver ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _ver = !_ver)),
            ),
            validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
          ),
          espacio,
          TextFormField(
            controller: _repetir,
            obscureText: !_ver,
            decoration: const InputDecoration(labelText: 'Repite la contraseña *', prefixIcon: Icon(Icons.lock_outline)),
            validator: (v) => v != _clave.text ? 'No coincide' : null,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _aceptaDatos,
            onChanged: (v) => setState(() => _aceptaDatos = v ?? false),
            title: const Text('Acepto el tratamiento de mis datos personales'),
            subtitle: GestureDetector(
              onTap: _verPolitica,
              child: Text('Leer la política', style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _enviar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.send),
            label: const Text('Enviar solicitud'),
          ),
        ]),
      ),
    );
  }
}
