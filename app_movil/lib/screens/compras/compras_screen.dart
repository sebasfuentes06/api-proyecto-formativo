import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';
import '../../widgets/exportar.dart';

/// Compras a proveedores (igual que en la web). Registrar una compra suma al
/// stock; el estado de pago sale de los abonos; cancelar devuelve el stock y
/// solo se eliminan compras canceladas.
class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key, this.proveedor});

  /// Desde la ficha de un proveedor: solo sus compras.
  final Proveedor? proveedor;

  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

const _metodosCompra = ['efectivo', 'transferencia', 'nequi', 'daviplata', 'tarjeta'];

Etiqueta etiquetaCompra(Compra c) {
  if (c.cancelada) return const Etiqueta('Cancelada', color: gris, icono: Icons.block);
  return switch (c.estadoPago) {
    'pagada' => const Etiqueta('Pagada', color: verde, icono: Icons.check_circle),
    'parcial' => const Etiqueta('Parcial', color: ambar, icono: Icons.timelapse),
    _ => const Etiqueta('Pendiente', color: rojo, icono: Icons.schedule),
  };
}

class _ComprasScreenState extends State<ComprasScreen> {
  String _buscar = '';
  String _filtro = 'todas';
  DateTimeRange? _rango;
  Map<String, dynamic> _resumen = const {};

  Map<String, dynamic> get _query => {
        'search': _buscar,
        if (widget.proveedor != null) 'id_proveedor': widget.proveedor!.id,
        if (_filtro == 'canceladas') 'estado': 'cancelada',
        if (['pendiente', 'parcial', 'pagada'].contains(_filtro)) ...{'estado': 'vigente', 'estado_pago': _filtro},
        if (_rango != null) 'desde': fechaApi(_rango!.start),
        if (_rango != null) 'hasta': fechaApi(_rango!.end),
      };

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _rango,
      helpText: 'Compras entre',
    );
    setState(() => _rango = r);
  }

  Future<void> _exportar() async {
    final filas = await Api.i.todos('/api/compras', Compra.desdeJson, query: _query);
    await compartirListadoPdf<Compra>(
      titulo: 'compras',
      filas: filas,
      filtro: widget.proveedor?.nombre,
      columnas: [
        ColumnaPdf('Folio', (c) => c.folio),
        ColumnaPdf('Fecha', (c) => c.fecha),
        ColumnaPdf('Proveedor', (c) => c.proveedor),
        ColumnaPdf('Unidades', (c) => c.unidades, numero: true),
        ColumnaPdf('Total', (c) => c.total, dinero: true),
        ColumnaPdf('Pagado', (c) => c.pagado, dinero: true),
        ColumnaPdf('Saldo', (c) => c.saldo, dinero: true),
        ColumnaPdf('Estado', (c) => c.cancelada ? 'Cancelada' : capitalizar(c.estadoPago)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.proveedor == null ? 'Compras' : 'Compras · ${widget.proveedor!.nombre}'),
        actions: [
          IconButton(
            tooltip: 'Filtrar por fecha',
            icon: Icon(_rango == null ? Icons.date_range_outlined : Icons.date_range, color: _rango == null ? null : tema.colorScheme.primary),
            onPressed: _elegirRango,
          ),
          BotonPdf(exportar: _exportar),
        ],
      ),
      floatingActionButton: !Sesion.i.puede('purchases.create')
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_compras',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompraFormScreen(proveedor: widget.proveedor))),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Registrar compra'),
            ),
      body: Column(children: [
        CampoBusqueda(pista: 'Folio o proveedor', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'todas': 'Todas', 'pendiente': 'Pendientes', 'parcial': 'Parciales', 'pagada': 'Pagadas', 'canceladas': 'Canceladas'},
          valor: _filtro,
          onCambio: (v) => setState(() => _filtro = v),
        ),
        if (_rango != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InputChip(
              label: Text('${fecha(_rango!.start)} – ${fecha(_rango!.end)}'),
              onDeleted: () => setState(() => _rango = null),
            ),
          ),
        if (_resumen.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              Expanded(child: Text('Comprado: ${dinero(aNum(_resumen['comprado']))}', style: tema.textTheme.bodySmall)),
              Text('Por pagar: ${dinero(aNum(_resumen['por_pagar']))}', style: tema.textTheme.bodySmall?.copyWith(color: rojo)),
            ]),
          ),
        Expanded(
          child: ListaPaginada<Compra>(
            key: ValueKey('$_buscar|$_filtro|$_rango'),
            cargar: (p) => Api.i.pagina('/api/compras', Compra.desdeJson, query: {..._query, 'page': p, 'limit': 20}),
            alCargar: (p) {
              if (p.resumen.toString() != _resumen.toString()) setState(() => _resumen = p.resumen);
            },
            vacio: const EstadoVacio(icono: Icons.shopping_bag_outlined, titulo: 'No hay compras en este filtro'),
            itemBuilder: (ctx, c) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
              title: Text('${c.folio} · ${c.proveedor}'),
              subtitle: Text('${fecha(c.fecha)} · ${c.unidades} und. · ${dinero(c.total)}'
                  '${!c.cancelada && c.saldo > 0 ? '\nDebe ${dinero(c.saldo)}' : ''}'),
              isThreeLine: !c.cancelada && c.saldo > 0,
              trailing: etiquetaCompra(c),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => CompraDetalleScreen(idCompra: c.id))),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle
