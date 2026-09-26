import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/carrito.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../../widgets/selectores.dart';
import '../pagos/pago_detalle.dart';
import 'pedido_detalle_screen.dart';

/// Registrar o editar un pedido. No descuenta stock: eso pasa al convertirlo
/// en venta.
class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({super.key, this.cliente, this.productoInicial, this.pedido, this.desdeCarrito = false});

  /// El Cliente llega aquí desde su carrito: se precargan esos productos y,
  /// al registrar el pedido, el carrito se vacía.
  final bool desdeCarrito;

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

  /// Cómo va a pagar. Obligatorio para el Cliente (Wompi, transferencia o
  /// efectivo en el punto físico); opcional para el equipo.
  late String? _metodo = widget.pedido?.metodoPago;

  /// Comprobante de la transferencia (obligatorio para el Cliente que paga
  /// por transferencia) y datos de la cuenta a la que debe transferir.
  final _comprobante = DatosPago(metodo: 'transferencia');
  final _referencia = TextEditingController();
  Map<String, dynamic>? _datosPago;

  bool get _pideComprobante => Sesion.i.esCliente && _metodo == 'transferencia';
  bool get _yaTieneComprobante => widget.pedido?.tieneComprobante ?? false;

  bool get _editando => widget.pedido != null;
  double get _total => _lineas.fold(0, (s, l) => s + l.subtotal);

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    // El Cliente siempre pide para sí mismo (la API lo fuerza igual).
    final u = Sesion.i.usuario;
    if (Sesion.i.esCliente && u?.idCliente != null) {
      _cliente = Cliente(id: u!.idCliente!, nombre: u.nombre);
      _canal = 'app';
    }
    if (widget.productoInicial != null) _lineas.add(LineaCarrito(widget.productoInicial!));
    if (widget.desdeCarrito) {
      for (final l in Carrito.i.lineas) {
        _lineas.add(LineaCarrito(l.producto, cantidad: l.cantidad));
      }
    }
    if (Sesion.i.esCliente) {
      datosDePago().then((d) {
        if (mounted) setState(() => _datosPago = d);
      });
    }
    if (_editando) {
      _cargandoEdicion = true;
      _prepararEdicion();
    }
  }

  @override
  void dispose() {
    _direccion.dispose();
    _notas.dispose();
    _referencia.dispose();
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
    if (Sesion.i.esCliente && _metodo == null) {
      mostrarMensaje(context, 'Elige cómo vas a pagar tu pedido.', error: true);
      return;
    }
    if (_pideComprobante && _comprobante.comprobante == null && !_yaTieneComprobante) {
      mostrarMensaje(context, 'Adjunta la foto del comprobante de la transferencia.', error: true);
      return;
    }
    final datos = {
      'id_cliente': _cliente!.id,
      if (_metodo != null) 'metodo_pago': _metodo,
      if (!Sesion.i.esCliente) 'canal': _canal,
      'direccion_entrega': _direccion.text.trim(),
      'notas': _notas.text.trim(),
      'items': _lineas.map((l) => l.aJson()).toList(),
      if (_pideComprobante && _comprobante.comprobante != null) ...{
        'comprobante': _comprobante.aJson()['comprobante'],
      },
      if (_pideComprobante && _referencia.text.trim().isNotEmpty) 'referencia_pago': _referencia.text.trim(),
    };
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/pedidos/${widget.pedido!.id}', datos) : Api.i.post('/api/pedidos', datos),
    );
    if (r == null || !mounted) return;
    final pedido = Pedido.desdeJson(r['datos']);
    if (widget.desdeCarrito) Carrito.i.vaciar();
    mostrarMensaje(context, r['mensaje'] ?? 'Pedido guardado.');
    if (_editando) {
      Navigator.pop(context, pedido);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(idPedido: pedido.id)));
    }
  }

  /// Transferencia: a qué cuenta pagar, comprobante (obligatorio) y referencia.
  Widget _seccionTransferencia(ThemeData tema) {
    final cuenta = _datosPago?['transferencia'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          margin: EdgeInsets.zero,
          color: tema.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.account_balance_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(cuenta == null
                    ? 'Transfiere el total (${dinero(_total)}) a la cuenta que te indicamos por WhatsApp y sube aquí la foto del comprobante.'
                    : 'Transfiere ${dinero(_total)} a:\n$cuenta\n\nLuego sube aquí la foto del comprobante.'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        CampoComprobante(datos: _comprobante, obligatorio: !_yaTieneComprobante, onCambio: () => setState(() {})),
        if (_yaTieneComprobante && _comprobante.comprobante == null)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text('Ya enviaste un comprobante con este pedido. Adjunta otro solo si quieres cambiarlo.',
                style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _referencia,
          decoration: const InputDecoration(
            labelText: 'Número de la transacción (opcional)',
            prefixIcon: Icon(Icons.tag),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar ${widget.pedido!.codigo}' : (Sesion.i.esCliente ? 'Hacer pedido' : 'Nuevo pedido'))),
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
              // El Cliente no elige cliente ni canal: pide para sí, por la app.
              if (!Sesion.i.esCliente) ...[
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
                    // Un pedido que hizo el cliente por la app se deja como está.
                    selected: {_canal == 'app' ? 'whatsapp' : _canal},
                    onSelectionChanged: (s) => setState(() => _canal = s.first),
                  ),
                ),
              ],
              const TituloSeccion('Productos'),
              // El cliente no cambia precios: los pone el catálogo.
              EditorCarrito(lineas: _lineas, onCambio: () => setState(() {}), editarPrecio: !Sesion.i.esCliente),
              TituloSeccion(Sesion.i.esCliente ? '¿Cómo vas a pagar? *' : 'Forma de pago (opcional)'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Sesion.i.esCliente
                    ? Column(children: [
                        for (final e in metodosPedidoCliente.entries)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _metodo == e.key ? tema.colorScheme.primary : tema.colorScheme.outlineVariant,
                                width: _metodo == e.key ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: Icon(iconoMetodo(e.key), color: _metodo == e.key ? tema.colorScheme.primary : null),
                              title: Text(e.value),
                              subtitle: Text(ayudaMetodoPedido[e.key]!),
                              trailing: Icon(_metodo == e.key ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: _metodo == e.key ? tema.colorScheme.primary : null),
                              onTap: () => setState(() => _metodo = e.key),
                            ),
                          ),
                      ])
                    : SelectorMetodo(valor: _metodo, onCambio: (m) => setState(() => _metodo = m)),
              ),
              if (_pideComprobante) _seccionTransferencia(tema),
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
