import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../../widgets/exportar.dart';
import '../catalogo/producto_detalle_screen.dart';

/// Categorías de productos (igual que en la web): listar, buscar, filtrar
/// por estado, ordenar, crear, editar, activar/desactivar, eliminar (si no
/// tiene productos), ver sus productos y exportar a PDF.
class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  String _buscar = '';
  String _estado = 'all';
  String _orden = 'nombre|asc';
  int _total = 0;

  Map<String, dynamic> get _query => {
        'search': _buscar,
        'status': _estado,
        'sortBy': _orden.split('|').first,
        'sortDir': _orden.split('|').last,
      };

  Future<void> _exportar() async {
    final filas = await Api.i.todos('/api/categorias', Categoria.desdeJson, query: _query);
    await compartirListadoPdf<Categoria>(
      titulo: 'categorías',
      filas: filas,
      columnas: [
        ColumnaPdf('Nombre', (c) => c.nombre),
        ColumnaPdf('Descripción', (c) => c.descripcion),
        ColumnaPdf('Productos', (c) => c.totalProductos, numero: true),
        ColumnaPdf('Estado', (c) => c.estado ? 'Activa' : 'Inactiva'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Categorías${_total > 0 ? ' ($_total)' : ''}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: _orden,
            onSelected: (v) => setState(() => _orden = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'nombre|asc', child: Text('Nombre (A-Z)')),
              PopupMenuItem(value: 'nombre|desc', child: Text('Nombre (Z-A)')),
              PopupMenuItem(value: 'created_at|desc', child: Text('Más recientes')),
            ],
          ),
          BotonPdf(exportar: _exportar),
        ],
      ),
      floatingActionButton: !Sesion.i.puede('categories.create')
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_categorias',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriaFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Categoría'),
            ),
      body: Column(children: [
        CampoBusqueda(pista: 'Nombre o descripción', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'all': 'Todas', 'active': 'Activas', 'inactive': 'Inactivas'},
          valor: _estado,
          onCambio: (v) => setState(() => _estado = v),
        ),
        Expanded(
          child: ListaPaginada<Categoria>(
            key: ValueKey('$_buscar|$_estado|$_orden'),
            cargar: (p) => Api.i.pagina('/api/categorias', Categoria.desdeJson, query: {..._query, 'page': p, 'limit': 20}),
            alCargar: (p) {
              if (p.total != _total) setState(() => _total = p.total);
            },
            vacio: const EstadoVacio(icono: Icons.category_outlined, titulo: 'No hay categorías en este filtro'),
            itemBuilder: (ctx, c) => ListTile(
              leading: CircleAvatar(child: Icon(Icons.category_outlined, color: c.estado ? null : gris)),
              title: Text(c.nombre, style: TextStyle(color: c.estado ? null : gris)),
              subtitle: Text([
                if ((c.descripcion ?? '').isNotEmpty) c.descripcion!,
                '${c.totalProductos} producto${c.totalProductos == 1 ? '' : 's'}',
              ].join('\n')),
              isThreeLine: (c.descripcion ?? '').isNotEmpty,
              trailing: c.estado ? const Etiqueta('Activa', color: verde) : const Etiqueta('Inactiva', color: gris),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => CategoriaDetalleScreen(categoria: c))),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Detalle: datos, acciones y los productos de la categoría.
class CategoriaDetalleScreen extends StatefulWidget {
  const CategoriaDetalleScreen({super.key, required this.categoria});
  final Categoria categoria;

  @override
  State<CategoriaDetalleScreen> createState() => _CategoriaDetalleScreenState();
}

class _CategoriaDetalleScreenState extends State<CategoriaDetalleScreen> {
  late Categoria _c = widget.categoria;

  @override
  void initState() {
    super.initState();
    Eventos.datos.addListener(_recargar);
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_recargar);
    super.dispose();
  }

  Future<void> _recargar() async {
    try {
      final r = await Api.i.get('/api/categorias/${_c.id}');
      if (mounted) setState(() => _c = Categoria.desdeJson(r['datos']));
    } catch (_) {/* se queda con lo que tenía (o ya se eliminó) */}
  }

  Future<void> _cambiarEstado() async {
    final ok = await confirmar(
      context,
      titulo: _c.estado ? 'Desactivar categoría' : 'Activar categoría',
      mensaje: _c.estado ? '${_c.nombre} dejará de aparecer para elegir en productos nuevos.' : '${_c.nombre} volverá a estar disponible.',
      textoOk: _c.estado ? 'Desactivar' : 'Activar',
      peligro: _c.estado,
    );
    if (!ok || !mounted) return;
    await conCarga(context, Api.i.put('/api/categorias/${_c.id}', {'estado': !_c.estado}));
  }

  Future<void> _eliminar() async {
    final ok = await eliminarConAviso(
      context,
      nombre: _c.nombre,
      ruta: '/api/categorias/${_c.id}',
      nota: 'Nota: no se puede eliminar una categoría que tiene productos; desactívala en su lugar.',
    );
    if (ok && mounted) {
      mostrarMensaje(context, 'Categoría eliminada.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.nombre),
        actions: [
          if (Sesion.i.puede('categories.edit'))
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoriaFormScreen(categoria: _c))),
            ),
          if (Sesion.i.puedeAlguno(['categories.edit', 'categories.delete']))
            PopupMenuButton<String>(
              onSelected: (v) => v == 'estado' ? _cambiarEstado() : _eliminar(),
              itemBuilder: (_) => [
                if (Sesion.i.puede('categories.edit')) PopupMenuItem(value: 'estado', child: Text(_c.estado ? 'Desactivar' : 'Activar')),
                if (Sesion.i.puede('categories.delete'))
                  const PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: rojo))),
              ],
            ),
        ],
      ),
      body: Column(children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.category_outlined)),
            title: Text(_c.nombre, style: tema.textTheme.titleMedium),
            subtitle: Text((_c.descripcion ?? '').isEmpty ? 'Sin descripción' : _c.descripcion!),
            trailing: _c.estado ? const Etiqueta('Activa', color: verde) : const Etiqueta('Inactiva', color: gris),
          ),
        ),
        TituloSeccion('Productos de la categoría (${_c.totalProductos})'),
        Expanded(
          child: ListaPaginada<Producto>(
            cargar: (p) => Api.i.pagina('/api/productos', Producto.desdeJson,
                query: {'categoria': _c.id, 'status': 'all', 'sortBy': 'nombre', 'page': p, 'limit': 30}),
            vacio: const EstadoVacio(icono: Icons.local_florist_outlined, titulo: 'Esta categoría aún no tiene productos'),
            itemBuilder: (ctx, p) => ListTile(
              leading: ProductoImagen(p, tam: 44),
              title: Text(p.nombre),
              subtitle: Text(p.sku),
              trailing: etiquetaStock(p),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ProductoDetalleScreen(producto: p))),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Crear o editar una categoría.
class CategoriaFormScreen extends StatefulWidget {
  const CategoriaFormScreen({super.key, this.categoria});
  final Categoria? categoria;

  @override
  State<CategoriaFormScreen> createState() => _CategoriaFormScreenState();
}

class _CategoriaFormScreenState extends State<CategoriaFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.categoria?.nombre);
  late final _descripcion = TextEditingController(text: widget.categoria?.descripcion);
  late bool _estado = widget.categoria?.estado ?? true;

  bool get _editando => widget.categoria != null;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final datos = {'nombre': _nombre.text.trim(), 'descripcion': _descripcion.text.trim(), 'estado': _estado};
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/categorias/${widget.categoria!.id}', datos) : Api.i.post('/api/categorias', datos),
    );
    if (r == null || !mounted) return;
    mostrarMensaje(context, _editando ? 'Categoría actualizada.' : 'Categoría creada.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ProtegerSalida(
        child: Scaffold(
          appBar: AppBar(title: Text(_editando ? 'Editar categoría' : 'Nueva categoría')),
          body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Nombre de la categoría *', prefixIcon: Icon(Icons.category_outlined)),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descripcion,
                maxLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Descripción', prefixIcon: Icon(Icons.notes)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                subtitle: Text(_estado ? 'Se puede asignar a productos' : 'No aparece para productos nuevos'),
                value: _estado,
                onChanged: (v) => setState(() => _estado = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _guardar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.save),
                label: Text(_editando ? 'Guardar cambios' : 'Crear categoría'),
              ),
            ]),
          ),
        ),
      );
}
