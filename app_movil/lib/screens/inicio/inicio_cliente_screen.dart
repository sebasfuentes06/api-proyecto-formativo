import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import '../carrito/carrito_screen.dart';
import '../catalogo/producto_detalle_screen.dart';
import '../pedidos/pedidos_screen.dart';

/// Inicio del Cliente (igual que en la web): sus datos, su saldo, sus
/// pedidos pendientes y las novedades del catálogo para agregar al carrito.
class InicioClienteScreen extends StatefulWidget {
  const InicioClienteScreen({super.key});

  @override
  State<InicioClienteScreen> createState() => _InicioClienteScreenState();
}

class _InicioClienteScreenState extends State<InicioClienteScreen> {
  double? _saldo;
  int _conSaldo = 0;
  int? _pendientes;
  List<Producto>? _novedades;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Eventos.datos.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final idCliente = Sesion.i.usuario?.idCliente;
    try {
      final r = await Future.wait([
        Api.i.pagina('/api/pedidos', Pedido.desdeJson, query: {'estado': 'pendiente', 'limit': 1}),
        // Novedades: los productos más recientes con stock.
        Api.i.pagina('/api/productos', Producto.desdeJson, query: {'status': 'active', 'sortBy': 'id_producto', 'sortDir': 'desc', 'limit': 12}),
        if (idCliente != null) Api.i.get('/api/clientes/$idCliente/estado-cuenta'),
      ]);
      if (!mounted) return;
      setState(() {
        _pendientes = (r[0] as Pagina<Pedido>).total;
        _novedades = (r[1] as Pagina<Producto>).items.where((p) => p.vendible).take(6).toList();
        if (r.length > 2) {
          final cuenta = (r[2] as Map<String, dynamic>)['datos'] as Map<String, dynamic>;
          _saldo = aNum((cuenta['resumen'] as Map<String, dynamic>)['saldo']);
          _conSaldo = (cuenta['ventas'] as List).where((v) => aNum((v as Map<String, dynamic>)['saldo']) > 0).length;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final u = Sesion.i.usuario;
    final Widget cuerpo;
    if (_novedades == null) {
      cuerpo = _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator());
    } else {
      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Hola, ${(u?.nombre ?? '').split(' ').first}', style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(u?.correo ?? '', style: TextStyle(color: tema.colorScheme.outline)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Card(
                color: (_saldo ?? 0) > 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((_saldo ?? 0) > 0 ? 'Saldo pendiente' : 'Estás al día', style: tema.textTheme.bodySmall),
                    FittedBox(child: Text(dinero(_saldo ?? 0), style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                    Text('$_conSaldo compra(s) con saldo', style: tema.textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
            Expanded(
              child: Card(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidosScreen())),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pedidos pendientes', style: tema.textTheme.bodySmall),
                      Text('${_pendientes ?? 0}', style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Toca para verlos', style: tema.textTheme.bodySmall),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
          const TituloSeccion('Novedades del catálogo'),
          if (_novedades!.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Pronto tendremos novedades.')),
          for (final p in _novedades!)
            ListTile(
              leading: ProductoImagen(p, tam: 52),
              title: Text(p.nombre),
              subtitle: Text('${p.categoria} · ${dinero(p.precio)}'),
              trailing: IconButton.filledTonal(
                tooltip: 'Agregar al carrito',
                icon: const Icon(Icons.add_shopping_cart),
                onPressed: () => agregarAlCarrito(context, p),
              ),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductoDetalleScreen(producto: p))),
            ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Inicio'), actions: const [BotonCarrito(), BotonPerfil()]),
      body: cuerpo,
    );
  }
}
