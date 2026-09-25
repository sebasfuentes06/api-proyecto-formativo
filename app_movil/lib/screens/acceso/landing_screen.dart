import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/contacto.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../login_screen.dart';
import 'registro_screen.dart';

/// Vitrina pública: lo primero que ve quien abre la app sin sesión.
///
/// Muestra los productos que se venden (catálogo real de la API, con sus
/// fotos). Para pedir hay que crear una cuenta o iniciar sesión.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  String _buscar = '';
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
    Future.microtask(() async {
      await _cargarCategorias();
      await _recargar();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final p = await Api.i.pagina('/api/categorias', Categoria.desdeJson, query: {'status': 'active', 'limit': 100});
      if (mounted) setState(() => _categorias = p.items);
    } catch (_) {/* sin categorías igual se muestran los productos */}
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
        'status': 'active',
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

  void _filtrar(void Function() cambio) {
    setState(cambio);
    _recargar();
  }

  Future<void> _entrar({String? correo}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(correoInicial: correo)));

  Future<void> _registrarse() async {
    final correo = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const RegistroScreen()));
    // Al terminar el registro se abre el login con el correo ya escrito.
    if (correo != null && mounted) await _entrar(correo: correo);
  }

  void _verProducto(Producto p) {
    final tema = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(aspectRatio: 1.3, child: ProductoImagen(p, tam: null, radio: 16)),
          const SizedBox(height: 16),
          Text(p.nombre, style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(p.categoria, style: TextStyle(color: tema.colorScheme.outline)),
          const SizedBox(height: 8),
          Row(children: [
            Text(dinero(p.precio),
                style: tema.textTheme.headlineSmall?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.w700)),
            const Spacer(),
            p.agotado ? const Etiqueta('Agotado', color: rojo) : const Etiqueta('Disponible', color: verde),
          ]),
          if (p.descripcion != null && p.descripcion!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.descripcion!, style: tema.textTheme.bodyLarge),
          ],
          const SizedBox(height: 20),
          Card(
            color: tema.colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.lock_outline),
                SizedBox(width: 10),
                Expanded(child: Text('Para hacer tu pedido y pagar desde la app, crea tu cuenta o inicia sesión.')),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _registrarse();
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Crear cuenta para pedir'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _entrar();
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Ya tengo cuenta'),
          ),
          TextButton.icon(
            onPressed: () => abrirWhatsApp(Config.telefono, 'Hola, me interesa ${p.nombre} (${dinero(p.precio)}).'),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Preguntar por WhatsApp'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 190,
              backgroundColor: tema.colorScheme.primary,
              foregroundColor: tema.colorScheme.onPrimary,
              title: const Text('Essence Don Aire'),
              actions: [
                TextButton(
                  onPressed: _entrar,
                  style: TextButton.styleFrom(foregroundColor: tema.colorScheme.onPrimary),
                  child: const Text('Iniciar sesión'),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tema.colorScheme.primary, tema.colorScheme.tertiary],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 96, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('Fragancias y detalles',
                        style: tema.textTheme.headlineSmall?.copyWith(color: tema.colorScheme.onPrimary, fontWeight: FontWeight.w700)),
                    Text('La Pintada, Antioquia · Pide desde la app y paga como prefieras',
                        style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onPrimary.withAlpha(220))),
                  ]),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CampoBusqueda(pista: 'Buscar producto', onBuscar: (v) => _filtrar(() => _buscar = v)),
            ),
            if (_categorias.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(label: const Text('Todo'), selected: _categoria == null, onSelected: (_) => _filtrar(() => _categoria = null)),
                      ),
                      for (final c in _categorias)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(c.nombre),
                            selected: _categoria == c.id,
                            onSelected: (s) => _filtrar(() => _categoria = s ? c.id : null),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ..._contenido(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _entrar,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: const Text('Iniciar sesión'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _registrarse,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: const Text('Registrarme'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _contenido() {
    if (_productos.isEmpty && _cargando) {
      return [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))];
    }
    if (_productos.isEmpty && _error != null) {
      return [SliverToBoxAdapter(child: ErrorReintentar(error: _error!, onReintentar: _recargar))];
    }
    if (_productos.isEmpty) {
      return const [
        SliverToBoxAdapter(child: EstadoVacio(icono: Icons.local_florist_outlined, titulo: 'No encontramos productos')),
      ];
    }
    final tema = Theme.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.7,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final p = _productos[i];
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _verProducto(p),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: ProductoImagen(p, tam: null, radio: 0)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: tema.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                            child: Text(dinero(p.precio),
                                style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.w700)),
                          ),
                          if (p.agotado) const Text('Agotado', style: TextStyle(color: rojo, fontSize: 12)),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              );
            },
            childCount: _productos.length,
          ),
        ),
      ),
      if (_cargando) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
    ];
  }
}
