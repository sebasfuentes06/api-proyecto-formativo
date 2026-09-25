import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import '../pagos/acciones_pago.dart';
import '../pagos/pago_detalle.dart';
import '../ventas/venta_detalle_screen.dart';

/// "Mi cuenta" del rol Cliente: cuánto debe, qué compras tienen saldo (para
/// pagarlas en línea con Wompi o reportar una transferencia con su
/// comprobante) y sus pagos, incluidos los que están por aprobar.
class MiCuentaScreen extends StatefulWidget {
  const MiCuentaScreen({super.key});

  @override
  State<MiCuentaScreen> createState() => _MiCuentaScreenState();
}

class _MiCuentaScreenState extends State<MiCuentaScreen> {
  Map<String, dynamic>? _cuenta;
  Object? _error;

  int? get _idCliente => Sesion.i.usuario?.idCliente;

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
    if (_idCliente == null) return;
    try {
      final r = await Api.i.get('/api/clientes/$_idCliente/estado-cuenta');
      if (!mounted) return;
      setState(() {
        _cuenta = r['datos'];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Para pagar hace falta la venta completa (saldo al día, cliente...).
  Future<void> _pagar(int idVenta) async {
    final forma = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('¿Cómo vas a pagar?', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(
            leading: const Icon(Icons.credit_card),
            title: const Text('Pagar en línea con Wompi'),
            subtitle: const Text('Tarjeta, PSE, Nequi o Bancolombia. Se abona al instante.'),
            onTap: () => Navigator.pop(ctx, 'wompi'),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Ya transferí: reportar pago'),
            subtitle: const Text('Sube la foto del comprobante. La administradora lo aprueba.'),
            onTap: () => Navigator.pop(ctx, 'reporte'),
          ),
        ]),
      ),
    );
    if (forma == null || !mounted) return;
    final r = await conCarga(context, Api.i.get('/api/ventas/$idVenta'), avisarCambio: false);
    if (r == null || !mounted) return;
    final venta = Venta.desdeJson(r['datos']);
    if (forma == 'wompi') {
      await pagarConWompi(context, venta);
    } else if (await reportarPago(context, venta)) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final Widget cuerpo;
    if (_idCliente == null) {
      cuerpo = const EstadoVacio(icono: Icons.link_off, titulo: 'Tu usuario no está enlazado a una ficha de cliente');
    } else if (_cuenta == null) {
      cuerpo = _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator());
    } else {
      final res = _cuenta!['resumen'] as Map<String, dynamic>;
      final saldo = aNum(res['saldo']);
      final conSaldo = (_cuenta!['ventas'] as List).cast<Map<String, dynamic>>().where((v) => aNum(v['saldo']) > 0).toList();
      final pagos = (_cuenta!['pagos'] as List).map((p) => Pago.desdeJson(p)).toList();

      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Card(
            color: saldo > 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(saldo > 0 ? 'Tu saldo pendiente' : '¡Estás al día!', style: tema.textTheme.titleSmall),
                Text(dinero(saldo), style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FilaValor('Total comprado', dinero(aNum(res['total_facturado']))),
                FilaValor('Total pagado', dinero(aNum(res['total_pagado']))),
              ]),
            ),
          ),
          if (conSaldo.isNotEmpty) ...[
            const TituloSeccion('Compras por pagar'),
            for (final v in conSaldo)
              Card(
                child: ListTile(
                  title: Text('${v['numero_factura']} · ${fecha(aFecha(v['fecha']))}'),
                  subtitle: Text('Total ${dinero(aNum(v['total']))} · pagado ${dinero(aNum(v['pagado']))}'),
                  trailing: FilledButton(onPressed: () => _pagar(aInt(v['id_venta'])), child: Text('Pagar ${dinero(aNum(v['saldo']))}')),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: aInt(v['id_venta'])))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Paga en línea con Wompi o, si ya transferiste, reporta el pago con la foto del comprobante. '
                'Desliza hacia abajo para ver tu saldo al día.',
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
              ),
            ),
          ],
          const TituloSeccion('Mis pagos'),
          if (pagos.isEmpty) const ListTile(title: Text('Aún no hay pagos registrados')),
          if (pagos.any((p) => p.porAprobar))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Los pagos "Por aprobar" se descuentan de tu saldo cuando la administradora los revisa.',
                  style: tema.textTheme.bodySmall?.copyWith(color: ambar)),
            ),
          for (final p in pagos) FilaPago(pago: p),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta'), actions: const [BotonPerfil()]),
      body: cuerpo,
    );
  }
}
