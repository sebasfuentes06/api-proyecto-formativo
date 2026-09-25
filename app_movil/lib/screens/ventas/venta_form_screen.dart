import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../../widgets/selectores.dart';
import 'venta_detalle_screen.dart';

/// Registrar una venta directa (sin pedido previo). Al guardarla se genera
/// la factura y se descuenta el stock en ese mismo momento.
class VentaFormScreen extends StatefulWidget {
  const VentaFormScreen({super.key, this.cliente, this.productoInicial});
  final Cliente? cliente;
  final Producto? productoInicial;

  @override
  State<VentaFormScreen> createState() => _VentaFormScreenState();
}

class _VentaFormScreenState extends State<VentaFormScreen> {
  final _form = GlobalKey<FormState>();
  Cliente? _cliente;
  String _canal = 'punto_fisico';
  final _lineas = <LineaCarrito>[];
  final _descuento = TextEditingController();
  final _notas = TextEditingController();
  final _pago = DatosPago();
  bool _pagaAhora = true;

  /// Cómo va a pagar el cliente esta venta (obligatorio).
  String? _metodo;

  /// Con Wompi el dinero entra por el link de pago, no se registra a mano.
  bool get _esWompi => _metodo == 'wompi';

  double get _subtotal => _lineas.fold(0, (s, l) => s + l.subtotal);
  double get _total {
    final t = _subtotal - (leerDinero(_descuento.text) ?? 0);
    return t < 0 ? 0.0 : t;
  }

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    if (widget.productoInicial != null) _lineas.add(LineaCarrito(widget.productoInicial!));
  }

  @override
  void dispose() {
    _descuento.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _elegirCliente() async {
    final c = await elegirCliente(context);
    if (c != null && mounted) setState(() => _cliente = c);
  }

  /// Venta rápida en el local a alguien que no quiere dar sus datos. Usa (o
  /// crea la primera vez) un cliente genérico "Consumidor final".
  Future<void> _consumidorFinal() async {
    final r = await conCarga(context, () async {
      final p = await Api.i.pagina('/api/clientes', Cliente.desdeJson, query: {'search': 'Consumidor final', 'limit': 1});
      if (p.items.isNotEmpty) return p.items.first;
      // "Consumidor final" con NIT 222222222222, como en la facturación
      // colombiana; el celular es el de la tienda.
      final creado = await Api.i.post('/api/clientes', {
        'nombre': 'Consumidor final',
        'tipo_documento': 'NIT',
        'documento': '222222222222',
        'telefono': Config.telefono.replaceAll(RegExp(r'[^0-9]'), ''),
        'ciudad': 'La Pintada',
        'notas': 'Ventas de mostrador sin datos del cliente',
      });
      return Cliente.desdeJson(creado['datos']);
    }(), avisarCambio: false);
    if (r != null && mounted) setState(() => _cliente = r);
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
    if (!_form.currentState!.validate()) {
      if (_metodo == null) mostrarMensaje(context, 'Elige el método de pago.', error: true);
      return;
    }

    final pagoValido = !_esWompi && _pagaAhora && (_pago.monto ?? 0) > 0;
    final ok = await confirmar(
      context,
      titulo: 'Confirmar venta',
      mensaje: 'Cliente: ${_cliente!.nombre}\n'
          'Total: ${dinero(_total)}\n'
          'Método de pago: ${nombresMetodo[_metodo]}\n'
          '${pagoValido ? 'Paga ahora: ${dinero(_pago.monto!)} (${nombresMetodo[_pago.metodo]})' : _esWompi ? 'Se paga con link de Wompi (lo envías en el siguiente paso)' : 'Queda a crédito'}\n\n'
          'Se descontará el stock y se generará la factura.',
      textoOk: 'Registrar venta',
    );
    if (!ok || !mounted) return;

    final r = await conCarga(
      context,
      Api.i.post('/api/ventas', {
        'id_cliente': _cliente!.id,
        'canal': _canal,
        'metodo_pago': _metodo,
        'items': _lineas.map((l) => l.aJson()).toList(),
        'descuento': leerDinero(_descuento.text) ?? 0,
        'notas': _notas.text.trim(),
        if (pagoValido) 'pago_inicial': _pago.aJson(),
      }),
    );
    if (r == null || !mounted) return;
    final venta = Venta.desdeJson(r['datos']);
    mostrarMensaje(context, r['mensaje'] ?? 'Venta registrada.');
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: venta.id, recienCreada: true)));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva venta')),
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
              onPressed: _guardar,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.check),
              label: const Text('Registrar venta'),
            ),
          ]),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          TituloSeccion(
            'Cliente',
            accion: _cliente == null ? TextButton(onPressed: _consumidorFinal, child: const Text('Consumidor final')) : null,
          ),
          Card(
            child: ListTile(
              leading: CircleAvatar(child: _cliente == null ? const Icon(Icons.person_search) : Text(_cliente!.iniciales)),
              title: Text(_cliente?.nombre ?? 'Elegir cliente'),
              subtitle: _cliente == null
                  ? const Text('Toca para buscar o registrar')
                  : Text(_cliente!.saldoPendiente > 0 ? 'Ya debe ${dinero(_cliente!.saldoPendiente)}' : (_cliente!.telefono ?? '')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _elegirCliente,
            ),
          ),
          const TituloSeccion('Canal'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'punto_fisico', label: Text('Punto físico'), icon: Icon(Icons.storefront)),
                ButtonSegment(value: 'whatsapp', label: Text('WhatsApp'), icon: Icon(Icons.chat)),
              ],
              selected: {_canal},
              onSelectionChanged: (s) => setState(() => _canal = s.first),
            ),
          ),
          const TituloSeccion('Productos'),
          EditorCarrito(lineas: _lineas, onCambio: () => setState(() {})),
          const TituloSeccion('Totales'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              TextFormField(
                controller: _descuento,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Descuento (opcional)', prefixText: '\$ '),
                onChanged: (_) => setState(() {}),
                validator: (v) => (leerDinero(v ?? '') ?? 0) > _subtotal ? 'No puede superar el subtotal' : null,
              ),
              const SizedBox(height: 8),
              FilaValor('Subtotal', dinero(_subtotal)),
              if ((leerDinero(_descuento.text) ?? 0) > 0) FilaValor('Descuento', '- ${dinero(leerDinero(_descuento.text)!)}'),
              FilaValor('Total', dinero(_total), destacado: true),
            ]),
          ),
          const TituloSeccion('Método de pago *'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectorMetodo(
              valor: _metodo,
              onCambio: (m) => setState(() {
                _metodo = m;
                if (m != 'wompi') _pago.metodo = m;
              }),
            ),
          ),
          if (_esWompi)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Al registrar la venta podrás crear el link de Wompi y enviárselo al cliente por WhatsApp.'),
            )
          else if (_metodo != null) ...[
            SwitchListTile(
              title: const Text('El cliente paga ahora'),
              subtitle: Text(_pagaAhora ? 'Pago total o abono inicial' : 'La venta queda a crédito (se abona después)'),
              value: _pagaAhora,
              onChanged: (v) => setState(() => _pagaAhora = v),
            ),
            if (_pagaAhora && _total > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CamposPago(key: ValueKey('$_total|$_metodo'), datos: _pago, maximo: _total, obligatorio: false),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(controller: _notas, maxLength: 250, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          ),
        ]),
      ),
    );
  }
}
