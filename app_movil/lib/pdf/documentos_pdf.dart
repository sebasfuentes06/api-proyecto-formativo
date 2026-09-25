import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/config.dart';
import '../core/formato.dart';
import '../models/modelos.dart';

/// Documentos PDF de la app: factura de venta, estado de cuenta y reporte de
/// pagos pendientes. Se generan en el teléfono (sin servidor) y se comparten
/// con el menú del sistema (WhatsApp, correo, Drive...) o se imprimen.

const _marca = PdfColor.fromInt(0xFF7A2E55);
const _grisClaro = PdfColor.fromInt(0xFFF3EDF1);

pw.Widget _encabezado(String titulo, String subtitulo) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _marca, width: 2))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(Config.negocio, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _marca)),
            pw.Text('Lociones y fragancias', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(Config.direccion, style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Tel. ${Config.telefono}', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(titulo, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitulo, style: const pw.TextStyle(fontSize: 10)),
        ]),
      ]),
    );

pw.Widget _fila(String etiqueta, String valor, {bool negrita = false, PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.SizedBox(width: 120, child: pw.Text(etiqueta, style: pw.TextStyle(fontWeight: negrita ? pw.FontWeight.bold : null))),
        pw.SizedBox(
          width: 100,
          child: pw.Text(valor,
              textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: negrita ? pw.FontWeight.bold : null, color: color)),
        ),
      ]),
    );

pw.Widget _pie(String texto) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 24),
      child: pw.Text(texto, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
    );

// ---------------------------------------------------------------------------
// Factura
// ---------------------------------------------------------------------------

Future<Uint8List> generarFactura(Venta v) async {
  final doc = pw.Document(title: 'Factura ${v.numeroFactura}', author: Config.negocio);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) => [
      _encabezado('FACTURA DE VENTA', 'No. ${v.numeroFactura}'),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 9, color: _marca, fontWeight: pw.FontWeight.bold)),
            pw.Text(v.cliente, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if ((v.clienteDocumento ?? '').isNotEmpty) pw.Text('Doc. ${v.clienteDocumento}'),
            if ((v.clienteTelefono ?? '').isNotEmpty) pw.Text('Tel. ${v.clienteTelefono}'),
            if ((v.clienteDireccion ?? '').isNotEmpty)
              pw.Text([v.clienteDireccion, v.clienteCiudad].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Fecha: ${fechaHora(v.fecha)}'),
          pw.Text('Canal: ${nombresCanal[v.canal] ?? v.canal}'),
          if (v.metodoPago != null) pw.Text('Forma de pago: ${nombresMetodo[v.metodoPago] ?? v.metodoPago}'),
          if (v.pedidoCodigo != null) pw.Text('Pedido: ${v.pedidoCodigo}'),
          if (v.vendedor != null) pw.Text('Atendió: ${v.vendedor}'),
        ]),
      ]),
      if (v.anulada)
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.all(8),
          color: PdfColors.red50,
          child: pw.Text('VENTA ANULADA${v.motivoAnulacion != null ? ': ${v.motivoAnulacion}' : ''}',
              style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold)),
        ),
      pw.SizedBox(height: 16),
      pw.TableHelper.fromTextArray(
        headers: ['Producto', 'Ref.', 'Cant.', 'Precio', 'Subtotal'],
        data: [for (final i in v.items) [i.nombre, i.sku, '${i.cantidad}', dinero(i.precioUnitario), dinero(i.subtotal)]],
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: _marca),
        oddRowDecoration: const pw.BoxDecoration(color: _grisClaro),
        cellAlignments: {2: pw.Alignment.center, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(2), 4: const pw.FlexColumnWidth(2)},
      ),
      pw.SizedBox(height: 10),
      _fila('Subtotal', dinero(v.subtotal)),
      if (v.descuento > 0) _fila('Descuento', '- ${dinero(v.descuento)}'),
      _fila('TOTAL', dinero(v.total), negrita: true),
      if (!v.anulada) ...[
        _fila('Pagado', dinero(v.pagado), color: PdfColors.green800),
        _fila('Saldo pendiente', dinero(v.saldo > 0 ? v.saldo : 0), negrita: true, color: v.saldo > 0 ? PdfColors.red800 : PdfColors.green800),
      ],
      if (v.pagos.where((p) => p.aplicado).isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('PAGOS RECIBIDOS', style: pw.TextStyle(fontSize: 9, color: _marca, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        for (final p in v.pagos.where((p) => p.aplicado))
          pw.Text('${fechaHora(p.fecha)}  ·  ${nombresMetodo[p.metodo] ?? p.metodo}  ·  ${dinero(p.monto)}'
              '${p.referencia != null ? '  ·  Ref. ${p.referencia}' : ''}'),
      ],
      _pie('Gracias por tu compra.\nDocumento generado por la app de ${Config.negocio}. No reemplaza la factura electrónica de la DIAN.'),
    ],
  ));
  return doc.save();
}

