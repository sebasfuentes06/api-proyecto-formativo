import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../clientes/cliente_detalle_screen.dart';
import '../pagos/acciones_pago.dart';

/// Detalle de una venta: factura, pagos/abonos, cobro con Wompi y anulación.
class VentaDetalleScreen extends StatefulWidget {
  const VentaDetalleScreen({super.key, required this.idVenta, this.recienCreada = false});
  final int idVenta;
  final bool recienCreada;

  @override
  State<VentaDetalleScreen> createState() => _VentaDetalleScreenState();
}

class _VentaDetalleScreenState extends State<VentaDetalleScreen> {
  Venta? _venta;
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
      final r = await Api.i.get('/api/ventas/${widget.idVenta}');
      if (!mounted) return;
      setState(() {
        _venta = Venta.desdeJson(r['datos']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _anular() async {
    final v = _venta!;
    final pagosActivos = v.pagos.where((p) => !p.anulado).toList();
    final devolver = pagosActivos.fold<double>(0, (s, p) => s + p.monto);
    final motivo = await pedirTexto(
      context,
      titulo: 'Anular ${v.numeroFactura}',
      etiqueta: 'Motivo de la anulación',
      ayuda: 'Se devolverán ${v.unidades > 0 ? v.unidades : v.items.fold<int>(0, (s, i) => s + i.cantidad)} unidad(es) al stock.'
          '${pagosActivos.isNotEmpty ? '\nSe anularán ${pagosActivos.length} pago(s): debes devolverle ${dinero(devolver)} al cliente.' : ''}'
          '\n\nEsta acción no se puede deshacer.',
      textoOk: 'Anular venta',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/ventas/${v.id}/anular', {'motivo': motivo}));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje']);
  }

  Future<void> _anularPago(Pago p) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Anular pago de ${dinero(p.monto)}',
      etiqueta: 'Motivo',
      ayuda: 'El saldo de la venta vuelve a subir en ${dinero(p.monto)}.',
      textoOk: 'Anular pago',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/pagos/${p.id}/anular', {'motivo': motivo}));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje']);
  }

  void _factura({required bool imprimir}) {
    final v = _venta!;
    if (imprimir) {
      imprimirFactura(v);
    } else {
      compartirFactura(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _venta;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final tema = Theme.of(context);
    final linksActivos = v.links.where((l) => l.estado == 'activo').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(v.numeroFactura),
        actions: [
          IconButton(tooltip: 'Compartir factura', icon: const Icon(Icons.share), onPressed: () => _factura(imprimir: false)),
          PopupMenuButton<String>(
            onSelected: (op) {
              switch (op) {
                case 'imprimir':
                  _factura(imprimir: true);
                case 'verificar':
                  verificarPagoWompi(context);
                case 'anular':
                  _anular();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'imprimir', child: ListTile(leading: Icon(Icons.print), title: Text('Imprimir / guardar PDF'))),
              if (v.debe)
                const PopupMenuItem(value: 'verificar', child: ListTile(leading: Icon(Icons.verified_outlined), title: Text('Verificar pago Wompi'))),
              // Anular es solo del Administrador.
              if (!v.anulada && Sesion.i.esAdmin)
                const PopupMenuItem(value: 'anular', child: ListTile(leading: Icon(Icons.block, color: rojo), title: Text('Anular venta'))),
            ],
          ),
        ],
      ),
      bottomNavigationBar: v.debe && Sesion.i.esCliente
          // El cliente paga su saldo en línea con Wompi.
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: () => pagarConWompi(context, v),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.credit_card),
                  label: Text('Pagar ${dinero(v.saldo)} en línea'),
                ),
              ),
            )
          : v.debe
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => crearLinkWompi(context, v),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                      icon: const Icon(Icons.link),
                      label: const Text('Link Wompi'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => registrarAbono(context, v),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                      icon: const Icon(Icons.payments),
                      label: const Text('Registrar pago'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (widget.recienCreada && !v.anulada)
            Card(
              color: tema.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: verde),
                title: const Text('Venta registrada'),
                subtitle: const Text('Comparte la factura con el cliente.'),
                trailing: FilledButton(onPressed: () => _factura(imprimir: false), child: const Text('Factura')),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                etiquetaEstadoPago(v.anulada ? 'anulada' : v.estadoPago),
                etiquetaCanal(v.canal),
                if (v.pedidoCodigo != null) Etiqueta('Pedido ${v.pedidoCodigo}', color: azul, icono: Icons.assignment),
              ]),
              const SizedBox(height: 8),
              Text(fechaHora(v.fecha), style: TextStyle(color: tema.colorScheme.outline)),
              if (v.anulada && v.motivoAnulacion != null) ...[
                const SizedBox(height: 8),
                Text('Anulada: ${v.motivoAnulacion}', style: const TextStyle(color: rojo)),
              ],
            ]),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(v.cliente),
              subtitle: Text(v.clienteTelefono ?? ''),
              trailing: v.clienteTelefono == null || Sesion.i.esCliente
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.chat, color: Color(0xFF128C7E)),
                      onPressed: () => abrirWhatsApp(v.clienteTelefono,
                          'Hola ${v.cliente.split(' ').first}, te escribimos de Essence Don Aire por tu compra ${v.numeroFactura}.'),
                    ),
              onTap: Sesion.i.esCliente
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteDetalleScreen(idCliente: v.idCliente))),
            ),
          ),
          const TituloSeccion('Productos'),
          for (final i in v.items)
            ListTile(
              dense: true,
              title: Text(i.nombre),
              subtitle: Text('${i.cantidad} × ${dinero(i.precioUnitario)}'),
              trailing: Text(dinero(i.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              const Divider(),
              FilaValor('Subtotal', dinero(v.subtotal)),
              if (v.descuento > 0) FilaValor('Descuento', '- ${dinero(v.descuento)}'),
              FilaValor('Total', dinero(v.total), destacado: true),
              if (!v.anulada) ...[
                FilaValor('Pagado', dinero(v.pagado), color: verde),
                FilaValor(v.saldo < 0 ? 'Saldo a favor' : 'Saldo', dinero(v.saldo.abs()), destacado: true, color: v.saldo > 0 ? rojo : verde),
              ],
            ]),
          ),
          if (v.total > 0 && !v.anulada)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: LinearProgressIndicator(
                value: (v.pagado / v.total).clamp(0, 1).toDouble(),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          TituloSeccion('Pagos (${v.pagos.length})'),
          if (v.pagos.isEmpty) const ListTile(title: Text('Sin pagos todavía')),
          for (final p in v.pagos)
            ListTile(
              leading: Icon(p.metodo == 'wompi' ? Icons.credit_card : Icons.payments_outlined, color: p.anulado ? gris : verde),
              title: Text('${dinero(p.monto)} · ${nombresMetodo[p.metodo] ?? p.metodo}',
                  style: TextStyle(decoration: p.anulado ? TextDecoration.lineThrough : null)),
              subtitle: Text([fechaHora(p.fecha), if (p.referencia != null) 'Ref. ${p.referencia}', if (p.nota != null) p.nota!].join('\n')),
              isThreeLine: p.referencia != null || p.nota != null,
              trailing: p.anulado
                  ? const Etiqueta('Anulado', color: gris)
                  : v.anulada || !Sesion.i.esAdmin
                      ? null
                      : IconButton(tooltip: 'Anular pago', icon: const Icon(Icons.undo), onPressed: () => _anularPago(p)),
            ),
          if (v.links.isNotEmpty) ...[
            TituloSeccion('Links Wompi (${linksActivos.length} activo${linksActivos.length == 1 ? '' : 's'})'),
            for (final l in v.links)
              ListTile(
                leading: Icon(Icons.link, color: l.estado == 'pagado' ? verde : l.estado == 'activo' ? azul : gris),
                title: Text(dinero(l.monto)),
                subtitle: Text('Creado ${fechaHora(l.creadoEn)}'),
                trailing: Etiqueta(capitalizar(l.estado), color: l.estado == 'pagado' ? verde : l.estado == 'activo' ? azul : gris),
                onTap: l.estado != 'activo'
                    ? null
                    : Sesion.i.esCliente
                        ? () => abrirUrl(l.url)
                        : () => mostrarLinkWompi(context, v, l),
              ),
          ],
          if ((v.notas ?? '').isNotEmpty) ...[
            const TituloSeccion('Notas'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(v.notas!)),
          ],
        ]),
      ),
    );
  }
}
