import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import '../clientes/cliente_detalle_screen.dart';
import '../ventas/venta_detalle_screen.dart';
import 'acciones_pago.dart';

/// Subproceso de pagos y abonos: cartera pendiente por cliente (con reporte
/// PDF y recordatorio por WhatsApp) e historial de pagos recibidos.
class PagosScreen extends StatelessWidget {
  const PagosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pagos y abonos'),
          actions: [
            IconButton(tooltip: 'Verificar pago Wompi', icon: const Icon(Icons.verified_outlined), onPressed: () => verificarPagoWompi(context)),
            const BotonPerfil(),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Por cobrar'), Tab(text: 'Pagos recibidos')]),
        ),
        body: const TabBarView(children: [_Cartera(), _Historial()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cartera pendiente (reporte de pagos pendientes)
// ---------------------------------------------------------------------------

class _Cartera extends StatefulWidget {
  const _Cartera();

  @override
  State<_Cartera> createState() => _CarteraState();
}

class _CarteraState extends State<_Cartera> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _datos;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

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
      final r = await Api.i.get('/api/pagos/pendientes');
      if (!mounted) return;
      setState(() {
        _datos = r['datos'];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _recordar(Map<String, dynamic> c) {
    final ventas = (c['ventas'] as List).cast<Map<String, dynamic>>();
    final texto = StringBuffer()
      ..writeln('Hola ${c['cliente'].toString().split(' ').first}, te saludamos de Essence Don Aire.')
      ..writeln('Te recordamos tu saldo pendiente:')
      ..writeln();
    for (final v in ventas) {
      texto.writeln('• ${v['numero_factura']} del ${fecha(aFecha(v['fecha']))}: ${dinero(aNum(v['saldo']))}');
    }
    texto
      ..writeln()
      ..writeln('Total: ${dinero(aNum(c['saldo']))}')
      ..writeln('Puedes abonar en el local, por Nequi/transferencia o te enviamos un link de pago. ¡Gracias!');
    abrirWhatsApp(c['telefono'], texto.toString());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_datos == null) {
      return _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator());
    }
    final tema = Theme.of(context);
    final clientes = (_datos!['clientes'] as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          color: clientes.isEmpty ? tema.colorScheme.primaryContainer : tema.colorScheme.errorContainer,
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text('Total por cobrar', style: tema.textTheme.titleSmall),
              Text(dinero(aNum(_datos!['total_pendiente'])), style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('${_datos!['cantidad_ventas']} venta(s) · ${_datos!['cantidad_clientes']} cliente(s)'),
              if (clientes.isNotEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => compartirReportePendientes(_datos!),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Reporte PDF'),
                ),
              ],
            ]),
          ),
        ),
        if (clientes.isEmpty)
          const EstadoVacio(icono: Icons.celebration_outlined, titulo: 'Nadie debe nada', subtitulo: 'Todas las ventas están pagadas.'),
        for (final c in clientes)
          Card(
            child: ExpansionTile(
              shape: const Border(),
              leading: CircleAvatar(child: Text(c['cliente'].toString().substring(0, 1).toUpperCase())),
              title: Text(c['cliente']),
              subtitle: Text('${(c['ventas'] as List).length} venta(s) · ${c['telefono'] ?? 'sin teléfono'}'),
              trailing: Text(dinero(aNum(c['saldo'])), style: const TextStyle(color: rojo, fontWeight: FontWeight.w700)),
              children: [
                for (final v in (c['ventas'] as List).cast<Map<String, dynamic>>())
                  ListTile(
                    dense: true,
                    title: Text('${v['numero_factura']} · ${fecha(aFecha(v['fecha']))}'),
                    subtitle: Text('Total ${dinero(aNum(v['total']))} · pagado ${dinero(aNum(v['pagado']))} · ${v['dias']} días'),
                    trailing: Text(dinero(aNum(v['saldo'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: v['id_venta']))),
                  ),
                OverflowBar(alignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteDetalleScreen(idCliente: c['id_cliente']))),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Estado de cuenta'),
                  ),
                  if (c['telefono'] != null)
                    TextButton.icon(onPressed: () => _recordar(c), icon: const Icon(Icons.chat), label: const Text('Recordar')),
                ]),
              ],
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Historial de pagos
// ---------------------------------------------------------------------------

class _Historial extends StatefulWidget {
  const _Historial();

  @override
  State<_Historial> createState() => _HistorialState();
}

class _HistorialState extends State<_Historial> with AutomaticKeepAliveClientMixin {
  String _buscar = '';
  String _metodo = '';
  double _recaudado = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      CampoBusqueda(pista: 'Factura, cliente o referencia', onBuscar: (v) => setState(() => _buscar = v)),
      FiltroChips<String>(
        opciones: {'': 'Todos', for (final e in nombresMetodo.entries) e.key: e.value},
        valor: _metodo,
        onCambio: (v) => setState(() => _metodo = v),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(children: [
          Text('Recaudado en el filtro: ', style: Theme.of(context).textTheme.bodySmall),
          Text(dinero(_recaudado), style: const TextStyle(fontWeight: FontWeight.w700, color: verde)),
        ]),
      ),
      Expanded(
        child: ListaPaginada<Pago>(
          key: ValueKey('$_buscar|$_metodo'),
          relleno: const EdgeInsets.only(bottom: 24),
          cargar: (p) => Api.i.pagina('/api/pagos', Pago.desdeJson, query: {'search': _buscar, 'metodo': _metodo, 'page': p, 'limit': 25}),
          alCargar: (p) {
            final r = aNum(p.resumen['recaudado']);
            if (r != _recaudado) setState(() => _recaudado = r);
          },
          vacio: const EstadoVacio(icono: Icons.payments_outlined, titulo: 'No hay pagos registrados'),
          itemBuilder: (ctx, p) => ListTile(
            leading: CircleAvatar(
              backgroundColor: p.anulado ? Theme.of(ctx).colorScheme.surfaceContainerHighest : const Color(0xFFE8F5E9),
              child: Icon(p.metodo == 'wompi' ? Icons.credit_card : Icons.payments_outlined, color: p.anulado ? gris : verde),
            ),
            title: Row(children: [
              Expanded(child: Text(p.cliente ?? '', overflow: TextOverflow.ellipsis)),
              Text(dinero(p.monto),
                  style: TextStyle(fontWeight: FontWeight.w700, decoration: p.anulado ? TextDecoration.lineThrough : null)),
            ]),
            subtitle: Text('${p.numeroFactura} · ${nombresMetodo[p.metodo] ?? p.metodo} · ${fechaHora(p.fecha)}'),
            trailing: p.anulado ? const Etiqueta('Anulado', color: gris) : null,
            onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: p.idVenta))),
          ),
        ),
      ),
    ]);
  }
}
