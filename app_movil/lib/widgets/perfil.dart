import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/sesion.dart';
import 'comunes.dart';

/// Botón del avatar (arriba a la derecha en todas las pestañas): perfil,
/// cambio de contraseña, estado de Wompi y cerrar sesión.
class BotonPerfil extends StatelessWidget {
  const BotonPerfil({super.key});

  @override
  Widget build(BuildContext context) {
    final nombre = Sesion.i.usuario?.nombre ?? 'A';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        tooltip: 'Mi cuenta',
        onPressed: () => _abrir(context),
        icon: CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(nombre.isEmpty ? 'A' : nombre[0].toUpperCase(),
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 14)),
        ),
      ),
    );
  }

  void _abrir(BuildContext context) {
    final u = Sesion.i.usuario;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(u?.nombre ?? 'Administrador'),
              subtitle: Text('${u?.correo ?? ''}\n${u?.rol ?? ''}'),
              isThreeLine: true,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Cambiar contraseña'),
              onTap: () {
                Navigator.pop(ctx);
                _cambiarClave(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.credit_card),
              title: const Text('Estado de Wompi'),
              onTap: () {
                Navigator.pop(ctx);
                _estadoWompi(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Servidor'),
              subtitle: Text(Config.apiUrl),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Cerrar sesión', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                Sesion.i.cerrar();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _estadoWompi(BuildContext context) async {
    final r = await conCarga(context, Api.i.get('/api/pagos/wompi'), avisarCambio: false);
    if (r == null || !context.mounted) return;
    final d = r['datos'] as Map<String, dynamic>;
    final ok = Icon(Icons.check_circle, color: verde);
    final no = Icon(Icons.cancel, color: rojo);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wompi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Entorno'),
            trailing: Text(d['entorno'] == 'production' ? 'Producción' : 'Pruebas (sandbox)'),
          ),
          ListTile(leading: d['links'] == true ? ok : no, title: const Text('Crear links de pago')),
          ListTile(leading: d['webhook'] == true ? ok : no, title: const Text('Confirmación automática (webhook)')),
          if (d['links'] != true)
            const Text('Mientras Wompi no esté configurado, registra los abonos manualmente.'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _cambiarClave(BuildContext context) async {
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: actual, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual'),
                validator: (v) => (v ?? '').isEmpty ? 'Obligatoria' : null),
            const SizedBox(height: 12),
            TextFormField(controller: nueva, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva (mínimo 8)'),
                validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null),
            const SizedBox(height: 12),
            TextFormField(controller: repetir, obscureText: true, decoration: const InputDecoration(labelText: 'Repite la nueva'),
                validator: (v) => v != nueva.text ? 'No coincide' : null),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
}
