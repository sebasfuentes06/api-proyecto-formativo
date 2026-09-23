import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../models/modelos.dart';
import '../screens/clientes/cliente_form_screen.dart';
import 'comunes.dart';

/// Pantallas para elegir un cliente o un producto al armar pedidos y ventas.

// ---------------------------------------------------------------------------
// Cliente
// ---------------------------------------------------------------------------

Future<Cliente?> elegirCliente(BuildContext context) =>
    Navigator.push<Cliente>(context, MaterialPageRoute(builder: (_) => const _SelectorCliente()));

class _SelectorCliente extends StatefulWidget {
  const _SelectorCliente();

  @override
  State<_SelectorCliente> createState() => _SelectorClienteState();
}

class _SelectorClienteState extends State<_SelectorCliente> {
  String _buscar = '';

  Future<void> _nuevo() async {
    final creado = await Navigator.push<Cliente>(context, MaterialPageRoute(builder: (_) => const ClienteFormScreen()));
    if (creado != null && mounted) Navigator.pop(context, creado);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir cliente')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo cliente'),
      ),
      body: Column(children: [
        CampoBusqueda(pista: 'Nombre, teléfono o documento', onBuscar: (v) => setState(() => _buscar = v)),
        Expanded(
          child: ListaPaginada<Cliente>(
            key: ValueKey(_buscar),
            cargar: (p) => Api.i.pagina('/api/clientes', Cliente.desdeJson,
                query: {'search': _buscar, 'status': 'active', 'page': p, 'limit': 30, 'sortBy': 'nombre'}),
            vacio: EstadoVacio(
              icono: Icons.person_search,
              titulo: _buscar.isEmpty ? 'No hay clientes activos' : 'Sin resultados para "$_buscar"',
              subtitulo: 'Regístralo con el botón "Nuevo cliente".',
            ),
            itemBuilder: (ctx, c) => ListTile(
              leading: CircleAvatar(child: Text(c.iniciales)),
              title: Text(c.nombre),
              subtitle: Text([c.telefono, c.ciudad].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
              trailing: c.saldoPendiente > 0 ? Etiqueta('Debe ${dinero(c.saldoPendiente)}', color: rojo) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Producto
// ---------------------------------------------------------------------------

/// Hoja inferior para buscar un producto. Los agotados o inactivos se ven
/// pero no se pueden elegir: así la persona sabe que existen y que faltan.
Future<Producto?> elegirProducto(BuildContext context) => showModalBottomSheet<Producto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.9, child: _SelectorProducto()),
    );

class _SelectorProducto extends StatefulWidget {
  const _SelectorProducto();

  @override
  State<_SelectorProducto> createState() => _SelectorProductoState();
}

class _SelectorProductoState extends State<_SelectorProducto> {
  String _buscar = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('Agregar producto', style: Theme.of(context).textTheme.titleMedium),
      CampoBusqueda(pista: 'Nombre o SKU', onBuscar: (v) => setState(() => _buscar = v)),
      Expanded(
        child: ListaPaginada<Producto>(
          key: ValueKey(_buscar),
          relleno: const EdgeInsets.only(bottom: 24),
          cargar: (p) => Api.i.pagina('/api/productos', Producto.desdeJson,
              query: {'search': _buscar, 'status': 'active', 'page': p, 'limit': 30, 'sortBy': 'nombre'}),
          vacio: const EstadoVacio(icono: Icons.search_off, titulo: 'No hay productos con ese nombre'),
          itemBuilder: (ctx, p) => ListTile(
            enabled: p.vendible,
            leading: ProductoImagen(p, tam: 48),
            title: Text(p.nombre),
            subtitle: Text('${p.sku} · ${dinero(p.precio)}'),
            trailing: etiquetaStock(p),
            onTap: () => Navigator.pop(ctx, p),
          ),
        ),
      ),
    ]);
  }
}
