import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/comunes.dart';
import '../pagos/pago_detalle.dart';
import '../pedidos/pedido_form_screen.dart';
import '../ventas/venta_detalle_screen.dart';
import '../ventas/venta_form_screen.dart';
import '../usuarios/usuario_form_screen.dart';
import 'cliente_form_screen.dart';

/// Ficha del cliente: datos, historial de compras y estado de cuenta.
class ClienteDetalleScreen extends StatefulWidget {
  const ClienteDetalleScreen({super.key, required this.idCliente});
  final int idCliente;

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  Cliente? _cliente;
  Map<String, dynamic>? _historial;
  Map<String, dynamic>? _cuenta;
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
      final r = await Future.wait([
        Api.i.get('/api/clientes/${widget.idCliente}'),
        Api.i.get('/api/clientes/${widget.idCliente}/historial'),
        Api.i.get('/api/clientes/${widget.idCliente}/estado-cuenta'),
      ]);
      if (!mounted) return;
      setState(() {
        _cliente = Cliente.desdeJson(r[0]['datos']);
        _historial = r[1]['datos'];
        _cuenta = r[2]['datos'];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cambiarEstado() async {
    final c = _cliente!;
    final ok = await confirmar(
      context,
      titulo: c.estado ? 'Desactivar cliente' : 'Activar cliente',
      mensaje: c.estado
          ? '${c.nombre} no aparecerá al registrar ventas ni pedidos. Su historial se conserva.'
          : '${c.nombre} volverá a estar disponible para ventas y pedidos.',
      textoOk: c.estado ? 'Desactivar' : 'Activar',
      peligro: c.estado,
    );
    if (!ok || !mounted) return;
    final r = await conCarga(context, Api.i.put('/api/clientes/${c.id}', {'estado': !c.estado}));
    if (r != null && mounted) mostrarMensaje(context, c.estado ? 'Cliente desactivado.' : 'Cliente activado.');
  }

  void _enviarEstadoCuenta() {
    final c = _cliente!;
    final res = _cuenta!['resumen'] as Map<String, dynamic>;
    final ventas = (_cuenta!['ventas'] as List).cast<Map<String, dynamic>>().where((v) => aNum(v['saldo']) > 0);
    final texto = StringBuffer()
      ..writeln('Hola ${c.nombre.split(' ').first}, te saludamos de Essence Don Aire.')
      ..writeln()
      ..writeln('Tu estado de cuenta:');
    for (final v in ventas) {
      texto.writeln('• ${v['numero_factura']} (${fecha(aFecha(v['fecha']))}): saldo ${dinero(aNum(v['saldo']))}');
    }
    texto
      ..writeln()
      ..writeln('Total pendiente: ${dinero(aNum(res['saldo']))}')
      ..writeln('¡Gracias por tu compra!');
    abrirWhatsApp(c.telefono, texto.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (_cliente == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final c = _cliente!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.nombre),
          actions: [
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteFormScreen(cliente: c))),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'estado') _cambiarEstado();
                if (v == 'pdf') compartirEstadoCuentaPdf(c, _cuenta!);
                if (v == 'acceso') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => UsuarioFormScreen(clienteInicial: c)));
                }
              },
              itemBuilder: (_) => [
                // Activar/desactivar clientes y darles acceso es del Administrador.
                if (Sesion.i.esAdmin)
                  PopupMenuItem(value: 'estado', child: Text(c.estado ? 'Desactivar cliente' : 'Activar cliente')),
                if (Sesion.i.esAdmin) const PopupMenuItem(value: 'acceso', child: Text('Dar acceso a la app')),
                const PopupMenuItem(value: 'pdf', child: Text('Estado de cuenta en PDF')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Datos'), Tab(text: 'Compras'), Tab(text: 'Cuenta')]),
        ),
        bottomNavigationBar: c.estado
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoFormScreen(cliente: c))),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Pedido'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaFormScreen(cliente: c))),
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Venta'),
                      ),
                    ),
                  ]),
                ),
              )
            : null,
        body: TabBarView(children: [
          RefreshIndicator(onRefresh: _cargar, child: _tabDatos(c)),
          RefreshIndicator(onRefresh: _cargar, child: _tabCompras()),
          RefreshIndicator(onRefresh: _cargar, child: _tabCuenta(c)),
        ]),
      ),
    );
  }

  Widget _tabDatos(Cliente c) {
    final tema = Theme.of(context);
    final res = _historial!['resumen'] as Map<String, dynamic>;
    final favoritos = (_historial!['favoritos'] as List).cast<Map<String, dynamic>>();
    Widget dato(IconData i, String etiqueta, String? valor) => ListTile(
          leading: Icon(i),
          title: Text(valor == null || valor.isEmpty ? '—' : valor),
          subtitle: Text(etiqueta),
          dense: true,
        );
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          CircleAvatar(radius: 30, child: Text(c.iniciales, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.nombre, style: tema.textTheme.titleLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                c.estado ? const Etiqueta('Activo', color: verde) : const Etiqueta('Inactivo', color: gris),
                if (c.saldoPendiente > 0) Etiqueta('Debe ${dinero(c.saldoPendiente)}', color: rojo),
              ]),
            ]),
          ),
        ]),
      ),
      if (c.telefono != null && c.telefono!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => abrirWhatsApp(c.telefono, 'Hola ${c.nombre.split(' ').first}, te saludamos de Essence Don Aire.'),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => llamar(c.telefono!),
                icon: const Icon(Icons.call),
                label: const Text('Llamar'),
              ),
            ),
          ]),
        ),
      const TituloSeccion('Contacto'),
      dato(Icons.phone_outlined, 'Teléfono', c.telefono),
      dato(Icons.home_outlined, 'Dirección', [c.direccion, c.ciudad].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
      dato(Icons.mail_outline, 'Correo', c.correo),
      dato(Icons.badge_outlined, 'Documento', c.documento == null ? null : '${c.tipoDocumento ?? ''} ${c.documento}'.trim()),
      if (c.notas != null && c.notas!.isNotEmpty) dato(Icons.notes, 'Notas', c.notas),
      const TituloSeccion('Resumen'),
      dato(Icons.shopping_bag_outlined, 'Compras confirmadas', '${res['compras']}'),
      dato(Icons.attach_money, 'Total comprado', dinero(aNum(res['total_comprado']))),
      dato(Icons.event_outlined, 'Última compra', fecha(aFecha(res['ultima_compra']))),
      dato(Icons.person_add_alt, 'Cliente desde', fecha(c.fechaRegistro)),
      if (favoritos.isNotEmpty) ...[
        const TituloSeccion('Sus favoritos'),
        for (final f in favoritos)
          ListTile(dense: true, leading: const Icon(Icons.favorite_border), title: Text(f['nombre']), trailing: Text('${f['unidades']} und.')),
      ],
    ]);
  }

  Widget _tabCompras() {
    final ventas = (_historial!['ventas'] as List).cast<Map<String, dynamic>>();
    if (ventas.isEmpty) {
      return ListView(children: const [
        EstadoVacio(icono: Icons.shopping_bag_outlined, titulo: 'Aún no ha comprado', subtitulo: 'Registra su primera venta con el botón de abajo.'),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: ventas.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
      itemBuilder: (ctx, i) {
        final v = ventas[i];
        final productos = (v['productos'] as List).map((p) => '${p['cantidad']}× ${p['nombre']}').join(', ');
        return ListTile(
          title: Row(children: [
            Expanded(child: Text('${v['numero_factura']}')),
            Text(dinero(aNum(v['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(productos, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Text(fecha(aFecha(v['fecha']))),
              const Spacer(),
              etiquetaEstadoPago(v['estado'] == 'anulada' ? 'anulada' : v['estado_pago']),
            ]),
          ]),
          onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: v['id_venta']))),
        );
      },
    );
  }

  Widget _tabCuenta(Cliente c) {
    final tema = Theme.of(context);
    final res = _cuenta!['resumen'] as Map<String, dynamic>;
    final ventas = (_cuenta!['ventas'] as List).cast<Map<String, dynamic>>().where((v) => aNum(v['saldo']) > 0).toList();
    final pagos = (_cuenta!['pagos'] as List).map((p) => Pago.desdeJson(p)).toList();
    final saldo = aNum(res['saldo']);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Card(
        color: saldo > 0 ? tema.colorScheme.errorContainer : tema.colorScheme.primaryContainer,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(saldo > 0 ? 'Saldo pendiente' : 'Al día', style: tema.textTheme.titleSmall),
            Text(dinero(saldo), style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FilaValor('Total facturado', dinero(aNum(res['total_facturado']))),
            FilaValor('Total pagado', dinero(aNum(res['total_pagado']))),
            if (saldo > 0 && c.telefono != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: _enviarEstadoCuenta, icon: const Icon(Icons.chat), label: const Text('Enviar por WhatsApp')),
            ],
          ]),
        ),
      ),
      if (ventas.isNotEmpty) ...[
        const TituloSeccion('Ventas con saldo'),
        for (final v in ventas)
          ListTile(
            title: Text('${v['numero_factura']} · ${fecha(aFecha(v['fecha']))}'),
            subtitle: Text('Total ${dinero(aNum(v['total']))} · pagado ${dinero(aNum(v['pagado']))} · hace ${v['dias']} días'),
            trailing: Text(dinero(aNum(v['saldo'])), style: const TextStyle(color: rojo, fontWeight: FontWeight.w700)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaDetalleScreen(idVenta: v['id_venta']))),
          ),
      ],
      const TituloSeccion('Últimos pagos'),
      if (pagos.isEmpty) const ListTile(title: Text('Sin pagos registrados')),
      for (final p in pagos) FilaPago(pago: p),
    ]);
  }
}
