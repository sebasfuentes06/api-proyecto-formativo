import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import '../usuarios/usuarios_screen.dart';
import 'venta_detalle_screen.dart';
import 'venta_form_screen.dart';

/// Subproceso de ventas: registrar ventas, consultar el historial y ver el
/// resumen del negocio.
class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  String _buscar = '';
  String _filtro = 'todas';
  DateTimeRange? _rango;
  Map<String, dynamic>? _resumen;
  Map<String, dynamic> _totales = {};

  @override
  void initState() {
    super.initState();
    Eventos.datos.addListener(_cargarResumen);
    _cargarResumen();
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_cargarResumen);
    super.dispose();
  }

  Future<void> _cargarResumen() async {
    if (!Sesion.i.esEquipo) return; // el cliente no ve los números del negocio
    try {
      final r = await Api.i.get('/api/dashboard/resumen');
      if (mounted) setState(() => _resumen = r['datos']);
    } catch (_) {/* el resumen es un extra: si falla, la lista sigue funcionando */}
  }

  Map<String, dynamic> get _query {
    final hoy = fechaApi(DateTime.now());
    return {
      'search': _buscar,
      if (_filtro == 'hoy') ...{'desde': hoy, 'hasta': hoy},
      if (_filtro == 'saldo') 'estado_pago': 'con_saldo',
      if (_filtro == 'anuladas') 'estado': 'anulada',
      if (_filtro == 'rango' && _rango != null) ...{'desde': fechaApi(_rango!.start), 'hasta': fechaApi(_rango!.end)},
    };
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _rango,
      helpText: 'Ventas entre',
    );
    if (r != null) {
      setState(() {
        _rango = r;
        _filtro = 'rango';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Sesion.i.esCliente ? 'Mis compras' : 'Ventas'),
        actions: [
          IconButton(tooltip: 'Filtrar por fechas', icon: const Icon(Icons.date_range), onPressed: _elegirRango),
          const BotonPerfil(),
        ],
      ),
      floatingActionButton: !Sesion.i.esEquipo
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_ventas',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VentaFormScreen())),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nueva venta'),
            ),
      body: Column(children: [
        CampoBusqueda(pista: 'Factura o cliente', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: {
            'todas': 'Todas',
            'hoy': 'Hoy',
            'saldo': 'Con saldo',
            'anuladas': 'Anuladas',
            if (_rango != null) 'rango': '${fecha(_rango!.start)} – ${fecha(_rango!.end)}',
          },
          valor: _filtro,
          onCambio: (v) => setState(() => _filtro = v),
        ),
        Expanded(
          child: ListaPaginada<Venta>(
            key: ValueKey('$_buscar|$_filtro|${_rango?.start}'),
            encabezado: _encabezado(),
            cargar: (p) => Api.i.pagina('/api/ventas', Venta.desdeJson, query: {..._query, 'page': p, 'limit': 20}),
            alCargar: (p) => setState(() => _totales = p.resumen),
            vacio: EstadoVacio(
              icono: Icons.receipt_long_outlined,
              titulo: Sesion.i.esCliente ? 'Aún no tienes compras aquí' : 'No hay ventas en este filtro',
            ),
            itemBuilder: (ctx, v) => ListTile(
              title: Row(children: [
                Expanded(child: Text(v.cliente, overflow: TextOverflow.ellipsis)),
                Text(dinero(v.total),
                    style: TextStyle(fontWeight: FontWeight.w600, decoration: v.anulada ? TextDecoration.lineThrough : null)),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(child: Text('${v.numeroFactura} · ${fechaHora(v.fecha)}')),
                  etiquetaEstadoPago(v.anulada ? 'anulada' : v.estadoPago),
                ]),
              ),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: v.id))),
            ),
          ),
        ),
      ]),
    );
  }

  /// Tarjetas del resumen (dashboard) arriba de la lista.
  Widget _encabezado() {
    final r = _resumen;
    final tema = Theme.of(context);
    Widget tarjeta(String titulo, String valor, IconData icono, {String? pie, Color? color}) => Expanded(
          child: Card(
            margin: const EdgeInsets.all(4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icono, size: 18, color: color ?? tema.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(titulo, style: tema.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
                ),
                if (pie != null) Text(pie, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
              ]),
            ),
          ),
        );

    final solicitudes = aInt(r?['solicitudes_pendientes']);
    return Column(children: [
      // Aviso para el Administrador: gente que se registró y espera aprobación.
      if (Sesion.i.esAdmin && solicitudes > 0)
        Card(
          color: tema.colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.how_to_reg),
            title: Text('$solicitudes solicitud${solicitudes == 1 ? '' : 'es'} de registro'),
            subtitle: const Text('Toca para aprobar o rechazar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsuariosScreen(soloPendientes: true))),
          ),
        ),
      if (r != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            Row(children: [
              tarjeta(r['alcance'] == 'mis_ventas' ? 'Mis ventas hoy' : 'Hoy', dinero(aNum(r['ventas_hoy'])), Icons.today,
                  pie: '${r['cantidad_hoy']} venta(s)'),
              tarjeta('Este mes', dinero(aNum(r['ventas_mes'])), Icons.calendar_month, pie: '${r['cantidad_mes']} venta(s)'),
            ]),
            Row(children: [
              tarjeta('Por cobrar', dinero(aNum(r['cartera'])), Icons.account_balance_wallet_outlined,
                  pie: '${r['ventas_con_saldo']} venta(s)', color: aNum(r['cartera']) > 0 ? rojo : null),
              tarjeta('Pendientes', '${r['pedidos_pendientes']} pedidos', Icons.assignment_late_outlined,
                  pie: '${r['stock_bajo']} producto(s) con stock bajo', color: aInt(r['pedidos_pendientes']) > 0 ? ambar : null),
            ]),
            if ((r['mas_vendidos'] as List).isNotEmpty)
              Card(
                margin: const EdgeInsets.all(4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Más vendidos del mes', style: tema.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    for (final m in (r['mas_vendidos'] as List).take(3))
                      Row(children: [
                        Expanded(child: Text('${m['nombre']}', overflow: TextOverflow.ellipsis)),
                        Text('${m['unidades']} und.', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                  ]),
                ),
              ),
          ]),
        ),
      if (_totales.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(child: Text('Vendido en el filtro: ${dinero(aNum(_totales['total_vendido']))}', style: tema.textTheme.bodySmall)),
            Text('Saldo: ${dinero(aNum(_totales['saldo_pendiente']))}', style: tema.textTheme.bodySmall),
          ]),
        ),
    ]);
  }
}