// ---------------------------------------------------------------------------

class CompraDetalleScreen extends StatefulWidget {
  const CompraDetalleScreen({super.key, required this.idCompra});
  final int idCompra;

  @override
  State<CompraDetalleScreen> createState() => _CompraDetalleScreenState();
}

class _CompraDetalleScreenState extends State<CompraDetalleScreen> {
  Compra? _c;
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
      final r = await Api.i.get('/api/compras/${widget.idCompra}');
      if (!mounted) return;
      setState(() {
        _c = Compra.desdeJson(r['datos']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _abonar() async {
    final c = _c!;
    final datos = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _HojaAbono(saldo: c.saldo),
    );
    if (datos == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/compras/${c.id}/pagos', datos));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje'] ?? 'Abono registrado.');
  }

  Future<void> _anularAbono(PagoCompra p) async {
    final ok = await confirmar(
      context,
      titulo: 'Anular abono',
      mensaje: '¿Anular el abono de ${dinero(p.monto)} del ${fecha(p.fecha)}? El saldo de la compra vuelve a subir.',
      textoOk: 'Anular abono',
      peligro: true,
    );
    if (!ok || !mounted) return;
    final r = await conCarga(context, Api.i.delete('/api/compras/${_c!.id}/pagos/${p.id}'));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje'] ?? 'Abono anulado.');
  }

  Future<void> _cancelar() async {
    final c = _c!;
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar ${c.folio}',
      etiqueta: 'Motivo de la cancelación',
      ayuda: 'Se restarán del stock las ${c.items.fold<int>(0, (s, i) => s + i.cantidad)} unidad(es) que entraron. '
          'Solo se puede si la compra no tiene abonos y el stock alcanza.',
      textoOk: 'Cancelar compra',
      peligro: true,
    );
    if (motivo == null || !mounted) return;
    final r = await conCarga(context, Api.i.post('/api/compras/${c.id}/cancelar', {'motivo': motivo}));
    if (r != null && mounted) mostrarMensaje(context, r['mensaje'] ?? 'Compra cancelada.');
  }

