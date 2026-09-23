import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import 'usuario_form_screen.dart';

/// Usuarios y roles (solo Administrador): quién entra a la app y con qué rol.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

Color colorRol(String rol) => switch (rol) {
      Rol.admin => const Color(0xFF7A2E55),
      Rol.vendedor => azul,
      _ => verde,
    };

IconData iconoRol(String rol) => switch (rol) {
      Rol.admin => Icons.admin_panel_settings_outlined,
      Rol.vendedor => Icons.storefront_outlined,
      _ => Icons.person_outline,
    };

class _UsuariosScreenState extends State<UsuariosScreen> {
  String _buscar = '';
  String _rol = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios y roles')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_usuarios',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsuarioFormScreen())),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nuevo usuario'),
      ),
      body: Column(children: [
        CampoBusqueda(pista: 'Nombre o correo', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'': 'Todos', Rol.admin: 'Administradores', Rol.vendedor: 'Vendedores', Rol.cliente: 'Clientes'},
          valor: _rol,
          onCambio: (v) => setState(() => _rol = v),
        ),
        Expanded(
          child: ListaPaginada<UsuarioApp>(
            key: ValueKey('$_buscar|$_rol'),
            cargar: (p) => Api.i.pagina('/api/usuarios', UsuarioApp.desdeJson,
                query: {'search': _buscar, 'rol': _rol, 'page': p, 'limit': 30}),
            vacio: const EstadoVacio(icono: Icons.manage_accounts_outlined, titulo: 'No hay usuarios en este filtro'),
            itemBuilder: (ctx, u) => ListTile(
              leading: CircleAvatar(
                backgroundColor: colorRol(u.rol).withAlpha(u.estado ? 40 : 15),
                child: Icon(iconoRol(u.rol), color: u.estado ? colorRol(u.rol) : gris),
              ),
              title: Text(u.nombre, style: TextStyle(color: u.estado ? null : gris)),
              subtitle: Text([
                u.correo,
                if (u.cliente != null) 'Ficha: ${u.cliente}',
                'Último acceso: ${u.ultimoAcceso == null ? 'nunca' : fechaHora(u.ultimoAcceso)}',
              ].join('\n')),
              isThreeLine: true,
              trailing: u.estado ? Etiqueta(u.rol, color: colorRol(u.rol)) : const Etiqueta('Inactivo', color: gris),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => UsuarioFormScreen(usuario: u))),
            ),
          ),
        ),
      ]),
    );
  }
}
