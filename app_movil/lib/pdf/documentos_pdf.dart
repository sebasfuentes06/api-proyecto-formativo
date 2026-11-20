import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/config.dart';
import '../core/formato.dart';
import '../models/modelos.dart';

/// Documentos PDF de la app, con el mismo diseño que los de la web: logo,
/// línea dorada, sello de estado, bloques de datos, tablas con encabezado
/// negro y dorado, cuadro de totales y fecha de generación.
///
/// Se generan en el teléfono (sin servidor) y se comparten con el menú del
/// sistema (WhatsApp, correo, Drive...) o se imprimen.

const _oro = PdfColor.fromInt(0xFFC9A227);
const _oroOscuro = PdfColor.fromInt(0xFF8A6D12);
const _negro = PdfColor.fromInt(0xFF1D1B16);
const _crema = PdfColor.fromInt(0xFFFAF6EA);
const _crema2 = PdfColor.fromInt(0xFFFCFBF8);
const _borde = PdfColor.fromInt(0xFFECE7DC);
const _grisTexto = PdfColor.fromInt(0xFF7A7466);
const _doradoClaro = PdfColor.fromInt(0xFFF4E3A7);

/// Tono del sello de estado.
enum Tono { ok, alerta, malo, neutro }

const _tonos = {
  Tono.ok: (PdfColor.fromInt(0xFFE8F6EE), PdfColor.fromInt(0xFF1D7A46)),
  Tono.alerta: (PdfColor.fromInt(0xFFFDF3DC), PdfColor.fromInt(0xFF8A6200)),
  Tono.malo: (PdfColor.fromInt(0xFFFDE8E8), PdfColor.fromInt(0xFFB42318)),
  Tono.neutro: (PdfColor.fromInt(0xFFF1EFE9), PdfColor.fromInt(0xFF555555)),
};

/// Ícono del logo (el mismo de la web, en dorado sobre negro).
const _logoSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">'
    '<rect x="0" y="0" width="96" height="96" rx="22" fill="#0b1117"/>'
    '<path d="M48 18c14 0 25 11 25 25 0 8-3 15-9 20l-13 10-13-10c-6-5-9-12-9-20 0-14 11-25 25-25zm0 16c-5 0-9 4-9 9s4 9 9 9 9-4 9-9-4-9-9-9zm-20 31h40v7H28v-7zm9 14h22v7H37v-7z" fill="#d6a93b"/>'
    '<circle cx="71" cy="33" r="5" fill="#fef3c7"/></svg>';

/// Una tabla del documento.
class TablaPdf {
  const TablaPdf({this.titulo, required this.columnas, required this.filas, this.numericas = const {}, this.vacio = 'Sin registros.'});
  final String? titulo;
  final List<String> columnas;
  final List<List<String>> filas;

  /// Índices de las columnas que van alineadas a la derecha (dinero, cantidades).
  final Set<int> numericas;
  final String vacio;
}

/// Un bloque "Etiqueta ........ valor".
class BloquePdf {
  const BloquePdf(this.titulo, this.campos);
  final String titulo;
  final List<(String, String?)> campos;
}

pw.Widget _seccion(String texto) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(texto.toUpperCase(), style: pw.TextStyle(fontSize: 8, letterSpacing: 1.5, color: _oroOscuro, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _tabla(TablaPdf t) {
  if (t.filas.isEmpty) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _borde), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Text(t.vacio, textAlign: pw.TextAlign.center, style: const pw.TextStyle(color: _grisTexto)),
    );
  }
  return pw.TableHelper.fromTextArray(
    headers: t.columnas,
    data: t.filas,
    border: null,
    headerStyle: pw.TextStyle(color: _doradoClaro, fontWeight: pw.FontWeight.bold, fontSize: 8, letterSpacing: 0.8),
    headerDecoration: const pw.BoxDecoration(color: _negro),
    cellStyle: const pw.TextStyle(fontSize: 9),
    oddRowDecoration: const pw.BoxDecoration(color: _crema2),
    rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.6))),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    headerAlignments: {for (final i in t.numericas) i: pw.Alignment.centerRight},
    cellAlignments: {for (final i in t.numericas) i: pw.Alignment.centerRight},
  );
}

