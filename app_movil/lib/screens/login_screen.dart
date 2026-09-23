import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/sesion.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _ver = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await Sesion.i.iniciar(_correo.text, _clave.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: tema.colorScheme.primaryContainer,
                      child: Icon(Icons.local_florist, size: 44, color: tema.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 16),
                    Text('Essence Don Aire', textAlign: TextAlign.center, style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Ventas, pedidos y pagos', textAlign: TextAlign.center, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.outline)),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _correo,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                      validator: (v) => (v ?? '').contains('@') ? null : 'Escribe tu correo',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _clave,
                      obscureText: !_ver,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _entrar(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _ver = !_ver),
                        ),
                      ),
                      validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: tema.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!, style: TextStyle(color: tema.colorScheme.onErrorContainer)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _cargando ? null : _entrar,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _cargando
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Ingresar'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Administrador · Vendedor · Cliente\n${Config.apiUrl.replaceFirst('https://', '')}',
                      textAlign: TextAlign.center,
                      style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

