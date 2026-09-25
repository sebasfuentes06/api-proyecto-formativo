import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../ventas/venta_detalle_screen.dart';

/// Pagos reportados por el cliente, comprobantes y aprobación del
/// Administrador. Lo usan el detalle de la venta, la pestaña Pagos y la
/// cuenta del cliente.

/// Etiqueta del estado de un pago.
Widget etiquetaPago(Pago p) => switch (p.estado) {
      'pendiente' => const Etiqueta('Por aprobar', color: ambar, icono: Icons.hourglass_top),
      'rechazado' => const Etiqueta('Rechazado', color: rojo),
      'anulado' => const Etiqueta('Anulado', color: gris),
      _ => const Etiqueta('Aplicado', color: verde),
    };

/// Una fila de pago. Al tocarla se abre el detalle (comprobante, aprobar...).
class FilaPago extends StatelessWidget {
  const FilaPago({super.key, required this.pago, this.mostrarCliente = false, this.trailing});
  final Pago pago;
  final bool mostrarCliente;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = pago;
    final tachado = p.anulado || p.rechazado;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: tachado
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : p.porAprobar
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFE8F5E9),
        child: Icon(iconoMetodo(p.metodo), color: tachado ? gris : (p.porAprobar ? ambar : verde)),
      ),
      title: Row(children: [
        Expanded(
          child: Text(mostrarCliente ? (p.cliente ?? '') : nombresMetodo[p.metodo] ?? p.metodo, overflow: TextOverflow.ellipsis),
        ),
        Text(dinero(p.monto), style: TextStyle(fontWeight: FontWeight.w700, decoration: tachado ? TextDecoration.lineThrough : null)),
      ]),
      subtitle: Text([
        if (mostrarCliente) '${p.numeroFactura ?? ''} · ${nombresMetodo[p.metodo] ?? p.metodo}',
        [if (!mostrarCliente && p.numeroFactura != null) p.numeroFactura!, fechaHora(p.fecha)].join(' · '),
        if (p.referencia != null) 'Ref. ${p.referencia}',
        if (p.rechazado && p.motivoRechazo != null) 'Motivo: ${p.motivoRechazo}',
      ].join('\n')),
      isThreeLine: mostrarCliente || p.referencia != null || (p.rechazado && p.motivoRechazo != null),
      trailing: trailing ??
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!p.aplicado) etiquetaPago(p),
            if (p.tieneComprobante) const Icon(Icons.receipt_long, size: 18, color: gris),
          ]),
      onTap: () => abrirPago(context, p),
    );
  }
}

/// Imagen del comprobante. La API la sirve solo con sesión, por eso se pide
/// con la cabecera Authorization.
class ImagenComprobante extends StatelessWidget {
  const ImagenComprobante({super.key, required this.pago, this.version = 0, this.alto = 260});
  final Pago pago;
  final int version;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        '${pago.comprobanteUrl}?v=$version',
        headers: {if (Api.i.token != null) 'Authorization': 'Bearer ${Api.i.token}'},
        height: alto,
        fit: BoxFit.contain,
        loadingBuilder: (_, hijo, p) => p == null ? hijo : SizedBox(height: alto, child: const Center(child: CircularProgressIndicator())),
        errorBuilder: (_, __, ___) => SizedBox(height: 80, child: const Center(child: Text('No se pudo cargar el comprobante'))),
      ),
    );
  }
}

/// Detalle de un pago: comprobante y, según el rol, aprobar / rechazar o
/// adjuntar el comprobante.
Future<void> abrirPago(BuildContext context, Pago pago) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaPago(pago: pago),
  );
}

class _HojaPago extends StatefulWidget {
  const _HojaPago({required this.pago});
  final Pago pago;

  @override
  State<_HojaPago> createState() => _HojaPagoState();
}

class _HojaPagoState extends State<_HojaPago> {
  late bool _tieneComprobante = widget.pago.tieneComprobante;
  int _version = 0;

  Pago get p => widget.pago;

  Future<void> _subirComprobante() async {
    final f = await elegirFoto(context);
    if (f == null || !mounted) return;
    final datos = DatosPago()
      ..comprobante = f.bytes
      ..comprobanteMime = f.mime;
    final r = await conCarga(context, Api.i.put('/api/pagos/${p.id}/comprobante', datos.aJson()['comprobante'] as Map<String, dynamic>));
    if (r == null || !mounted) return;
    setState(() {
      _tieneComprobante = true;
      _version++;
    });
    mostrarMensaje(context, 'Comprobante guardado.');
  }