/// Arma el documento con el formato de la marca.
Future<Uint8List> generarDocumento({
  required String titulo,
  String? codigo,
  String? fechaDoc,
  (String, Tono)? estado,
  String? aviso,
  List<BloquePdf> bloques = const [],
  List<(String, String)> resumen = const [],
  List<TablaPdf> tablas = const [],
  List<(String, String, bool)> totales = const [],
  String? notas,
  String pie = 'Essence Don Aire · Gracias por confiar en nosotros.',
  bool horizontal = false,
}) async {
  final doc = pw.Document(title: [titulo, codigo].whereType<String>().join(' '), author: Config.negocio);
  final generado = fechaHora(DateTime.now());
  final colores = estado == null ? null : _tonos[estado.$2]!;

  doc.addPage(pw.MultiPage(
    pageFormat: horizontal ? PdfPageFormat.letter.landscape : PdfPageFormat.letter,
    margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
    footer: (ctx) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _borde))),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(pie, style: const pw.TextStyle(fontSize: 7, color: _grisTexto))),
        pw.Text('Generado el $generado · Pág. ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: _grisTexto)),
      ]),
    ),
    build: (ctx) => [
      // Encabezado: logo y datos del negocio a la izquierda, documento a la derecha.
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _oro, width: 2.5))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 40, height: 40, child: pw.SvgImage(svg: _logoSvg)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(text: 'ESSENCE ', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5, color: _negro)),
                  pw.TextSpan(text: 'DON AIRE', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5, color: _oroOscuro)),
                ]),
              ),
              pw.Text('Perfumería · ${Config.direccion}', style: const pw.TextStyle(fontSize: 7.5, color: _grisTexto)),
              pw.Text('Tel. ${Config.telefono}', style: const pw.TextStyle(fontSize: 7.5, color: _grisTexto)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(titulo.toUpperCase(), style: const pw.TextStyle(fontSize: 8, letterSpacing: 2, color: _grisTexto)),
            if (codigo != null) pw.Text(codigo, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            if (fechaDoc != null) pw.Text(fechaDoc, style: const pw.TextStyle(fontSize: 9, color: _grisTexto)),
            if (estado != null)
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(color: colores!.$1, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Text(estado.$1.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: colores.$2)),
              ),
          ]),
        ]),
      ),
      if (aviso != null)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFDF1F1), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text(aviso, style: pw.TextStyle(color: const PdfColor.fromInt(0xFFA12A2A), fontWeight: pw.FontWeight.bold)),
        ),
      if (bloques.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (var i = 0; i < bloques.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(color: _crema2, border: pw.Border.all(color: _borde), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(bloques[i].titulo.toUpperCase(),
                      style: pw.TextStyle(fontSize: 7.5, letterSpacing: 1.5, color: _oroOscuro, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  for (final c in bloques[i].campos.where((c) => (c.$2 ?? '').isNotEmpty))
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(c.$1, style: const pw.TextStyle(fontSize: 8.5, color: _grisTexto)),
                        pw.SizedBox(width: 8),
                        pw.Expanded(child: pw.Text(c.$2!, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                      ]),
                    ),
                ]),
              ),
            ),
          ],
        ]),
      ],
      if (resumen.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Row(children: [
          for (var i = 0; i < resumen.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: _crema, border: pw.Border.all(color: const PdfColor.fromInt(0xFFEFE3BF)), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(resumen[i].$1.toUpperCase(), style: const pw.TextStyle(fontSize: 7, letterSpacing: 1, color: _grisTexto)),
                  pw.Text(resumen[i].$2, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ]),
              ),
            ),
          ],
        ]),
      ],
      for (final t in tablas) ...[
        if (t.titulo != null) _seccion(t.titulo!) else pw.SizedBox(height: 12),
        _tabla(t),
      ],
      if (totales.isNotEmpty)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 220,
            margin: const pw.EdgeInsets.only(top: 12),
            child: pw.Column(children: [
              for (final t in totales)
                t.$3
                    ? pw.Container(
                        margin: const pw.EdgeInsets.symmetric(vertical: 4),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: pw.BoxDecoration(color: _negro, borderRadius: pw.BorderRadius.circular(6)),
                        child: pw.Row(children: [
                          pw.Expanded(child: pw.Text(t.$1, style: pw.TextStyle(color: _doradoClaro, fontWeight: pw.FontWeight.bold, fontSize: 12))),
                          pw.Text(t.$2, style: pw.TextStyle(color: _doradoClaro, fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        ]),
                      )
                    : pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                        child: pw.Row(children: [pw.Expanded(child: pw.Text(t.$1)), pw.Text(t.$2)]),
                      ),
            ]),
          ),
        ),
      if ((notas ?? '').isNotEmpty)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 14),
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(color: _crema, border: pw.Border(left: pw.BorderSide(color: _oro, width: 3))),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Notas: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(text: notas),
            ]),
          ),
        ),
    ],
  ));
  return doc.save();
}