  Future<void> _eliminar() async {
    final ok = await eliminarConAviso(
      context,
      nombre: 'Compra ${_c!.folio}',
      ruta: '/api/compras/${_c!.id}',
      nota: 'Nota: solo se pueden eliminar compras canceladas.',
    );
    if (ok && mounted) {
      mostrarMensaje(context, 'Compra eliminada.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorReintentar(error: _error!, onReintentar: _cargar) : const Center(child: CircularProgressIndicator()),
      );
    }
    final tema = Theme.of(context);
    final unidades = c.items.fold<int>(0, (s, i) => s + i.cantidad);
    return Scaffold(
      appBar: AppBar(
        title: Text('Compra ${c.folio}'),
        actions: [
          if (Sesion.i.puede('data.export'))
            IconButton(
              tooltip: 'Descargar PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => conCarga(context, compartirCompraPdf(c), avisarCambio: false),
            ),
          if ((!c.cancelada && Sesion.i.puede('purchases.edit')) || (c.cancelada && Sesion.i.puede('purchases.delete')))
            PopupMenuButton<String>(
              onSelected: (v) => v == 'cancelar' ? _cancelar() : _eliminar(),
              itemBuilder: (_) => [
                if (!c.cancelada && Sesion.i.puede('purchases.edit')) const PopupMenuItem(value: 'cancelar', child: Text('Cancelar compra')),
                if (c.cancelada && Sesion.i.puede('purchases.delete'))
                  const PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: rojo))),
              ],
            ),
        ],
      ),
      bottomNavigationBar: !c.cancelada && c.saldo > 0 && Sesion.i.puede('purchases.create')
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: _abonar,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Registrar abono (debe ${dinero(c.saldo)})'),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
              title: Text(c.proveedor, style: tema.textTheme.titleMedium),
              subtitle: Text('${fecha(c.fecha)}${c.registro != null ? ' · registró ${c.registro}' : ''}'),
              trailing: etiquetaCompra(c),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              FilaValor('Total', dinero(c.total), destacado: true),
              FilaValor('Pagado', dinero(c.pagado), color: verde),
              FilaValor('Saldo', dinero(c.saldo), color: !c.cancelada && c.saldo > 0 ? rojo : verde),
            ]),
          ),
          if (c.cancelada)
            Card(
              color: tema.colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Compra cancelada'),
                subtitle: Text('El stock que había entrado ya se devolvió.${c.motivoCancelacion != null ? '\nMotivo: ${c.motivoCancelacion}' : ''}'),
              ),
            ),
          TituloSeccion('Productos · $unidades und.'),
          for (final i in c.items)
            ListTile(
              title: Text(i.nombre),
              subtitle: Text('${i.cantidad} × ${dinero(i.costoUnitario)}${i.sku.isNotEmpty ? ' · ${i.sku}' : ''}'),
              trailing: Text(dinero(i.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          TituloSeccion('Abonos al proveedor · ${dinero(c.pagado)} de ${dinero(c.total)}'),
          if (c.pagos.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Sin abonos registrados. Por eso la compra figura como Pendiente.')),
          for (final p in c.pagos)
            ListTile(
              leading: Icon(iconoMetodo(p.metodo)),
              title: Text(dinero(p.monto)),
              subtitle: Text('${fechaHora(p.fecha)} · ${nombresMetodo[p.metodo] ?? p.metodo}${p.referencia != null ? ' · ${p.referencia}' : ''}'),
              trailing: Sesion.i.puede('purchases.edit') && !c.cancelada
                  ? IconButton(tooltip: 'Anular abono', icon: const Icon(Icons.delete_outline, color: rojo), onPressed: () => _anularAbono(p))
                  : null,
            ),
          if ((c.notas ?? '').isNotEmpty) ...[
            const TituloSeccion('Notas'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(c.notas!)),
          ],
        ]),
      ),
    );
  }
}

/// Hoja para registrar un abono al proveedor.
class _HojaAbono extends StatefulWidget {
  const _HojaAbono({required this.saldo});
  final double saldo;

  @override
  State<_HojaAbono> createState() => _HojaAbonoState();
}

class _HojaAbonoState extends State<_HojaAbono> {
  final _form = GlobalKey<FormState>();
  final _pago = DatosPago();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Abono al proveedor', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              CamposPago(datos: _pago, maximo: widget.saldo, metodos: _metodosCompra, pedirComprobante: false),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.check),
                label: const Text('Registrar abono'),
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  final j = _pago.aJson()..remove('comprobante');
                  Navigator.pop(context, j);
                },
              ),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Registrar compra