  Future<void> _aprobar() async {
    final ok = await confirmar(
      context,
      titulo: 'Aprobar pago',
      mensaje: '¿Confirmas que recibiste ${dinero(p.monto)} por ${nombresMetodo[p.metodo]}?\n'
          'Se abonará a la factura ${p.numeroFactura ?? ''} y se le avisará al cliente por correo.',
      textoOk: 'Aprobar',
    );
    if (!ok || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/pagos/${p.id}/aprobar'));
    if (r == null || !mounted) return;
    mostrarMensaje(context, r['mensaje'] ?? 'Pago aprobado.');
    Navigator.pop(context);
  }

  Future<void> _rechazar() async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Rechazar pago',
      etiqueta: 'Motivo (le llega al cliente)',
      ayuda: 'Ej. no llegó la transferencia, el valor no coincide, el comprobante no se ve.',
      textoOk: 'Rechazar',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/pagos/${p.id}/rechazar', {'motivo': motivo}));
    if (r == null || !mounted) return;
    mostrarMensaje(context, r['mensaje'] ?? 'Pago rechazado.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final puedeAdjuntar = Sesion.i.esEquipo ? !p.anulado : p.porAprobar;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(dinero(p.monto), style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
          etiquetaPago(p),
        ]),
        const SizedBox(height: 4),
        Text([nombresMetodo[p.metodo] ?? p.metodo, fechaHora(p.fecha)].join(' · ')),
        if (p.numeroFactura != null || p.cliente != null)
          Text([p.numeroFactura, p.cliente].whereType<String>().join(' · '), style: TextStyle(color: tema.colorScheme.outline)),
        if (p.referencia != null) Text('Referencia: ${p.referencia}'),
        if (p.nota != null) Text(p.nota!, style: TextStyle(color: tema.colorScheme.outline)),
        if (p.rechazado && p.motivoRechazo != null) ...[
          const SizedBox(height: 8),
          Text('Motivo del rechazo: ${p.motivoRechazo}', style: const TextStyle(color: rojo)),
        ],
        if (p.porAprobar && Sesion.i.esCliente) ...[
          const SizedBox(height: 8),
          const Text('La administradora está revisando este pago. Te llegará un correo con la respuesta.'),
        ],
        const SizedBox(height: 16),
        Text('Comprobante', style: tema.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_tieneComprobante)
          ImagenComprobante(pago: p, version: _version)
        else
          Text('Sin comprobante adjunto.', style: TextStyle(color: tema.colorScheme.outline)),
        if (puedeAdjuntar) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _subirComprobante,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_tieneComprobante ? 'Cambiar comprobante' : 'Adjuntar comprobante'),
          ),
        ],
        if (p.porAprobar && Sesion.i.esAdmin) ...[
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _rechazar,
                style: OutlinedButton.styleFrom(foregroundColor: rojo, minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.close),
                label: const Text('Rechazar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _aprobar,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.check),
                label: const Text('Aprobar'),
              ),
            ),
          ]),
        ],
        if (Sesion.i.esEquipo && p.numeroFactura != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: p.idVenta)));
            },
            icon: const Icon(Icons.receipt_long),
            label: const Text('Ver la venta'),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// El cliente reporta un pago de su saldo
// ---------------------------------------------------------------------------

/// Datos para pagar que configura el negocio en la API (cuenta para
/// transferir, dirección del punto físico).
Future<Map<String, dynamic>> datosDePago() async {
  try {
    final r = await Api.i.get('/api/pagos/datos-pago');
    return (r['datos'] as Map<String, dynamic>?) ?? {};
  } catch (_) {
    return {};
  }
}

