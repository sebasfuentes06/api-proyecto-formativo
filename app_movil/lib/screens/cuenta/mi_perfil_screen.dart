import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/sesion.dart';
import '../../widgets/campos_persona.dart';
import '../../widgets/comunes.dart';

/// "Mi perfil" (los tres roles, igual que en la web): datos personales,
/// verificación del correo y cambio de contraseña.
class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: Sesion.i.usuario?.nombre);
  late final _telefono = TextEditingController(text: Sesion.i.usuario?.telefono);

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final r = await conCarga(
      context,
      Api.i.put('/api/auth/perfil', {'nombre': _nombre.text.trim(), 'telefono': _telefono.text.trim()}),
      avisarCambio: false,
    );
    if (r == null || !mounted) return;
    await Sesion.i.actualizar(r['datos'] as Map<String, dynamic>);
    if (mounted) mostrarMensaje(context, 'Cambios guardados.');
  }

  @override
  Widget build(BuildContext context) {
    final u = Sesion.i.usuario;
    final tema = Theme.of(context);
    final iniciales = (u?.nombre ?? '?').trim().split(RegExp(r'\s+')).take(2).map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListenableBuilder(
        listenable: Sesion.i,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              CircleAvatar(radius: 38, backgroundColor: tema.colorScheme.primary, child: Text(iniciales, style: TextStyle(fontSize: 26, color: tema.colorScheme.onPrimary))),
              const SizedBox(height: 10),
              Text(u?.nombre ?? '', style: tema.textTheme.titleLarge),
              Text(u?.correo ?? '', style: TextStyle(color: tema.colorScheme.outline)),
              const SizedBox(height: 6),
              Etiqueta(u?.rol ?? '', color: tema.colorScheme.primary, icono: Icons.shield_outlined),
              const SizedBox(height: 6),
              Text('El rol lo asigna un administrador y no puede cambiarse desde aquí.',
                  textAlign: TextAlign.center, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
            ]),
          ),
          const TituloSeccion('Datos personales'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre completo *', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'El nombre es obligatorio' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: u?.correo,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.mail_outline),
                    helperText: 'El correo es tu usuario de acceso: no se cambia desde aquí.',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _telefono,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: const InputDecoration(labelText: 'Teléfono', hintText: '3001234567', prefixIcon: Icon(Icons.phone_iphone)),
                  validator: (v) => (v ?? '').trim().isEmpty ? null : validarCelular(v),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _guardar, icon: const Icon(Icons.save), label: const Text('Guardar cambios')),
              ]),
            ),
          ),
          const TituloSeccion('Seguridad'),
          const _VerificarCorreo(),
          Card(
            child: ListTile(
              leading: Icon(Icons.key_outlined, color: tema.colorScheme.primary),
              title: const Text('Contraseña'),
              subtitle: const Text('Cámbiala cuando quieras. Te pediremos la contraseña actual.'),
              trailing: OutlinedButton(onPressed: () => cambiarClave(context), child: const Text('Cambiar')),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Tarjeta para verificar el correo con un código de 6 dígitos.
class _VerificarCorreo extends StatefulWidget {
  const _VerificarCorreo();

  @override
  State<_VerificarCorreo> createState() => _VerificarCorreoState();
}

class _VerificarCorreoState extends State<_VerificarCorreo> {
  final _codigo = TextEditingController();
  bool _enviado = false;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final r = await conCarga(context, Api.i.post('/api/auth/verificar-correo/enviar'), avisarCambio: false);
    if (r == null || !mounted) return;
    setState(() => _enviado = true);
    mostrarMensaje(context, r['mensaje'] ?? 'Te enviamos un código de 6 dígitos.');
  }

  Future<void> _confirmar() async {
    final codigo = _codigo.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      mostrarMensaje(context, 'Escribe los 6 dígitos del código.', error: true);
      return;
    }
    final r = await conCarga(context, Api.i.post('/api/auth/verificar-correo', {'codigo': codigo}), avisarCambio: false);
    if (r == null || !mounted) return;
    await Sesion.i.actualizar(r['datos'] as Map<String, dynamic>);
    if (mounted) mostrarMensaje(context, 'Correo verificado.');
  }

  @override
  Widget build(BuildContext context) {
    final u = Sesion.i.usuario;
    if (u?.correoVerificado ?? false) {
      return Card(
        color: verde.withAlpha(25),
        child: ListTile(
          leading: const Icon(Icons.verified, color: verde),
          title: const Text('Correo verificado'),
          subtitle: Text(u!.correo),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.mark_email_unread_outlined, color: ambar),
            SizedBox(width: 10),
            Expanded(child: Text('Verifica tu correo', style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text('Te enviamos un código a ${u?.correo ?? ''} para confirmar que es tuyo.'),
          const SizedBox(height: 12),
          if (!_enviado)
            FilledButton.icon(onPressed: _enviar, icon: const Icon(Icons.send), label: const Text('Enviar código'))
          else ...[
            TextField(
              controller: _codigo,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'Código de 6 dígitos', prefixIcon: Icon(Icons.pin_outlined)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _enviar, child: const Text('Reenviar'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _confirmar, child: const Text('Verificar'))),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Cambio de contraseña de la propia cuenta (pide la actual).
Future<void> cambiarClave(BuildContext context) async {
  final actual = TextEditingController();
  final nueva = TextEditingController();
  final repetir = TextEditingController();
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: actual,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual'),
              validator: (v) => (v ?? '').isEmpty ? 'Escribe tu contraseña actual' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: nueva,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva (mínimo 8)'),
              validator: (v) {
                if ((v ?? '').length < 8) return 'Mínimo 8 caracteres';
                if (v == actual.text) return 'Debe ser distinta de la actual';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: repetir,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la nueva'),
              validator: (v) => v != nueva.text ? 'Las contraseñas no coinciden' : null,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final hayTexto = actual.text.isNotEmpty || nueva.text.isNotEmpty || repetir.text.isNotEmpty;
            if (!hayTexto || await confirmarSalida(ctx)) {
              if (ctx.mounted) Navigator.pop(ctx, false);
            }
          },
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(ctx, true);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final r = await conCarga(context, Api.i.put('/api/auth/password', {'actual': actual.text, 'nueva': nueva.text}), avisarCambio: false);
  if (r != null && context.mounted) mostrarMensaje(context, 'Contraseña actualizada.');
}
