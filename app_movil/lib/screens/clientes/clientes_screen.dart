import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import 'cliente_detalle_screen.dart';
import 'cliente_form_screen.dart';

/// Subproceso de clientes: registrar, consultar, actualizar y cambiar estado.
class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  String _buscar = '';
  String _filtro = 'active';
  int _total = 0;

  Map<String, dynamic> get _query => {
        'search': _buscar,
        'status': _filtro == 'deben' ? 'active' : _filtro,
        if (_filtro == 'deben') 'conSaldo': 1,
        'sortBy': 'nombre',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Clientes${_total > 0 ? ' ($_total)' : ''}'), actions: const [BotonPerfil()]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_clientes',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClienteFormScreen())),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
      body: Column(children: [
        CampoBusqueda(pista: 'Nombre, teléfono, correo o documento', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'active': 'Activos', 'deben': 'Con saldo', 'inactive': 'Inactivos', 'all': 'Todos'},
          valor: _filtro,
          onCambio: (v) => setState(() => _filtro = v),
        ),
        Expanded(
          child: ListaPaginada<Cliente>(
            key: ValueKey('$_buscar|$_filtro'),
            cargar: (p) => Api.i.pagina('/api/clientes', Cliente.desdeJson, query: {..._query, 'page': p, 'limit': 20}),
            alCargar: (p) {
              if (p.total != _total) setState(() => _total = p.total);
            },
            vacio: EstadoVacio(
              icono: Icons.people_outline,
              titulo: _buscar.isEmpty ? 'No hay clientes en este filtro' : 'Nadie coincide con "$_buscar"',
              subtitulo: 'Registra clientes para no volver a pedirles sus datos.',
            ),
            itemBuilder: (ctx, c) => _FilaCliente(cliente: c),
          ),
        ),
      ]),
    );
  }
}

class _FilaCliente extends StatelessWidget {
  const _FilaCliente({required this.cliente});
  final Cliente cliente;

  @override
  Widget build(BuildContext context) {
    final c = cliente;
    final tema = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.estado ? tema.colorScheme.primaryContainer : tema.colorScheme.surfaceContainerHighest,
        child: Text(c.iniciales),
      ),
      title: Text(c.nombre, style: TextStyle(color: c.estado ? null : tema.colorScheme.outline)),
      subtitle: Text(
        [c.telefono, c.ciudad, if (c.compras > 0) '${c.compras} compra${c.compras == 1 ? '' : 's'}']
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' · '),
      ),
      trailing: !c.estado
          ? const Etiqueta('Inactivo', color: gris)
          : c.saldoPendiente > 0
              ? Etiqueta(dinero(c.saldoPendiente), color: rojo)
              : null,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteDetalleScreen(idCliente: c.id))),
    );
  }
}