/// El cliente reporta que ya pagó (transferencia, Nequi, Daviplata) y
/// adjunta el comprobante. Queda "por aprobar" hasta que el Administrador lo
/// revise. Devuelve true si se envió.
Future<bool> reportarPago(BuildContext context, Venta venta) async {
  final reportado = venta.pagos.where((p) => p.porAprobar).fold<double>(0, (s, p) => s + p.monto);
  final maximo = venta.saldo - reportado;
  if (maximo <= 0) {
    mostrarMensaje(context, 'Ya reportaste pagos por todo el saldo. Espera la revisión de la administradora.', error: true);
    return false;
  }
  final info = await conCarga(context, datosDePago(), avisarCambio: false);
  if (info == null || !context.mounted) return false;
  final datos = await showModalBottomSheet<DatosPago>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _HojaReporte(venta: venta, maximo: maximo, reportado: reportado, info: info),
  );
  if (datos == null || !context.mounted) return false;
  final r = await conCarga(context, Api.i.post('/api/pagos', {'id_venta': venta.id, ...datos.aJson()}));
  if (r == null || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.hourglass_top, size: 40, color: ambar),
      title: const Text('Pago reportado'),
      content: Text(r['mensaje'] ?? 'La administradora revisará tu pago.'),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
    ),
  );
  return true;
}

class _HojaReporte extends StatefulWidget {
  const _HojaReporte({required this.venta, required this.maximo, required this.reportado, required this.info});
  final Venta venta;
  final double maximo, reportado;
  final Map<String, dynamic> info;

  @override
  State<_HojaReporte> createState() => _HojaReporteState();
}

class _HojaReporteState extends State<_HojaReporte> {
  final _form = GlobalKey<FormState>();
  final _datos = DatosPago(metodo: 'transferencia');

  void _enviar() {
    if (!_form.currentState!.validate()) return;
    if (_datos.comprobante == null && _datos.referencia.trim().isEmpty) {
      mostrarMensaje(context, 'Adjunta la foto del comprobante o escribe el número de la transacción.', error: true);
      return;
    }
    Navigator.pop(context, _datos);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    final tema = Theme.of(context);
    final cuenta = widget.info['transferencia'] as String?;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Reportar un pago', style: tema.textTheme.titleLarge),
            Text('Factura ${v.numeroFactura}'),
            const SizedBox(height: 12),
            FilaValor('Saldo pendiente', dinero(v.saldo), destacado: true, color: rojo),
            if (widget.reportado > 0) FilaValor('Ya reportado (por aprobar)', dinero(widget.reportado)),
            const SizedBox(height: 12),
            Card(
              color: tema.colorScheme.secondaryContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.account_balance_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(cuenta == null
                        ? 'Haz la transferencia a la cuenta que te indicamos por WhatsApp y luego repórtala aquí con la foto del comprobante.'
                        : 'Transfiere a: $cuenta\nLuego repórtala aquí con la foto del comprobante.'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // El cliente no registra efectivo ni tarjeta: eso lo hace la
            // tienda cuando le pagan en persona.
            CamposPago(datos: _datos, maximo: widget.maximo, metodos: metodosReporte, pedirComprobante: false),
            const SizedBox(height: 12),
            CampoComprobante(datos: _datos, obligatorio: true, onCambio: () => setState(() {})),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.send),
              label: const Text('Enviar para aprobación'),
              onPressed: _enviar,
            ),
            const SizedBox(height: 6),
            Text('Tu saldo se actualiza cuando la administradora aprueba el pago.',
                textAlign: TextAlign.center, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
          ]),
        ),
      ),
    );
  }
}

/// Lista de pagos reportados por los clientes que esperan aprobación.
class ListaPorAprobar extends StatelessWidget {
  const ListaPorAprobar({super.key});

  @override
  Widget build(BuildContext context) {
    // La lista se recarga sola cuando se aprueba o rechaza un pago.
    return ListaPaginada<Pago>(
      relleno: const EdgeInsets.only(bottom: 24),
      cargar: (p) => Api.i.pagina('/api/pagos', Pago.desdeJson, query: {'estado': 'pendiente', 'page': p, 'limit': 25}),
      vacio: const EstadoVacio(
        icono: Icons.task_alt,
        titulo: 'No hay pagos por aprobar',
        subtitulo: 'Cuando un cliente reporte una transferencia, aparecerá aquí con su comprobante.',
      ),
      itemBuilder: (ctx, p) => FilaPago(pago: p, mostrarCliente: true),
    );
  }
}

/// Pantalla suelta (se abre desde el aviso del resumen de Ventas).
class PagosPorAprobarScreen extends StatelessWidget {
  const PagosPorAprobarScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Pagos por aprobar')), body: const ListaPorAprobar());
}
