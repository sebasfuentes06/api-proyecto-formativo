import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../widgets/comunes.dart';

/// "¿Olvidaste tu contraseña?" en dos pasos:
///   1. Escribes tu correo y te llega un código de 6 dígitos.
///   2. Escribes el código y tu contraseña nueva.
class RecuperarScreen extends StatefulWidget {
  const RecuperarScreen({super.key, this.correoInicial});
  final String? correoInicial;

  @override
  State<RecuperarScreen> createState() => _RecuperarScreenState();
}

class _RecuperarScreenState extends State<RecuperarScreen> {
  final _formCorreo = GlobalKey<FormState>();
  final _formCodigo = GlobalKey<FormState>();
  late final _correo = TextEditingController(text: widget.correoInicial);
  final _codigo = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  bool _codigoEnviado = false;
  bool _ver = false;
  int _esperar = 0;
  Timer? _reloj;

  @override
  void dispose() {
    _reloj?.cancel();
    for (final c in [_correo, _codigo, _nueva, _repetir]) {
      c.dispose();
    }
    super.dispose();
  }

  void _arrancarEspera(int segundos) {
    _reloj?.cancel();
    setState(() => _esperar = segundos);
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _esperar <= 1) {
        t.cancel();
        if (mounted) setState(() => _esperar = 0);
        return;
      }
      setState(() => _esperar--);
    });
  }

  Future<void> _pedirCodigo() async {
    if (!_formCorreo.currentState!.validate()) return;
    final r = await conCarga(context, Api.i.post('/api/auth/olvide', {'correo': _correo.text.trim()}), avisarCambio: false);
    if (r == null || !mounted) return;
    final datos = (r['datos'] as Map<String, dynamic>?) ?? {};
    setState(() => _codigoEnviado = true);
    _arrancarEspera((datos['reenviar_en'] as num?)?.toInt() ?? 60);
    mostrarMensaje(context, r['mensaje'] ?? 'Revisa tu correo.');
  }

  Future<void> _cambiar() async {
    if (!_formCodigo.currentState!.validate()) return;
    final r = await conCarga(
      context,
      Api.i.post('/api/auth/restablecer', {'correo': _correo.text.trim(), 'codigo': _codigo.text.trim(), 'nueva': _nueva.text}),
      avisarCambio: false,
    );
    if (r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: verde, size: 40),
        title: const Text('Contraseña actualizada'),
        content: const Text('Ya puedes iniciar sesión con tu contraseña nueva.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ir a iniciar sesión'))],
      ),
    );
    if (mounted) Navigator.pop(context, _correo.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          CircleAvatar(child: Text(_codigoEnviado ? '2' : '1')),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _codigoEnviado ? 'Escribe el código que te llegó y tu contraseña nueva.' : 'Te enviaremos un código de 6 dígitos a tu correo.',
              style: tema.textTheme.titleMedium,
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Form(
          key: _formCorreo,
          child: TextFormField(
            controller: _correo,
            enabled: !_codigoEnviado,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo de tu cuenta', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : 'Correo no válido',
          ),
        ),
        const SizedBox(height: 16),
        if (!_codigoEnviado)
          FilledButton.icon(
            onPressed: _pedirCodigo,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.send),
            label: const Text('Enviar código'),
          )
        else
          Form(
            key: _formCodigo,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _codigo,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Código de 6 dígitos', counterText: ''),
                validator: (v) => (v ?? '').length != 6 ? 'El código tiene 6 números' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nueva,
                obscureText: !_ver,
                decoration: InputDecoration(
                  labelText: 'Contraseña nueva (mínimo 8)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(icon: Icon(_ver ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _ver = !_ver)),
                ),
                validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _repetir,
                obscureText: !_ver,
                decoration: const InputDecoration(labelText: 'Repite la contraseña nueva', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => v != _nueva.text ? 'No coincide' : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cambiar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.key),
                label: const Text('Cambiar contraseña'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _esperar > 0 ? null : _pedirCodigo,
                child: Text(_esperar > 0 ? 'Reenviar código en $_esperar s' : 'Reenviar código'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _codigoEnviado = false;
                  _codigo.clear();
                }),
                child: const Text('Usar otro correo'),
              ),
              Text(
                'El código vence en 15 minutos. Si no lo ves, revisa la carpeta de spam.',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
              ),
            ]),
          ),
      ]),
    );
  }
}