// ---------------------------------------------------------------------------

class _LineaNueva {
  _LineaNueva(this.producto, this.cantidad, this.costo);
  final Producto producto;
  int cantidad;
  int costo;
  int get subtotal => cantidad * costo;
}

class CompraFormScreen extends StatefulWidget {
  const CompraFormScreen({super.key, this.proveedor});
  final Proveedor? proveedor;

  @override
  State<CompraFormScreen> createState() => _CompraFormScreenState();
}

class _CompraFormScreenState extends State<CompraFormScreen> {
  final _form = GlobalKey<FormState>();
  final _folio = TextEditingController();
  final _notas = TextEditingController();
  DateTime _fecha = DateTime.now();
  List<Proveedor>? _proveedores;
  late int? _idProveedor = widget.proveedor?.id;
  final _lineas = <_LineaNueva>[];
  final _pago = DatosPago();
  bool _pagaAhora = false;
  Object? _error;

  int get _total => _lineas.fold(0, (s, l) => s + l.subtotal);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _folio.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await Future.wait([
        Api.i.todos('/api/proveedores', Proveedor.desdeJson, query: {'status': 'active', 'sortBy': 'nombre'}),
        Api.i.get('/api/compras/siguiente-folio'),
      ]);
      if (!mounted) return;
      setState(() {
        _proveedores = r[0] as List<Proveedor>;
        _folio.text = ((r[1] as Map<String, dynamic>)['datos']?['folio'] ?? '').toString();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _agregarProducto() async {
    if (_idProveedor == null) {
      mostrarMensaje(context, 'Primero elige el proveedor.', error: true);
      return;
    }
    final productos = await conCarga(
      context,
      Api.i.todos('/api/productos', Producto.desdeJson, query: {'proveedor': _idProveedor, 'status': 'all', 'sortBy': 'nombre'}),
      avisarCambio: false,
    );
    if (productos == null || !mounted) return;
    if (productos.isEmpty) {
      mostrarMensaje(context, 'Este proveedor no tiene productos en el catálogo.', error: true);
      return;
    }
    final p = await showModalBottomSheet<Producto>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Column(children: [
          Text('Productos del proveedor', style: Theme.of(ctx).textTheme.titleMedium),
          Expanded(
            child: ListView(children: [
              for (final p in productos)
                ListTile(
                  leading: ProductoImagen(p, tam: 44),
                  title: Text(p.nombre),
                  subtitle: Text('${p.sku} · stock ${p.stock}'),
                  enabled: !_lineas.any((l) => l.producto.id == p.id),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (p == null || !mounted) return;
    final datos = await _pedirLinea(p);
    if (datos != null) setState(() => _lineas.add(_LineaNueva(p, datos.$1, datos.$2)));
  }

  /// Pide cantidad y costo unitario de un producto.
  Future<(int, int)?> _pedirLinea(Producto p, [_LineaNueva? actual]) {
    final cantidad = TextEditingController(text: '${actual?.cantidad ?? 1}');
    final costo = TextEditingController(text: actual == null ? '' : '${actual.costo}');
    final form = GlobalKey<FormState>();
    return showDialog<(int, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.nombre),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: cantidad,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Cantidad *'),
              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mayor que cero' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: costo,
              autofocus: actual == null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Costo unitario *', prefixText: '\$ ', helperText: 'Precio de venta: ${dinero(p.precio)}'),
              validator: (v) => leerDinero(v ?? '') == null ? 'Escribe el costo' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, (int.parse(cantidad.text), leerDinero(costo.text)!));
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDate: _fecha);
    if (f != null) setState(() => _fecha = f);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_lineas.isEmpty) {
      mostrarMensaje(context, 'Agrega al menos un producto.', error: true);
      return;
    }
    final hoy = DateTime.now();
    final esHoy = _fecha.year == hoy.year && _fecha.month == hoy.month && _fecha.day == hoy.day;
    final ok = await confirmar(
      context,
      titulo: 'Registrar compra',
      mensaje: 'Proveedor: ${_proveedores?.firstWhere((p) => p.id == _idProveedor).nombre}\n'
          'Total: ${dinero(_total)}\n\nSe sumarán ${_lineas.fold<int>(0, (s, l) => s + l.cantidad)} unidad(es) al stock.',
      textoOk: 'Registrar',
    );
    if (!ok || !mounted) return;
    final r = await conCarga(
      context,
      Api.i.post('/api/compras', {
        'folio': _folio.text.trim(),
        'id_proveedor': _idProveedor,
        if (!esHoy) 'fecha': '${fechaApi(_fecha)}T12:00:00',
        'impuesto': 0,
        'notas': _notas.text.trim(),
        'items': [for (final l in _lineas) {'id_producto': l.producto.id, 'cantidad': l.cantidad, 'costo_unitario': l.costo}],
        if (_pagaAhora && (_pago.monto ?? 0) > 0) 'pago_inicial': _pago.aJson()..remove('comprobante'),
      }),
    );
    if (r == null || !mounted) return;
    mostrarMensaje(context, r['mensaje'] ?? 'Compra registrada.');
    final compra = Compra.desdeJson(r['datos']);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CompraDetalleScreen(idCompra: compra.id)));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final Widget cuerpo;
    if (_error != null) {
      cuerpo = ErrorReintentar(error: _error!, onReintentar: _cargar);
    } else if (_proveedores == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      cuerpo = Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _folio,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Folio', helperText: 'Consecutivo sugerido'),
                    validator: (v) => (v ?? '').trim().length > 20 ? 'Máximo 20' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _elegirFecha,
                    child: InputDecorator(decoration: const InputDecoration(labelText: 'Fecha'), child: Text(fecha(_fecha))),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _idProveedor,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Proveedor *', prefixIcon: Icon(Icons.local_shipping_outlined)),
                items: [for (final p in _proveedores!) DropdownMenuItem(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  if (v != _idProveedor) _lineas.clear();
                  _idProveedor = v;
                }),
                validator: (v) => v == null ? 'Elige el proveedor' : null,
              ),
            ]),
          ),
          const TituloSeccion('Productos'),
          if (_lineas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Agrega los productos que llegaron. Solo salen los de este proveedor.',
                  textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.outline)),
            ),
          for (final l in _lineas)
            Card(
              child: ListTile(
                leading: ProductoImagen(l.producto, tam: 44),
                title: Text(l.producto.nombre),
                subtitle: Text('${l.cantidad} × ${dinero(l.costo)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(dinero(l.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lineas.remove(l))),
                ]),
                onTap: () async {
                  final d = await _pedirLinea(l.producto, l);
                  if (d != null) {
                    setState(() {
                      l.cantidad = d.$1;
                      l.costo = d.$2;
                    });
                  }
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(onPressed: _agregarProducto, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilaValor('Total', dinero(_total), destacado: true)),
          SwitchListTile(
            title: const Text('Abonar ahora'),
            subtitle: const Text('Registrar un pago al proveedor con la compra'),
            value: _pagaAhora,
            onChanged: _total > 0 ? (v) => setState(() => _pagaAhora = v) : null,
          ),
          if (_pagaAhora && _total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CamposPago(key: ValueKey(_total), datos: _pago, maximo: _total.toDouble(), metodos: _metodosCompra, pedirComprobante: false),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(controller: _notas, maxLength: 250, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
          ),
        ]),
      );
    }
    return ProtegerSalida(
      child: Scaffold(
        appBar: AppBar(title: const Text('Registrar compra')),
        bottomNavigationBar: _proveedores == null
            ? null
            : SafeArea(
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
                      label: const Text('Registrar compra'),
                    ),
                  ]),
                ),
              ),
        body: cuerpo,
      ),
    );
  }
}
