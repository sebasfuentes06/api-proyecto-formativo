import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../pagos/pago_detalle.dart';
import '../ventas/venta_detalle_screen.dart';
import 'pedido_form_screen.dart';

/// Detalle de un pedido: consultarlo, actualizarlo, cancelarlo o
/// convertirlo en venta confirmada.
class PedidoDetalleScreen extends StatefulWidget {
  const PedidoDetalleScreen({super.key, required this.idPedido});
  final int idPedido;

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  Pedido? _pedido;
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
    try {
      final r = await Api.i.get('/api/pedidos/${widget.idPedido}');
      if (!mounted) return;
      setState(() {
        _pedido = Pedido.desdeJson(r['datos']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  int _versionComprobante = 0;

  Future<void> _subirComprobante() async {
    final f = await elegirFoto(context);
    if (f == null || !mounted) return;
    final datos = DatosPago()
      ..comprobante = f.bytes
      ..comprobanteMime = f.mime;
    final r = await conCarga(
      context,
      Api.i.put('/api/pedidos/${widget.idPedido}/comprobante', datos.aJson()['comprobante'] as Map<String, dynamic>),
    );
    if (r == null || !mounted) return;
    setState(() => _versionComprobante++);
    mostrarMensaje(context, 'Comprobante guardado.');
  }

  Future<void> _cancelar() async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar ${_pedido!.codigo}',
      etiqueta: 'Motivo',
      ayuda: 'El pedido queda cancelado y no se podrá convertir en venta.',
      textoOk: 'Cancelar pedido',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/pedidos/${widget.idPedido}/cancelar', {'motivo': motivo}));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje']);
  }

  Future<void> _convertir() async {
    final p = _pedido!;
    if (p.items.any((i) => !i.disponible)) {
      mostrarMensaje(context, 'Hay productos sin stock suficiente. Edita el pedido antes de convertirlo.', error: true);
      return;
    }
    final cierre = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _HojaCierre(subtotal: p.total, metodo: p.metodoPago),
    );
    if (cierre == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/pedidos/${p.id}/convertir', cierre));
    if (r == null || !mounted) return;
    final venta = Venta.desdeJson(r['datos']);
    mostrarMensaje(context, r['mensaje']);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: venta.id)));
  }

  void _confirmarPorWhatsApp() {
    final p = _pedido!;
    final texto = StringBuffer()
      ..writeln('Hola ${p.cliente.split(' ').first}, recibimos tu pedido ${p.codigo} en Essence Don Aire:')
      ..writeln();
    for (final i in p.items) {
      texto.writeln('• ${i.cantidad} × ${i.nombre} — ${dinero(i.subtotal)}');
    }
    texto
      ..writeln()
      ..writeln('Total: ${dinero(p.total)}');
    if ((p.direccionEntrega ?? '').isNotEmpty) texto.writeln('Entrega: ${p.direccionEntrega}');
    texto.writeln('\n¡Gracias por tu compra!');
    abrirWhatsApp(p.clienteTelefono, texto.toString());
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final tema = Theme.of(context);
    final faltantes = p.items.where((i) => !i.disponible).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.codigo),
        actions: [
          if (p.pendiente)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoFormScreen(pedido: p))),
            ),
          if (p.pendiente)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'cancelar' ? _cancelar() : null,
              itemBuilder: (_) => const [PopupMenuItem(value: 'cancelar', child: Text('Cancelar pedido'))],
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // Convertir en venta es del equipo; el cliente solo ve el estado.
          child: p.pendiente && Sesion.i.esEquipo
              ? FilledButton.icon(
                  onPressed: _convertir,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Convertir en venta'),
                )
              : p.pendiente
                  ? Text('Tu pedido está pendiente. Te confirmaremos por WhatsApp.',
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline))
                  : p.idVenta != null && p.estado == 'confirmado'
                  ? FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: p.idVenta!))),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      icon: const Icon(Icons.receipt_long),
                      label: Text(Sesion.i.esCliente && p.metodoPago != 'efectivo'
                          ? 'Ver compra y pagar'
                          : 'Ver venta ${p.numeroFactura ?? ''}'),
                    )
                  : const SizedBox.shrink(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              etiquetaEstadoPedido(p.estado),
              etiquetaCanal(p.canal),
              if (p.metodoPago != null) Etiqueta(nombresMetodo[p.metodoPago] ?? p.metodoPago!, color: azul, icono: iconoMetodo(p.metodoPago!)),
              Text(fechaHora(p.fecha), style: TextStyle(color: tema.colorScheme.outline)),
            ]),
          ),
          if (p.metodoPago != null && p.estado != 'cancelado')
            Card(
              color: tema.colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(iconoMetodo(p.metodoPago!)),
                title: Text(metodosPedidoCliente[p.metodoPago] ?? 'Pago: ${nombresMetodo[p.metodoPago]}'),
                subtitle: Text(_instruccionPago(p)),
              ),
            ),
          if (p.tieneComprobante || (p.pendiente && p.metodoPago == 'transferencia')) ...[
            const TituloSeccion('Comprobante de la transferencia'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (p.tieneComprobante)
                  ImagenComprobante(url: p.comprobanteUrl, version: _versionComprobante, alto: 240)
                else
                  const Text('Este pedido todavía no tiene comprobante.', style: TextStyle(color: rojo)),
                if (p.pendiente) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _subirComprobante,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(p.tieneComprobante ? 'Cambiar comprobante' : 'Adjuntar comprobante'),
                  ),
                ],
              ]),
            ),
          ],
          if (faltantes > 0 && p.pendiente)
            Card(
              color: tema.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text('$faltantes producto(s) ya no tienen stock suficiente'),
                subtitle: const Text('Edita el pedido o espera a que llegue mercancía.'),
              ),
            ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(p.cliente),
              subtitle: Text([p.clienteTelefono, p.direccionEntrega ?? p.clienteDireccion].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
              trailing: p.clienteTelefono == null || !Sesion.i.esEquipo
                  ? null
                  : IconButton(icon: const Icon(Icons.chat, color: Color(0xFF128C7E)), tooltip: 'Confirmar por WhatsApp', onPressed: _confirmarPorWhatsApp),
            ),
          ),
          const TituloSeccion('Productos'),
          for (final i in p.items)
            ListTile(
              title: Text(i.nombre),
              subtitle: Text('${i.cantidad} × ${dinero(i.precioUnitario)}'
                  '${p.pendiente && i.stockActual != null ? ' · stock: ${i.stockActual}' : ''}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dinero(i.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p.pendiente && !i.disponible) const Etiqueta('Sin stock', color: rojo),
              ]),
            ),
          const Divider(),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilaValor('Total', dinero(p.total), destacado: true)),
          if ((p.notas ?? '').isNotEmpty) ...[
            const TituloSeccion('Notas'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(p.notas!)),
          ],
        ]),
      ),
    );
  }
}

