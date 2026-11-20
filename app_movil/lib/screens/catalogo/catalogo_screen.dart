import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../../widgets/exportar.dart';
import '../../widgets/perfil.dart';
import '../carrito/carrito_screen.dart';
import 'producto_detalle_screen.dart';
import 'producto_form_screen.dart';

/// Subproceso de catálogo: productos disponibles con stock, precio e imagen.
class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  String _buscar = '';
  String _filtro = 'active'; // active | bajo | inactive
  String _orden = 'nombre|asc';
  int? _categoria;
  List<Categoria> _categorias = [];

  final _productos = <Producto>[];
  bool _cargando = true;
  Object? _error;
  int _pagina = 0, _totalPaginas = 1, _solicitud = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _cargar();
    });
    Eventos.datos.addListener(_recargar);
    Future.microtask(() async {
      await _cargarCategorias();
      await _recargar();
    });
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_recargar);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final p = await Api.i.pagina('/api/categorias', Categoria.desdeJson, query: {'status': 'active', 'limit': 100});
      if (mounted) setState(() => _categorias = p.items);
    } catch (_) {/* sin categorías se muestran todos los productos */}
  }

  Future<void> _recargar() async {
    _pagina = 0;
    _totalPaginas = 1;
    await _cargar(reiniciar: true);
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    if (!mounted || (!reiniciar && (_cargando || _pagina >= _totalPaginas))) return;
    final numero = ++_solicitud;
    setState(() => _cargando = true);
    try {
      final p = await Api.i.pagina('/api/productos', Producto.desdeJson, query: {
        'search': _buscar,
        'status': _filtro == 'inactive' ? 'inactive' : 'active',
        if (_filtro == 'bajo') 'stockBajo': 1,
        'categoria': _categoria,
        'sortBy': _orden.split('|').first,
        'sortDir': _orden.split('|').last,
        'page': _pagina + 1,
        'limit': 20,
      });
      if (!mounted || numero != _solicitud) return;
      setState(() {
        if (reiniciar) _productos.clear();
        _productos.addAll(p.items);
        _pagina++;
        _totalPaginas = p.totalPaginas;
        _error = null;
      });
    } catch (e) {
      if (mounted && numero == _solicitud) setState(() => _error = e);
    } finally {
      if (mounted && numero == _solicitud) setState(() => _cargando = false);
    }
  }

  /// Catálogo en PDF con los filtros puestos (igual que el botón PDF de la web).
  Future<void> _exportar() async {
    final filas = await Api.i.todos('/api/productos', Producto.desdeJson, query: {
      'search': _buscar,
      'status': _filtro == 'inactive' ? 'inactive' : 'active',
      if (_filtro == 'bajo') 'stockBajo': 1,
      'categoria': _categoria,
      'sortBy': _orden.split('|').first,
      'sortDir': _orden.split('|').last,
    });
    await compartirListadoPdf<Producto>(
      titulo: 'productos',
      filas: filas,
      columnas: [
        ColumnaPdf('Producto', (p) => p.nombre),
        ColumnaPdf('SKU', (p) => p.sku),
        ColumnaPdf('Categoría', (p) => p.categoria),
        ColumnaPdf('Proveedor', (p) => p.proveedor),
        ColumnaPdf('Precio', (p) => p.precio, dinero: true),
        ColumnaPdf('Stock', (p) => p.stock, numero: true),
        ColumnaPdf('Estado', (p) => p.estado ? 'Activo' : 'Inactivo'),
      ],
    );
  }

  void _cambiarFiltro(void Function() cambio) {
    setState(cambio);
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo'), actions: [
        PopupMenuButton<String>(
          tooltip: 'Ordenar',
          icon: const Icon(Icons.sort),
          initialValue: _orden,
          onSelected: (v) => _cambiarFiltro(() => _orden = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'nombre|asc', child: Text('Nombre (A-Z)')),
            PopupMenuItem(value: 'nombre|desc', child: Text('Nombre (Z-A)')),
            PopupMenuItem(value: 'precio|asc', child: Text('Precio: menor a mayor')),
            PopupMenuItem(value: 'precio|desc', child: Text('Precio: mayor a menor')),
            PopupMenuItem(value: 'stock|asc', child: Text('Stock: menor a mayor')),
          ],
        ),
        if (Sesion.i.esEquipo) BotonPdf(exportar: _exportar),
        const BotonCarrito(),
        const BotonPerfil(),
      ]),
      // Crear productos es del Administrador.
      floatingActionButton: !Sesion.i.puede('products.create')
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_catalogo',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductoFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Producto'),
            ),
      body: Column(children: [
        CampoBusqueda(pista: 'Buscar fragancia o SKU', onBuscar: (v) => _cambiarFiltro(() => _buscar = v)),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in {
                'active': 'Disponibles',
                if (Sesion.i.esEquipo) 'bajo': 'Stock bajo',
                if (Sesion.i.puede('products.edit')) 'inactive': 'Inactivos',
              }.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(label: Text(f.value), selected: _filtro == f.key, onSelected: (_) => _cambiarFiltro(() => _filtro = f.key)),
                ),
              const VerticalDivider(),
              for (final c in _categorias)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(c.nombre),
                    selected: _categoria == c.id,
                    onSelected: (s) => _cambiarFiltro(() => _categoria = s ? c.id : null),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: RefreshIndicator(onRefresh: _recargar, child: _cuerpo())),
      ]),
    );
  }

  Widget _cuerpo() {
    if (_productos.isEmpty && _cargando) return const Center(child: CircularProgressIndicator());
    if (_productos.isEmpty && _error != null) return ListView(children: [ErrorReintentar(error: _error!, onReintentar: _recargar)]);
    if (_productos.isEmpty) {
      return ListView(children: const [
        EstadoVacio(icono: Icons.local_florist_outlined, titulo: 'No hay productos con estos filtros'),
      ]);
    }
    return GridView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 4, 12, Sesion.i.puede('products.create') ? 96 : 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.66,
      ),
      itemCount: _productos.length,
      itemBuilder: (ctx, i) => _TarjetaProducto(producto: _productos[i]),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto});
  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductoDetalleScreen(producto: p))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ProductoImagen(p, tam: null, radio: 0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: tema.textTheme.titleSmall),
              Text(p.categoria, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(dinero(p.precio),
                      style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                // Atajo: agregar al carrito sin abrir el producto (el cliente
                // para su pedido; el equipo, para armar un pedido a un cliente).
                if (Sesion.i.puede('orders.create') && p.vendible)
                  SizedBox(
                    width: 30,
                    height: 26,
                    child: IconButton.filledTonal(
                      tooltip: 'Agregar al carrito',
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      icon: const Icon(Icons.add_shopping_cart),
                      onPressed: () => agregarAlCarrito(context, p),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              etiquetaStock(p),
            ]),
          ),
        ]),
      ),
    );
  }
}
