import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/sesion.dart';
import '../../widgets/perfil.dart';
import '../categorias/categorias_screen.dart';
import '../clientes/clientes_screen.dart';
import '../compras/compras_screen.dart';
import '../cuenta/mi_perfil_screen.dart';
import '../pagos/pagos_screen.dart';
import '../proveedores/proveedores_screen.dart';
import '../roles/roles_screen.dart';
import '../usuarios/usuarios_screen.dart';

/// Pestaña "Más": el resto de módulos de la web, cada uno visible solo para
/// quien tiene el permiso de verlo.
class MasScreen extends StatelessWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    void abrir(Widget pantalla) => Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

    Widget seccion(String titulo, List<Widget> filas) {
      if (filas.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(titulo.toUpperCase(),
              style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.primary, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
        ),
        Card(child: Column(children: filas)),
      ]);
    }

    ListTile fila(IconData icono, String titulo, String sub, VoidCallback alTocar) => ListTile(
          leading: Icon(icono, color: tema.colorScheme.primary),
          title: Text(titulo),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: alTocar,
        );

    final s = Sesion.i;
    return Scaffold(
      appBar: AppBar(title: const Text('Más'), actions: const [BotonPerfil()]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        seccion('Operaciones', [
          if (s.puede('customers.view')) fila(Icons.people_outline, 'Clientes', 'Fichas, historial y estado de cuenta', () => abrir(const ClientesScreen())),
          if (s.puede('payments.view')) fila(Icons.payments_outlined, 'Pagos y abonos', 'Por aprobar, cartera e historial', () => abrir(const PagosScreen())),
          if (s.puede('purchases.view')) fila(Icons.shopping_bag_outlined, 'Compras', 'Compras a proveedores y sus abonos', () => abrir(const ComprasScreen())),
        ]),
        seccion('Catálogo', [
          if (s.puede('categories.view')) fila(Icons.category_outlined, 'Categorías', 'Familias de fragancias', () => abrir(const CategoriasScreen())),
          if (s.puede('suppliers.view')) fila(Icons.local_shipping_outlined, 'Proveedores', 'Marcas y contactos', () => abrir(const ProveedoresScreen())),
        ]),
        seccion('Administración', [
          if (s.puede('users.view')) fila(Icons.manage_accounts_outlined, 'Usuarios', 'Cuentas, solicitudes y permisos', () => abrir(const UsuariosScreen())),
          if (s.puede('roles.view')) fila(Icons.shield_outlined, 'Roles', 'Qué puede hacer cada rol', () => abrir(const RolesScreen())),
        ]),
        seccion('Mi cuenta', [
          fila(Icons.account_circle_outlined, 'Mi perfil', 'Mis datos, verificar correo y contraseña', () => abrir(const MiPerfilScreen())),
          ListTile(
            leading: Icon(Icons.logout, color: tema.colorScheme.error),
            title: Text('Cerrar sesión', style: TextStyle(color: tema.colorScheme.error)),
            onTap: () => Sesion.i.cerrar(),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${Config.negocio} · ${s.usuario?.rol ?? ''}', textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.outline)),
        ),
      ]),
    );
  }
}
