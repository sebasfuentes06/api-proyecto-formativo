import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formato.dart';
import '../models/modelos.dart';
import 'comunes.dart';
import 'selectores.dart';

/// Editor de productos de un pedido o una venta: agregar, cambiar cantidad,
/// ajustar precio y quitar. Compartido por los dos formularios.
class EditorCarrito extends StatelessWidget {
  const EditorCarrito({super.key, required this.lineas, required this.onCambio});

  final List<LineaCarrito> lineas;
  final VoidCallback onCambio;

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
                    onTap: () => _editarPrecio(context, l),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(dinero(l.precio),
                            style: TextStyle(
                              color: l.precio != l.producto.precio ? ambar : tema.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(width: 4),
                        Icon(Icons.edit, size: 14, color: tema.colorScheme.outline),
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
  int? monto;
  String metodo = 'efectivo';
  String referencia = '';

  Map<String, dynamic> aJson() => {
        'monto': monto,
        'metodo': metodo,
        if (referencia.trim().isNotEmpty) 'referencia': referencia.trim(),
      };
}

/// Campos de un pago: monto (con botón "todo"), método y referencia.
/// Se usa para el pago inicial de una venta y para registrar abonos.
class CamposPago extends StatefulWidget {
  const CamposPago({super.key, required this.datos, required this.maximo, this.obligatorio = true});
  final DatosPago datos;
  final double maximo;
  final bool obligatorio;

  @override
  State<CamposPago> createState() => _CamposPagoState();
}

class _CamposPagoState extends State<CamposPago> {
  late final TextEditingController _monto = TextEditingController(text: widget.datos.monto?.toString() ?? '');

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
          for (final m in ['efectivo', 'transferencia', 'nequi', 'daviplata', 'tarjeta'])
            DropdownMenuItem(value: m, child: Text(nombresMetodo[m]!)),
        ],
        onChanged: (v) => setState(() => widget.datos.metodo = v ?? 'efectivo'),
      ),
      if (necesitaReferencia) ...[
        const SizedBox(height: 14),
        TextFormField(
          initialValue: widget.datos.referencia,
          decoration: const InputDecoration(labelText: 'Referencia / comprobante (opcional)'),
          onChanged: (v) => widget.datos.referencia = v,
        ),
      ],
    ]);
  }
}