Future<void> compartirFactura(Venta v) async {
  final bytes = await generarFactura(v);
  await Printing.sharePdf(bytes: bytes, filename: 'Factura_${v.numeroFactura}.pdf');
}

Future<void> imprimirFactura(Venta v) async {
  await Printing.layoutPdf(name: 'Factura ${v.numeroFactura}', onLayout: (_) => generarFactura(v));
}

// ---------------------------------------------------------------------------
// Estado de cuenta de un cliente
// ---------------------------------------------------------------------------

Future<void> compartirEstadoCuentaPdf(Cliente c, Map<String, dynamic> cuenta) async {
  final res = cuenta['resumen'] as Map<String, dynamic>;
  final ventas = (cuenta['ventas'] as List).cast<Map<String, dynamic>>();
  final pagos = (cuenta['pagos'] as List).cast<Map<String, dynamic>>().where((p) => p['estado'] == 'aplicado').toList();
  final doc = pw.Document(title: 'Estado de cuenta ${c.nombre}');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) => [
      _encabezado('ESTADO DE CUENTA', fecha(DateTime.now())),
      pw.SizedBox(height: 12),
      pw.Text(c.nombre, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (c.telefono != null) pw.Text('Tel. ${c.telefono}'),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Factura', 'Fecha', 'Total', 'Pagado', 'Saldo'],
        data: [
          for (final v in ventas)
            [v['numero_factura'], fecha(aFecha(v['fecha'])), dinero(aNum(v['total'])), dinero(aNum(v['pagado'])), dinero(aNum(v['saldo']))]
        ],
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: _marca),
        oddRowDecoration: const pw.BoxDecoration(color: _grisClaro),
        cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
      ),
      pw.SizedBox(height: 10),
      _fila('Total facturado', dinero(aNum(res['total_facturado']))),
      _fila('Total pagado', dinero(aNum(res['total_pagado']))),
      _fila('SALDO PENDIENTE', dinero(aNum(res['saldo'])), negrita: true, color: PdfColors.red800),
      if (pagos.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('ÚLTIMOS PAGOS', style: pw.TextStyle(fontSize: 9, color: _marca, fontWeight: pw.FontWeight.bold)),
        for (final p in pagos.take(15))
          pw.Text('${fecha(aFecha(p['fecha']))}  ·  ${p['numero_factura']}  ·  ${nombresMetodo[p['metodo']] ?? p['metodo']}  ·  ${dinero(aNum(p['monto']))}'),
      ],
      _pie('${Config.negocio} · ${Config.telefono}'),
    ],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'Estado_de_cuenta_${c.nombre.replaceAll(' ', '_')}.pdf');
}

// ---------------------------------------------------------------------------
// Reporte de pagos pendientes (cartera)
// ---------------------------------------------------------------------------

Future<void> compartirReportePendientes(Map<String, dynamic> datos) async {
  final clientes = (datos['clientes'] as List).cast<Map<String, dynamic>>();
  final doc = pw.Document(title: 'Reporte de pagos pendientes');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) => [
      _encabezado('PAGOS PENDIENTES', 'Corte: ${fechaHora(DateTime.now())}'),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pw.Expanded(child: pw.Text('${datos['cantidad_clientes']} cliente(s) · ${datos['cantidad_ventas']} venta(s)')),
        pw.Text('Total: ${dinero(aNum(datos['total_pendiente']))}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
      ]),
      pw.SizedBox(height: 12),
      for (final c in clientes) ...[
        pw.Container(
          color: _grisClaro,
          padding: const pw.EdgeInsets.all(6),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text('${c['cliente']}  ${c['telefono'] != null ? '(${c['telefono']})' : ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Text(dinero(aNum(c['saldo'])), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.TableHelper.fromTextArray(
          headers: ['Factura', 'Fecha', 'Días', 'Total', 'Pagado', 'Saldo'],
          data: [
            for (final v in (c['ventas'] as List).cast<Map<String, dynamic>>())
              [v['numero_factura'], fecha(aFecha(v['fecha'])), '${v['dias']}', dinero(aNum(v['total'])), dinero(aNum(v['pagado'])), dinero(aNum(v['saldo']))]
          ],
          border: null,
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {2: pw.Alignment.center, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 8),
      ],
      _pie('Reporte generado desde la app de ${Config.negocio}.'),
    ],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: 'Pagos_pendientes_${fechaApi(DateTime.now())}.pdf');
}
