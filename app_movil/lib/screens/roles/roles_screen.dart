import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/permisos.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../usuarios/usuarios_screen.dart';

/// Roles (solo lectura, igual que en la web): los tres roles del sistema,
/// lo que puede hacer cada uno y cuántas cuentas activas tiene. Para darle o
/// quitarle permisos a una persona se usa el formulario de Usuarios.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

const _descripciones = {
  Rol.admin: 'Acceso completo a todos los módulos del sistema',
  Rol.vendedor: 'Ventas, pedidos, abonos, clientes y su dashboard personal',
  Rol.cliente: 'Catálogo, carrito, sus pedidos y sus pagos',
};

class _RolesScreenState extends State<RolesScreen> {
  Map<String, int>? _conteo;
  String _buscar = '';

  @override
  void initState() {
    super.initState();
    if (Sesion.i.puede('users.view')) {
      Api.i.todos('/api/usuarios', UsuarioApp.desdeJson).then((lista) {
        final c = <String, int>{};
        for (final u in lista.where((u) => u.estado && !u.pendiente && !u.rechazado)) {
          c[u.rol] = (c[u.rol] ?? 0) + 1;
        }
        if (mounted) setState(() => _conteo = c);
      }).catchError((_) {
        if (mounted) setState(() => _conteo = {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final roles = Rol.todos.where((r) {
      final q = _buscar.toLowerCase();
      return q.isEmpty || r.toLowerCase().contains(q) || (_descripciones[r] ?? '').toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      body: Column(children: [
        CampoBusqueda(pista: 'Buscar rol', onBuscar: (v) => setState(() => _buscar = v)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Los tres roles del sistema son fijos (los mismos de la web). Al Vendedor se le pueden dar o quitar permisos '
            'uno por uno desde Usuarios.',
            style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
          ),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            for (final r in roles)
              Card(
                child: ExpansionTile(
                  leading: CircleAvatar(backgroundColor: colorRol(r).withAlpha(40), child: Icon(iconoRol(r), color: colorRol(r))),
                  title: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${_descripciones[r]}${_conteo == null ? '' : '\n${_conteo![r] ?? 0} cuenta(s) activa(s)'}'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in agruparPermisos(permisosPorRol[r] ?? const []))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 110, child: Text(g.nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Expanded(child: Text(g.claves.map(nombreAccion).join(', '))),
                        ]),
                      ),
                  ],
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
