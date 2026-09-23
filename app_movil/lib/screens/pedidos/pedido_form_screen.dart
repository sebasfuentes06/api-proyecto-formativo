import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../../widgets/selectores.dart';
import 'pedido_detalle_screen.dart';

/// Registrar o editar un pedido. No descuenta stock: eso pasa al convertirlo
/// en venta.
class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({super.key, this.cliente, this.productoInicial, this.pedido});

  final Cliente? cliente;
  final Producto? productoInicial;

  /// Si viene, se está editando ese pedido (debe estar pendiente).
  final Pedido? pedido;

  @override
  State<PedidoFormScreen> createState() => _PedidoFormScreenState();
}

class _PedidoFormScreenState extends State<PedidoFormScreen> {
  Cliente? _cliente;
  String _canal = 'whatsapp';
  final _lineas = <LineaCarrito>[];
  late final _direccion = TextEditingController(text: widget.pedido?.direccionEntrega);
  late final _notas = TextEditingController(text: widget.pedido?.notas);
  bool _cargandoEdicion = false;

  bool get _editando => widget.pedido != null;
  double get _total => _lineas.fold(0, (s, l) => s + l.subtotal);

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    if (widget.productoInicial != null) _lineas.add(LineaCarrito(widget.productoInicial!));
    if (_editando) {
      _cargandoEdicion = true;
      _prepararEdicion();
    }
  }

  @override
  void dispose() {
    _direccion.dispose();
    _notas.dispose();
    super.dispose();
  }

  /// Para editar hace falta el Producto completo de cada línea (stock actual,
  /// foto), no solo lo que trae el detalle del pedido.
  Future<void> _prepararEdicion() async {
    final p = widget.pedido!;
    _canal = p.canal;
    _cliente = Cliente(id: p.idCliente, nombre: p.cliente, telefono: p.clienteTelefono, direccion: p.clienteDireccion);
    try {
      final productos = await Future.wait(p.items.map((i) => Api.i.get('/api/productos/${i.idProducto}')));
      for (var k = 0; k < p.items.length; k++) {
        _lineas.add(LineaCarrito(Producto.desdeJson(productos[k]['datos']), cantidad: p.items[k].cantidad, precio: p.items[k].precioUnitario));
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
    if (mounted) setState(() => _cargandoEdicion = false);
  }

  Future<void> _elegirCliente() async {
    final c = await elegirCliente(context);
    if (c == null || !mounted) return;
    setState(() {
      _cliente = c;
      if (_direccion.text.isEmpty && c.direccion != null) _direccion.text = c.direccion!;
    });
  }

  Future<void> _guardar() async {
    if (_cliente == null) {
      mostrarMensaje(context, 'Elige el cliente.', error: true);
      return;
    }
    if (_lineas.isEmpty) {
      mostrarMensaje(context, 'Agrega al menos un producto.', error: true);
      return;
    }
    final datos = {
      'id_cliente': _cliente!.id,
      'canal': _canal,
      'direccion_entrega': _direccion.text.trim(),
      'notas': _notas.text.trim(),
      'items': _lineas.map((l) => l.aJson()).toList(),
    };
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/pedidos/${widget.pedido!.id}', datos) : Api.i.post('/api/pedidos', datos),
    );
    if (r == null || !mounted) return;
    final pedido = Pedido.desdeJson(r['datos']);
    mostrarMensaje(context, r['mensaje'] ?? 'Pedido guardado.');
    if (_editando) {
      Navigator.pop(context, pedido);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(idPedido: pedido.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar ${widget.pedido!.codigo}' : 'Nuevo pedido')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total', style: tema.textTheme.bodySmall),
                Text(dinero(_total), style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            FilledButton.icon(
              onPressed: _cargandoEdicion ? null : _guardar,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.check),
              label: Text(_editando ? 'Guardar' : 'Registrar pedido'),
            ),
          ]),
        ),
      ),
      body: _cargandoEdicion
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              const TituloSeccion('Cliente'),
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: _cliente == null ? const Icon(Icons.person_search) : Text(_cliente!.iniciales)),
                  title: Text(_cliente?.nombre ?? 'Elegir cliente'),
                  subtitle: _cliente == null ? const Text('Toca para buscar o registrar') : Text(_cliente!.telefono ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _elegirCliente,
                ),
              ),
              const TituloSeccion('Canal'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'whatsapp', label: Text('WhatsApp'), icon: Icon(Icons.chat)),
                    ButtonSegment(value: 'punto_fisico', label: Text('Punto físico'), icon: Icon(Icons.storefront)),
                  ],
                  selected: {_canal},
                  onSelectionChanged: (s) => setState(() => _canal = s.first),
                ),
              ),
              const TituloSeccion('Productos'),
              EditorCarrito(lineas: _lineas, onCambio: () => setState(() {})),
              const TituloSeccion('Entrega'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  TextField(controller: _direccion, decoration: const InputDecoration(labelText: 'Dirección de entrega', prefixIcon: Icon(Icons.place_outlined))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notas,
                    maxLines: 2,
                    maxLength: 250,
                    decoration: const InputDecoration(labelText: 'Notas (hora, empaque, regalo...)', prefixIcon: Icon(Icons.notes)),
                  ),
                ]),
              ),
            ]),
    );
  }
}
