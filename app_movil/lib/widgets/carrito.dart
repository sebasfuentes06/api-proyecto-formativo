import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/formato.dart';
import '../models/modelos.dart';
import 'comunes.dart';
import 'selectores.dart';

/// Editor de productos de un pedido o una venta: agregar, cambiar cantidad,
/// ajustar precio y quitar. Compartido por los dos formularios.
class EditorCarrito extends StatelessWidget {
  const EditorCarrito({super.key, required this.lineas, required this.onCambio, this.editarPrecio = true});

  final List<LineaCarrito> lineas;
  final VoidCallback onCambio;

  /// El equipo puede dar precio especial; el cliente no.
  final bool editarPrecio;

  double get total => lineas.fold(0, (s, l) => s + l.subtotal);

  Future<void> _agregar(BuildContext context) async {
    final p = await elegirProducto(context);
    if (p == null) return;
    final i = lineas.indexWhere((l) => l.producto.id == p.id);
    if (i >= 0) {
      if (lineas[i].cantidad < p.stock) lineas[i].cantidad++;
    } else {
      lineas.add(LineaCarrito(p));
    }
    onCambio();
  }

  Future<void> _editarPrecio(BuildContext context, LineaCarrito l) async {
    final control = TextEditingController(text: l.precio.round().toString());
    final nuevo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Precio de ${l.producto.nombre}'),
        content: TextField(
          controller: control,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(prefixText: '\$ ', helperText: 'Precio de catálogo: ${dinero(l.producto.precio)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, leerDinero(control.text)), child: const Text('Aplicar')),
        ],
      ),
    );
    if (nuevo != null) {
      l.precio = nuevo.toDouble();
      onCambio();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (lineas.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text('Aún no hay productos.', textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.outline)),
        ),
      for (final l in lineas)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ProductoImagen(l.producto, tam: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.producto.nombre, style: tema.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  InkWell(
                    onTap: editarPrecio ? () => _editarPrecio(context, l) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(dinero(l.precio),
                            style: TextStyle(
                              color: l.precio != l.producto.precio ? ambar : tema.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                        if (editarPrecio) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 14, color: tema.colorScheme.outline),
                        ],
                      ]),
                    ),
                  ),
                  Text('Disponibles: ${l.producto.stock}', style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.outlined(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(l.cantidad == 1 ? Icons.delete_outline : Icons.remove, size: 18),
                    onPressed: () {
                      if (l.cantidad == 1) {
                        lineas.remove(l);
                      } else {
                        l.cantidad--;
                      }
                      onCambio();
                    },
                  ),
                  SizedBox(width: 30, child: Text('${l.cantidad}', textAlign: TextAlign.center, style: tema.textTheme.titleMedium)),
                  IconButton.outlined(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 18),
                    // No deja pedir más de lo que hay: la API igual lo rechazaría.
                    onPressed: l.cantidad >= l.producto.stock
                        ? null
                        : () {
                            l.cantidad++;
                            onCambio();
                          },
                  ),
                ]),
                Text(dinero(l.subtotal), style: tema.textTheme.titleSmall),
              ]),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: OutlinedButton.icon(
          onPressed: () => _agregar(context),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Agregar producto'),
        ),
      ),
    ]);
  }
}

/// Datos de un pago o abono que se está capturando.
class DatosPago {
  DatosPago({this.metodo = 'efectivo'});
  int? monto;
  String metodo;
  String referencia = '';

  /// Foto del comprobante (captura de la transferencia, recibo...).
  Uint8List? comprobante;
  String comprobanteMime = 'image/jpeg';

  Map<String, dynamic> aJson() => {
        'monto': monto,
        'metodo': metodo,
        if (referencia.trim().isNotEmpty) 'referencia': referencia.trim(),
        if (comprobante != null) 'comprobante': {'base64': base64Encode(comprobante!), 'tipo_mime': comprobanteMime},
      };
}

/// Toma o elige una foto y la comprime en el teléfono (~100-200 KB).
/// Devuelve null si la persona cancela.
Future<({Uint8List bytes, String mime})?> elegirFoto(BuildContext context, {String titulo = 'Comprobante'}) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600))),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Elegir de la galería (capturas)'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
      ]),
    ),
  );
  if (origen == null) return null;
  try {
    final foto = await ImagePicker().pickImage(source: origen, maxWidth: 1400, maxHeight: 1400, imageQuality: 70);
    if (foto == null) return null;
    final bytes = await foto.readAsBytes();
    final n = foto.name.toLowerCase();
    final mime = n.endsWith('.png') ? 'image/png' : n.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    if (bytes.length > 1400 * 1024) {
      if (context.mounted) mostrarMensaje(context, 'La imagen pesa demasiado. Toma una captura más pequeña.', error: true);
      return null;
    }
    return (bytes: bytes, mime: mime);
  } catch (e) {
    if (context.mounted) mostrarMensaje(context, 'No se pudo abrir la imagen: $e', error: true);
    return null;
  }
}

