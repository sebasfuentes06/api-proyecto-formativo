import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
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
        'sortBy': 'nombre',
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

  void _cambiarFiltro(void Function() cambio) {
    setState(cambio);
    _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo'), actions: const [BotonPerfil()]),
      floatingActionButton: FloatingActionButton.extended(
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
              for (final f in const {'active': 'Disponibles', 'bajo': 'Stock bajo', 'inactive': 'Inactivos'}.entries)
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
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
              Text(dinero(p.precio), style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              etiquetaStock(p),
            ]),
          ),
        ]),
      ),
    );
  }
}
