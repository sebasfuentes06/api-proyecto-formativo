import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../../widgets/exportar.dart';
import '../../widgets/perfil.dart';
import '../pagos/pago_detalle.dart';
import '../usuarios/usuarios_screen.dart';

/// Inicio (dashboard), igual que en la web: ventas de hoy y del mes, cartera,
/// pedidos por atender, stock bajo, lo más vendido y los avisos pendientes.
/// El Administrador ve el negocio completo; el Vendedor, solo sus ventas.
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key, this.irA});

  /// Para saltar a otra pestaña desde un aviso (Pedidos, Catálogo...).
  final void Function(String pestana)? irA;

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  Map<String, dynamic>? _datos;
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
      final r = await Api.i.get('/api/dashboard/resumen');
      if (!mounted) return;
      setState(() {
        _datos = r['datos'] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    final tema = Theme.of(context);
    final mio = d?['alcance'] == 'mis_ventas';
    final nombre = (Sesion.i.usuario?.nombre ?? '').split(' ').first;

    final Widget cuerpo;
    if (d == null) {
      cuerpo = _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator());
    } else {
      final top = (d['mas_vendidos'] as List? ?? []).cast<Map<String, dynamic>>();
      final maximo = top.isEmpty ? 1 : top.map((t) => aInt(t['unidades'])).reduce((a, b) => a > b ? a : b);
      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Hola, $nombre', style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(mio ? 'Este es el resumen de tus ventas.' : 'Así va el negocio hoy.', style: TextStyle(color: tema.colorScheme.outline)),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            childAspectRatio: 1.55,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _Indicador(titulo: 'Ventas de hoy', valor: dinero(aNum(d['ventas_hoy'])), detalle: '${d['cantidad_hoy']} venta(s)', icono: Icons.today, color: verde),
              _Indicador(titulo: 'Ventas del mes', valor: dinero(aNum(d['ventas_mes'])), detalle: '${d['cantidad_mes']} venta(s)', icono: Icons.calendar_month, color: azul),
              _Indicador(
                titulo: 'Por cobrar',
                valor: dinero(aNum(d['cartera'])),
                detalle: '${d['ventas_con_saldo']} venta(s) con saldo',
                icono: Icons.account_balance_wallet_outlined,
                color: rojo,
                onTap: () => widget.irA?.call('pagos'),
              ),
              _Indicador(
                titulo: 'Pedidos pendientes',
                valor: '${d['pedidos_pendientes']}',
                detalle: 'por atender',
                icono: Icons.assignment_outlined,
                color: ambar,
                onTap: () => widget.irA?.call('pedidos'),
              ),
            ],
          ),
          const TituloSeccion('Avisos'),
          if (aInt(d['stock_bajo']) > 0)
            _Aviso(
              icono: Icons.inventory_2_outlined,
              color: ambar,
              texto: '${d['stock_bajo']} producto(s) con stock bajo',
              detalle: 'Revisa el catálogo para reponer.',
              onTap: () => widget.irA?.call('catalogo'),
            ),
          if (aInt(d['pagos_por_aprobar']) > 0)
            _Aviso(
              icono: Icons.fact_check_outlined,
              color: azul,
              texto: '${d['pagos_por_aprobar']} pago(s) por aprobar · ${dinero(aNum(d['monto_por_aprobar']))}',
              detalle: 'Los reportaron los clientes con su comprobante.',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PagosPorAprobarScreen())),
            ),
          if (aInt(d['solicitudes_pendientes']) > 0 && Sesion.i.puede('users.view'))
            _Aviso(
              icono: Icons.how_to_reg_outlined,
              color: const Color(0xFF6A1B9A),
              texto: '${d['solicitudes_pendientes']} solicitud(es) de registro',
              detalle: 'Apruébalas o recházalas en Usuarios.',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsuariosScreen(soloPendientes: true))),
            ),
          if (aInt(d['stock_bajo']) == 0 && aInt(d['pagos_por_aprobar']) == 0 && aInt(d['solicitudes_pendientes']) == 0)
            const _Aviso(icono: Icons.check_circle_outline, color: verde, texto: 'Todo al día', detalle: 'No hay avisos pendientes.'),
          TituloSeccion(mio ? 'Tus más vendidos del mes' : 'Más vendidos del mes'),
          if (top.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Aún no hay ventas este mes.'))
          else
            for (var i = 0; i < top.length; i++)
              ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text('${top[i]['nombre']}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: aInt(top[i]['unidades']) / maximo, minHeight: 6),
                  ),
                ),
                trailing: Text('${top[i]['unidades']} und.', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          if (d != null) BotonPdf(exportar: () => compartirDashboardPdf(d), tooltip: 'Exportar a PDF'),
          const BotonPerfil(),
        ],
      ),
      body: cuerpo,
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.titulo, required this.valor, required this.detalle, required this.icono, required this.color, this.onTap});
  final String titulo, valor, detalle;
  final IconData icono;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: tema.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Icon(icono, size: 18, color: color),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(detalle, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.color, required this.texto, required this.detalle, this.onTap});
  final IconData icono;
  final Color color;
  final String texto, detalle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: color.withAlpha(30), child: Icon(icono, color: color)),
          title: Text(texto),
          subtitle: Text(detalle),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