/// Botón para adjuntar el comprobante, con miniatura cuando ya hay uno.
class CampoComprobante extends StatelessWidget {
  const CampoComprobante({super.key, required this.datos, required this.onCambio, this.obligatorio = false});
  final DatosPago datos;
  final VoidCallback onCambio;
  final bool obligatorio;

  @override
  Widget build(BuildContext context) {
    final c = datos.comprobante;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: c == null
            ? const Icon(Icons.receipt_long_outlined)
            : ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(c, width: 48, height: 48, fit: BoxFit.cover)),
        title: Text(c == null ? 'Adjuntar comprobante${obligatorio ? '' : ' (opcional)'}' : 'Comprobante adjunto'),
        subtitle: Text(c == null ? 'Foto o captura de la transferencia' : '${(c.length / 1024).round()} KB · toca para cambiarlo'),
        trailing: c == null
            ? const Icon(Icons.add_a_photo_outlined)
            : IconButton(
                tooltip: 'Quitar',
                icon: const Icon(Icons.close),
                onPressed: () {
                  datos.comprobante = null;
                  onCambio();
                },
              ),
        onTap: () async {
          final f = await elegirFoto(context);
          if (f == null) return;
          datos.comprobante = f.bytes;
          datos.comprobanteMime = f.mime;
          onCambio();
        },
      ),
    );
  }
}

/// Campos de un pago: monto (con botón "todo"), método, referencia y
/// comprobante. Se usa para el pago inicial de una venta, para registrar
/// abonos y para que el cliente reporte sus pagos.
class CamposPago extends StatefulWidget {
  const CamposPago({
    super.key,
    required this.datos,
    required this.maximo,
    this.obligatorio = true,
    this.metodos = const ['efectivo', 'transferencia', 'nequi', 'daviplata', 'tarjeta'],
    this.pedirComprobante = true,
  });
  final DatosPago datos;
  final double maximo;
  final bool obligatorio;
  final List<String> metodos;
  final bool pedirComprobante;

  @override
  State<CamposPago> createState() => _CamposPagoState();
}

class _CamposPagoState extends State<CamposPago> {
  late final TextEditingController _monto = TextEditingController(text: widget.datos.monto?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    if (!widget.metodos.contains(widget.datos.metodo)) widget.datos.metodo = widget.metodos.first;
  }

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final necesitaReferencia = widget.datos.metodo != 'efectivo';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: _monto,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Monto',
          prefixText: '\$ ',
          helperText: 'Máximo ${dinero(widget.maximo)}',
          suffixIcon: TextButton(
            onPressed: () {
              _monto.text = widget.maximo.round().toString();
              widget.datos.monto = widget.maximo.round();
              setState(() {});
            },
            child: const Text('Todo'),
          ),
        ),
        onChanged: (v) => widget.datos.monto = leerDinero(v),
        validator: (v) {
          final n = leerDinero(v ?? '');
          if (n == null || n == 0) return widget.obligatorio ? 'Escribe el monto' : null;
          if (n > widget.maximo.round()) return 'No puede superar ${dinero(widget.maximo)}';
          return null;
        },
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: widget.datos.metodo,
        decoration: const InputDecoration(labelText: 'Método de pago'),
        items: [
          for (final m in widget.metodos) DropdownMenuItem(value: m, child: Text(nombresMetodo[m]!)),
        ],
        onChanged: (v) => setState(() => widget.datos.metodo = v ?? widget.metodos.first),
      ),
      if (necesitaReferencia) ...[
        const SizedBox(height: 14),
        TextFormField(
          initialValue: widget.datos.referencia,
          decoration: const InputDecoration(labelText: 'Referencia / número de la transacción (opcional)'),
          onChanged: (v) => widget.datos.referencia = v,
        ),
        if (widget.pedirComprobante) ...[
          const SizedBox(height: 10),
          CampoComprobante(datos: widget.datos, onCambio: () => setState(() {})),
        ],
      ],
    ]);
  }
}

IconData iconoMetodo(String m) => switch (m) {
      'efectivo' => Icons.payments_outlined,
      'transferencia' => Icons.account_balance_outlined,
      'nequi' || 'daviplata' => Icons.phone_android,
      'tarjeta' => Icons.credit_card,
      'wompi' => Icons.language,
      _ => Icons.attach_money,
    };

/// Botones para escoger el método de pago (obligatorio en ventas y pedidos).
class SelectorMetodo extends FormField<String> {
  SelectorMetodo({
    super.key,
    required String? valor,
    required ValueChanged<String> onCambio,
    List<String> opciones = metodosVenta,
    Map<String, String>? etiquetas,
  }) : super(
          initialValue: valor,
          validator: (v) => v == null ? 'Elige el método de pago' : null,
          builder: (campo) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in opciones)
                ChoiceChip(
                  avatar: Icon(iconoMetodo(m), size: 18),
                  label: Text(etiquetas?[m] ?? nombresMetodo[m] ?? m),
                  selected: campo.value == m,
                  onSelected: (_) {
                    campo.didChange(m);
                    onCambio(m);
                  },
                ),
            ]),
            if (campo.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(campo.errorText!, style: TextStyle(color: Theme.of(campo.context).colorScheme.error, fontSize: 12)),
              ),
          ]),
        );
}