Future<void> _compartir(Future<Uint8List> pdf, String archivo) async {
  await Printing.sharePdf(bytes: await pdf, filename: '${archivo.replaceAll(RegExp(r'[^\wÁÉÍÓÚáéíóúÑñ-]+'), '_')}.pdf');
}

String _metodo(String? m) => m == null ? '—' : (nombresMetodo[m] ?? m);

// ---------------------------------------------------------------------------
// Factura de venta
// ---------------------------------------------------------------------------

Future<Uint8List> generarFactura(Venta v) {
  final estado = switch (v.anulada ? 'anulada' : v.estadoPago) {
    'pagada' => ('Pagada', Tono.ok),
    'parcial' => ('Abonada', Tono.alerta),
    'anulada' => ('Anulada', Tono.malo),
    _ => ('Pendiente de pago', Tono.malo),
  };
  final aplicados = v.pagos.where((p) => p.aplicado).toList();
  return generarDocumento(
    titulo: 'Factura de venta',
    codigo: v.numeroFactura,
    fechaDoc: fechaHora(v.fecha),
    estado: estado,
    aviso: v.anulada ? 'Venta ANULADA${v.motivoAnulacion != null ? ' · Motivo: ${v.motivoAnulacion}' : ''}' : null,
    bloques: [
      BloquePdf('Cliente', [
        ('Nombre', v.cliente),
        ('Documento', v.clienteDocumento),
        ('Celular', v.clienteTelefono),
        ('Correo', v.clienteCorreo),
        ('Dirección', [v.clienteDireccion, v.clienteCiudad].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
      ]),
      BloquePdf('Venta', [
        ('Forma de pago', _metodo(v.metodoPago)),
        ('Canal', nombresCanal[v.canal] ?? v.canal),
        ('Pedido', v.pedidoCodigo),
        ('Atendió', v.vendedor),
      ]),
    ],
    tablas: [
      TablaPdf(
        titulo: 'Productos',
        columnas: const ['Producto', 'Ref.', 'Cant.', 'Precio', 'Subtotal'],
        numericas: const {2, 3, 4},
        filas: [for (final i in v.items) [i.nombre, i.sku, '${i.cantidad}', dinero(i.precioUnitario), dinero(i.subtotal)]],
      ),
      if (aplicados.isNotEmpty)
        TablaPdf(
          titulo: 'Pagos recibidos',
          columnas: const ['Fecha', 'Método', 'Referencia', 'Monto'],
          numericas: const {3},
          filas: [for (final p in aplicados) [fechaHora(p.fecha), _metodo(p.metodo), p.referencia ?? '—', dinero(p.monto)]],
        ),
    ],
    totales: [
      ('Subtotal', dinero(v.subtotal), false),
      if (v.descuento > 0) ('Descuento', '- ${dinero(v.descuento)}', false),
      ('Total', dinero(v.total), true),
      ('Pagado', dinero(v.pagado), false),
      ('Saldo', dinero(v.saldo > 0 ? v.saldo : 0), false),
    ],
    notas: v.notas,
    pie: 'Essence Don Aire · Gracias por tu compra. No reemplaza la factura electrónica de la DIAN.',
  );
}

Future<void> compartirFactura(Venta v) => _compartir(generarFactura(v), 'Factura_${v.numeroFactura}');

Future<void> imprimirFactura(Venta v) async {
  await Printing.layoutPdf(name: 'Factura ${v.numeroFactura}', onLayout: (_) => generarFactura(v));
}

// ---------------------------------------------------------------------------
// Pedido
// ---------------------------------------------------------------------------

Future<void> compartirPedidoPdf(Pedido p) {
  final estado = switch (p.estado) {
    'confirmado' => ('Confirmado', Tono.ok),
    'cancelado' => ('Cancelado', Tono.malo),
    _ => ('Pendiente', Tono.alerta),
  };
  return _compartir(
    generarDocumento(
      titulo: 'Pedido',
      codigo: p.codigo,
      fechaDoc: fechaHora(p.fecha),
      estado: estado,
      bloques: [
        BloquePdf('Cliente', [('Nombre', p.cliente), ('Celular', p.clienteTelefono), ('Entrega', p.direccionEntrega ?? p.clienteDireccion)]),
        BloquePdf('Pedido', [
          ('Canal', nombresCanal[p.canal] ?? p.canal),
          ('Forma de pago', _metodo(p.metodoPago)),
          ('Comprobante', p.tieneComprobante ? 'Adjunto' : null),
          ('Venta', p.numeroFactura),
        ]),
      ],
      tablas: [
        TablaPdf(
          titulo: 'Productos',
          columnas: const ['Producto', 'Cant.', 'Precio', 'Subtotal'],
          numericas: const {1, 2, 3},
          filas: [for (final i in p.items) [i.nombre, '${i.cantidad}', dinero(i.precioUnitario), dinero(i.subtotal)]],
        ),
      ],
      totales: [
        ('Unidades', '${p.items.fold<int>(0, (s, i) => s + i.cantidad)}', false),
        ('Total', dinero(p.total), true),
      ],
      notas: p.notas,
      pie: 'Essence Don Aire · El pedido no descuenta inventario hasta convertirse en venta.',
    ),
    'Pedido_${p.codigo}',
  );
}

// ---------------------------------------------------------------------------
// Recibo de un pago
// ---------------------------------------------------------------------------

Future<void> compartirReciboPdf(Pago p) {
  final tono = switch (p.estado) {
    'aplicado' => Tono.ok,
    'pendiente' => Tono.alerta,
    'rechazado' || 'anulado' => Tono.malo,
    _ => Tono.neutro,
  };
  return _compartir(
    generarDocumento(
      titulo: 'Recibo de pago',
      codigo: p.numeroFactura != null ? 'Factura ${p.numeroFactura}' : 'Pago #${p.id}',
      fechaDoc: fechaHora(p.fecha),
      estado: (nombresEstadoPago[p.estado] ?? p.estado, tono),
      bloques: [
        BloquePdf('Pago', [
          ('Cliente', p.cliente),
          ('Método', _metodo(p.metodo)),
          ('Referencia', p.referencia),
          ('Comprobante', p.tieneComprobante ? 'Adjunto' : 'Sin comprobante'),
          ('Nota', p.nota),
          ('Motivo', p.motivoRechazo),
        ]),
      ],
      totales: [('Valor del pago', dinero(p.monto), true)],
      pie: 'Essence Don Aire · Este recibo certifica el pago registrado en el sistema.',
    ),
    'Recibo_${p.numeroFactura ?? p.id}',
  );
}

// ---------------------------------------------------------------------------
// Estado de cuenta de un cliente
// ---------------------------------------------------------------------------

Future<void> compartirEstadoCuentaPdf(Cliente c, Map<String, dynamic> cuenta) {
  final res = cuenta['resumen'] as Map<String, dynamic>;
  final ventas = (cuenta['ventas'] as List).cast<Map<String, dynamic>>();
  final pagos = (cuenta['pagos'] as List).cast<Map<String, dynamic>>();
  final saldo = aNum(res['saldo']);
  return _compartir(
    generarDocumento(
      titulo: 'Estado de cuenta',
      codigo: c.nombre,
      fechaDoc: fecha(DateTime.now()),
      estado: saldo > 0 ? ('Saldo ${dinero(saldo)}', Tono.malo) : ('Al día', Tono.ok),
      bloques: [
        BloquePdf('Cliente', [
          ('Documento', c.documento == null ? null : '${c.tipoDocumento ?? ''} ${c.documento}'.trim()),
          ('Celular', c.telefono),
          ('Correo', c.correo),
          ('Dirección', [c.direccion, c.ciudad, c.departamento].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
        ]),
      ],
      resumen: [
        ('Facturado', dinero(aNum(res['total_facturado']))),
        ('Pagado', dinero(aNum(res['total_pagado']))),
        ('Saldo', dinero(saldo)),
      ],
      tablas: [
        TablaPdf(
          titulo: 'Compras',
          columnas: const ['Factura', 'Fecha', 'Estado', 'Total', 'Pagado', 'Saldo'],
          numericas: const {3, 4, 5},
          vacio: 'Aún no tiene compras.',
          filas: [
            for (final v in ventas)
              [
                '${v['numero_factura']}',
                fecha(aFecha(v['fecha'])),
                v['estado'] == 'anulada' ? 'Anulada' : capitalizar('${v['estado_pago'] ?? ''}'),
                dinero(aNum(v['total'])),
                dinero(aNum(v['pagado'])),
                v['estado'] == 'anulada' ? '—' : dinero(aNum(v['saldo'])),
              ]
          ],
        ),
        TablaPdf(
          titulo: 'Pagos',
          columnas: const ['Fecha', 'Factura', 'Método', 'Estado', 'Monto'],
          numericas: const {4},
          vacio: 'Aún no tiene pagos.',
          filas: [
            for (final p in pagos)
              [
                fecha(aFecha(p['fecha'])),
                '${p['numero_factura'] ?? ''}',
                _metodo(p['metodo'] as String?),
                nombresEstadoPago[p['estado']] ?? '${p['estado']}',
                dinero(aNum(p['monto'])),
              ]
          ],
        ),
      ],
      notas: c.notas,
      pie: 'Essence Don Aire · Estado de cuenta del cliente.',
    ),
    'Estado_de_cuenta_${c.nombre}',
  );
}

// ---------------------------------------------------------------------------
// Reporte de pagos pendientes (cartera)
// ---------------------------------------------------------------------------

Future<void> compartirReportePendientes(Map<String, dynamic> datos) {
  final clientes = (datos['clientes'] as List).cast<Map<String, dynamic>>();
  return _compartir(
    generarDocumento(
      titulo: 'Pagos pendientes',
      codigo: 'Cartera',
      fechaDoc: 'Corte: ${fechaHora(DateTime.now())}',
      resumen: [
        ('Clientes', '${datos['cantidad_clientes']}'),
        ('Ventas con saldo', '${datos['cantidad_ventas']}'),
        ('Total por cobrar', dinero(aNum(datos['total_pendiente']))),
      ],
      tablas: [
        for (final c in clientes)
          TablaPdf(
            titulo: '${c['cliente']}${c['telefono'] != null ? ' · ${c['telefono']}' : ''} — saldo ${dinero(aNum(c['saldo']))}',
            columnas: const ['Factura', 'Fecha', 'Días', 'Total', 'Pagado', 'Saldo'],
            numericas: const {2, 3, 4, 5},
            filas: [
              for (final v in (c['ventas'] as List).cast<Map<String, dynamic>>())
                [
                  '${v['numero_factura']}',
                  fecha(aFecha(v['fecha'])),
                  '${v['dias']}',
                  dinero(aNum(v['total'])),
                  dinero(aNum(v['pagado'])),
                  dinero(aNum(v['saldo'])),
                ]
            ],
          ),
      ],
      pie: 'Essence Don Aire · Reporte de cartera generado desde la app.',
    ),
    'Pagos_pendientes_${fechaApi(DateTime.now())}',
  );
}

// ---------------------------------------------------------------------------
// Compra a proveedor
// ---------------------------------------------------------------------------

Future<void> compartirCompraPdf(Compra c) {
  final estado = c.cancelada
      ? ('Cancelada', Tono.malo)
      : switch (c.estadoPago) {
          'pagada' => ('Pagada', Tono.ok),
          'parcial' => ('Parcial', Tono.alerta),
          _ => ('Pendiente', Tono.malo),
        };
  return _compartir(
    generarDocumento(
      titulo: 'Orden de compra',
      codigo: c.folio,
      fechaDoc: fecha(c.fecha),
      estado: estado,
      aviso: c.cancelada ? 'Compra CANCELADA: el stock que había entrado ya se devolvió.' : null,
      bloques: [
        BloquePdf('Proveedor', [
          ('Nombre', c.proveedor),
          ('Productos', '${c.items.length} línea(s)'),
          ('Unidades', '${c.items.fold<int>(0, (s, i) => s + i.cantidad)}'),
          ('Registró', c.registro),
        ]),
      ],
      resumen: [('Total', dinero(c.total)), ('Pagado', dinero(c.pagado)), ('Saldo', dinero(c.saldo))],
      tablas: [
        TablaPdf(
          titulo: 'Productos',
          columnas: const ['Producto', 'Cant.', 'Costo', 'Subtotal'],
          numericas: const {1, 2, 3},
          filas: [for (final i in c.items) [i.nombre, '${i.cantidad}', dinero(i.costoUnitario), dinero(i.subtotal)]],
        ),
        TablaPdf(
          titulo: 'Abonos al proveedor',
          columnas: const ['Fecha', 'Método', 'Referencia', 'Monto'],
          numericas: const {3},
          vacio: 'Sin abonos registrados.',
          filas: [for (final p in c.pagos) [fechaHora(p.fecha), _metodo(p.metodo), p.referencia ?? '—', dinero(p.monto)]],
        ),
      ],
      totales: [('Total', dinero(c.total), true), ('Saldo pendiente', dinero(c.saldo), false)],
      notas: c.notas,
      pie: 'Essence Don Aire · Orden de compra a proveedor.',
    ),
    'Compra_${c.folio}',
  );
}

// ---------------------------------------------------------------------------
// Ficha de proveedor
// ---------------------------------------------------------------------------

Future<void> compartirProveedorPdf(Proveedor p) => _compartir(
      generarDocumento(
        titulo: 'Ficha de proveedor',
        codigo: p.nombre,
        fechaDoc: fecha(DateTime.now()),
        estado: p.estado ? ('Activo', Tono.ok) : ('Inactivo', Tono.malo),
        bloques: [
          BloquePdf('Datos', [
            ('Tipo de persona', p.tipoPersona == 'juridica' ? 'Persona jurídica' : p.tipoPersona == 'natural' ? 'Persona natural' : null),
            ('Documento', p.documento == null ? null : '${p.tipoDocumento ?? ''} ${p.documento}'.trim()),
            ('Contacto', p.contacto),
            ('Correo', p.email),
            ('Teléfono', p.telefono),
            ('Ubicación', [p.ciudad, p.departamento].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
            ('Proveedor desde', p.fechaAlta == null ? null : fecha(p.fechaAlta)),
          ]),
        ],
        resumen: [
          ('Órdenes de compra', '${p.totalCompras}'),
          ('Total comprado', dinero(p.totalComprado)),
          ('Productos en catálogo', '${p.totalProductos}'),
        ],
        pie: 'Essence Don Aire · Ficha de proveedor.',
      ),
      'Proveedor_${p.nombre}',
    );

// ---------------------------------------------------------------------------
// Resumen (dashboard)
// ---------------------------------------------------------------------------

Future<void> compartirDashboardPdf(Map<String, dynamic> d) {
  final top = (d['mas_vendidos'] as List? ?? []).cast<Map<String, dynamic>>();
  final mio = d['alcance'] == 'mis_ventas';
  return _compartir(
    generarDocumento(
      titulo: mio ? 'Mi resumen de ventas' : 'Resumen del negocio',
      codigo: 'Dashboard',
      fechaDoc: fechaHora(DateTime.now()),
      resumen: [
        ('Ventas de hoy', dinero(aNum(d['ventas_hoy']))),
        ('Ventas del mes', dinero(aNum(d['ventas_mes']))),
        ('Por cobrar', dinero(aNum(d['cartera']))),
      ],
      bloques: [
        BloquePdf('Indicadores', [
          ('Ventas hoy (cantidad)', '${d['cantidad_hoy']}'),
          ('Ventas del mes (cantidad)', '${d['cantidad_mes']}'),
          ('Ventas con saldo', '${d['ventas_con_saldo']}'),
          ('Pedidos pendientes', '${d['pedidos_pendientes']}'),
          ('Productos con stock bajo', '${d['stock_bajo']}'),
          if (!mio) ('Pagos por aprobar', '${d['pagos_por_aprobar']} · ${dinero(aNum(d['monto_por_aprobar']))}'),
          if (!mio) ('Solicitudes de registro', '${d['solicitudes_pendientes']}'),
        ]),
      ],
      tablas: [
        TablaPdf(
          titulo: 'Más vendidos del mes',
          columnas: const ['#', 'Producto', 'Unidades'],
          numericas: const {2},
          vacio: 'Aún no hay ventas este mes.',
          filas: [for (var i = 0; i < top.length; i++) ['${i + 1}', '${top[i]['nombre']}', '${top[i]['unidades']}']],
        ),
      ],
      pie: 'Essence Don Aire · Reporte ejecutivo generado desde la app.',
    ),
    'Resumen_${fechaApi(DateTime.now())}',
  );
}

// ---------------------------------------------------------------------------
// Listados de cualquier módulo
// ---------------------------------------------------------------------------

/// Una columna de un listado en PDF.
class ColumnaPdf<T> {
  const ColumnaPdf(this.titulo, this.valor, {this.dinero = false, this.numero = false});
  final String titulo;
  final Object? Function(T) valor;
  final bool dinero, numero;
}

/// Listado de un módulo en PDF, con el número de registros y la suma de las
/// columnas de dinero (igual que el botón PDF de la web).
Future<void> compartirListadoPdf<T>({required String titulo, required List<T> filas, required List<ColumnaPdf<T>> columnas, String? filtro}) {
  String celda(ColumnaPdf<T> c, T fila) {
    final v = c.valor(fila);
    if (v == null || v == '') return '—';
    if (c.dinero) return dinero(aNum(v));
    if (v is DateTime) return fecha(v);
    if (v is bool) return v ? 'Sí' : 'No';
    return '$v';
  }

  final sumas = [
    for (final c in columnas.where((c) => c.dinero).take(3)) ('${c.titulo} (suma)', dinero(filas.fold<double>(0, (s, f) => s + aNum(c.valor(f))))),
  ];
  return _compartir(
    generarDocumento(
      titulo: 'Listado de $titulo',
      fechaDoc: fecha(DateTime.now()),
      estado: filtro == null ? null : (filtro, Tono.neutro),
      resumen: [('Registros', '${filas.length}'), ...sumas],
      tablas: [
        TablaPdf(
          columnas: [for (final c in columnas) c.titulo],
          numericas: {for (var i = 0; i < columnas.length; i++) if (columnas[i].dinero || columnas[i].numero) i},
          vacio: 'No hay registros con los filtros actuales.',
          filas: [for (final f in filas) [for (final c in columnas) celda(c, f)]],
        ),
      ],
      horizontal: columnas.length > 5,
      pie: 'Essence Don Aire · Listado generado desde la app.',
    ),
    'Listado_${titulo}_${fechaApi(DateTime.now())}',
  );
}
