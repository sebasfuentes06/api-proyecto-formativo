import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/sesion.dart';
import '../screens/cuenta/mi_perfil_screen.dart';
import '../screens/usuarios/usuarios_screen.dart';
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

  /// Menú de la cuenta. Va dentro de un scroll y con altura controlada:
  /// antes era una columna fija y, en pantallas bajas, no cabía y Flutter
  /// pintaba la franja amarilla de "overflow" encima de "Cerrar sesión".
  void _abrir(BuildContext context) {
    final u = Sesion.i.usuario;
    final error = Theme.of(context).colorScheme.error;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(u?.nombre ?? ''),
                subtitle: Text('${u?.correo ?? ''}\n${u?.rol ?? ''}'),
                isThreeLine: true,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Mi perfil'),
                subtitle: const Text('Mis datos, verificar correo y contraseña'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MiPerfilScreen()));
                },
              ),
              if (Sesion.i.puede('users.view'))
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Usuarios'),
                  subtitle: const Text('Cuentas, solicitudes y permisos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const UsuariosScreen()));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Cambiar contraseña'),
                onTap: () {
                  Navigator.pop(ctx);
                  cambiarClave(context);
                },
              ),
              if (Sesion.i.esEquipo)
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
                leading: Icon(Icons.logout, color: error),
                title: Text('Cerrar sesión', style: TextStyle(color: error)),
                onTap: () {
                  Navigator.pop(ctx);
                  Sesion.i.cerrar();
                },
              ),
            ],
          ),
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
}