/// Qué sigue con el pago, según el método y el estado del pedido.
String _instruccionPago(Pedido p) {
  final m = p.metodoPago;
  if (p.pendiente) {
    if (!Sesion.i.esCliente) {
      return p.tieneComprobante
          ? 'El cliente ya transfirió y adjuntó el comprobante. Al convertirlo en venta, el pago queda en Pagos ▸ Por aprobar.'
          : 'El cliente eligió esta forma de pago. Al convertirlo en venta queda registrada.';
    }
    return switch (m) {
      'wompi' => 'Cuando confirmemos tu pedido podrás pagarlo en línea desde la app.',
      'efectivo' => 'Pagas en efectivo en el punto físico al recoger o recibir tu pedido.',
      _ => p.tieneComprobante
          ? 'Ya enviaste el comprobante. Lo revisamos al confirmar tu pedido.'
          : 'Adjunta la foto del comprobante de tu transferencia.',
    };
  }
  return switch (m) {
    'wompi' => 'Pedido confirmado: entra a la compra y toca "Pagar en línea".',
    'efectivo' => 'Pedido confirmado: el pago se hace en efectivo en el punto físico.',
    _ => p.tieneComprobante
        ? 'Pedido confirmado: tu comprobante quedó en revisión; te avisamos por correo cuando se apruebe.'
        : 'Pedido confirmado: transfiere y entra a la compra para "Reportar pago" con el comprobante.',
  };
}

/// Hoja para cerrar la venta al convertir un pedido: método de pago,
/// descuento y pago inicial.
class _HojaCierre extends StatefulWidget {
  const _HojaCierre({required this.subtotal, this.metodo});
  final double subtotal;
  final String? metodo;

  @override
  State<_HojaCierre> createState() => _HojaCierreState();
}

class _HojaCierreState extends State<_HojaCierre> {
  final _form = GlobalKey<FormState>();
  final _descuento = TextEditingController();
  late final _pago = DatosPago(metodo: widget.metodo == null || widget.metodo == 'wompi' ? 'efectivo' : widget.metodo!);
  // Si el cliente va a pagar con Wompi o transferencia, normalmente todavía
  // no ha pagado nada al confirmar el pedido.
  late bool _registrarPago = widget.metodo == null || widget.metodo == 'efectivo';
  late String? _metodo = widget.metodo;

  double get _total => widget.subtotal - (leerDinero(_descuento.text) ?? 0);

  @override
  void dispose() {
    _descuento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Confirmar venta', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descuento,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Descuento (opcional)', prefixText: '\$ '),
              onChanged: (_) => setState(() {}),
              validator: (v) => (leerDinero(v ?? '') ?? 0) > widget.subtotal ? 'No puede superar el subtotal' : null,
            ),
            const SizedBox(height: 12),
            FilaValor('Subtotal', dinero(widget.subtotal)),
            FilaValor('Total a pagar', dinero(_total < 0 ? 0.0 : _total), destacado: true),
            const Divider(height: 24),
            Text('Método de pago *', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectorMetodo(
              valor: _metodo,
              onCambio: (m) => setState(() {
                _metodo = m;
                if (m != 'wompi') _pago.metodo = m;
              }),
            ),
            if (_metodo != 'wompi') ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('El cliente paga ahora'),
                subtitle: const Text('Pago total o abono inicial'),
                value: _registrarPago,
                onChanged: (v) => setState(() => _registrarPago = v),
              ),
              if (_registrarPago)
                CamposPago(key: ValueKey('$_total|$_metodo'), datos: _pago, maximo: _total < 0 ? 0.0 : _total),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('El cliente paga con Wompi desde su app (o le envías el link desde la venta).'),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.check),
              label: const Text('Confirmar venta'),
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                Navigator.pop(context, {
                  'metodo_pago': _metodo,
                  'descuento': leerDinero(_descuento.text) ?? 0,
                  if (_metodo != 'wompi' && _registrarPago && (_pago.monto ?? 0) > 0) 'pago_inicial': _pago.aJson(),
                });
              },
            ),
          ]),
        ),
      ),
    );
  }
}
