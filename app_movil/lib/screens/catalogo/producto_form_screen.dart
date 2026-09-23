import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';

/// Crear o editar un producto del catálogo.
class ProductoFormScreen extends StatefulWidget {
  const ProductoFormScreen({super.key, this.producto});
  final Producto? producto;

  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _sku = TextEditingController(text: widget.producto?.sku);
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _descripcion = TextEditingController(text: widget.producto?.descripcion);
  late final _precio = TextEditingController(text: widget.producto?.precio.round().toString());
  late final _stock = TextEditingController(text: widget.producto?.stock.toString() ?? '0');
  late final _minimo = TextEditingController(text: widget.producto?.stockMinimo.toString() ?? '3');
  late int? _categoria = widget.producto?.idCategoria;
  late int? _proveedor = widget.producto?.idProveedor;

  List<Categoria>? _categorias;
  List<Proveedor>? _proveedores;
  Object? _error;

  bool get _editando => widget.producto != null;

  @override
  void initState() {
    super.initState();
    _cargarListas();
  }

  @override
  void dispose() {
    for (final c in [_sku, _nombre, _descripcion, _precio, _stock, _minimo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarListas() async {
    try {
      final r = await Future.wait([
        Api.i.pagina('/api/categorias', Categoria.desdeJson, query: {'limit': 100, 'sortBy': 'nombre'}),
        Api.i.pagina('/api/proveedores', Proveedor.desdeJson, query: {'limit': 100, 'sortBy': 'nombre'}),
      ]);
      if (!mounted) return;
      setState(() {
        // Se muestran las activas y, si se está editando, la que ya tenía
        // aunque esté inactiva (si no, el desplegable quedaría sin valor).
        _categorias = (r[0].items as List<Categoria>).where((c) => c.estado || c.id == _categoria).toList();
        _proveedores = (r[1].items as List<Proveedor>).where((p) => p.estado || p.id == _proveedor).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final datos = {
      'sku': _sku.text.trim(),
      'nombre': _nombre.text.trim(),
      'descripcion': _descripcion.text.trim(),
      'id_categoria': _categoria,
      'id_proveedor': _proveedor,
      'precio': leerDinero(_precio.text) ?? 0,
      'stock': int.tryParse(_stock.text) ?? 0,
      'stock_minimo': int.tryParse(_minimo.text) ?? 0,
    };
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/productos/${widget.producto!.id}', datos) : Api.i.post('/api/productos', datos),
    );
    if (r == null || !mounted) return;
    mostrarMensaje(context, _editando ? 'Producto actualizado.' : 'Producto creado. Agrégale una foto desde su ficha.');
    Navigator.pop(context, Producto.desdeJson(r['datos']));
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    final Widget cuerpo;
    if (_error != null) {
      cuerpo = ErrorReintentar(error: _error!, onReintentar: _cargarListas);
    } else if (_categorias == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      cuerpo = Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre *'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
          ),
          espacio,
          TextFormField(
            controller: _sku,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'SKU / referencia *', helperText: 'Código único. Ej: NAT-ESS-010'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
          ),
          espacio,
          DropdownButtonFormField<int>(
            value: _categoria,
            decoration: const InputDecoration(labelText: 'Categoría *'),
            items: [for (final c in _categorias!) DropdownMenuItem(value: c.id, child: Text(c.nombre))],
            onChanged: (v) => setState(() => _categoria = v),
            validator: (v) => v == null ? 'Elige una categoría' : null,
          ),
          espacio,
          DropdownButtonFormField<int>(
            value: _proveedor,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Proveedor / marca *'),
            items: [for (final p in _proveedores!) DropdownMenuItem(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _proveedor = v),
            validator: (v) => v == null ? 'Elige un proveedor' : null,
          ),
          espacio,
          TextFormField(
            controller: _precio,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Precio de venta *', prefixText: '\$ '),
            validator: (v) => (leerDinero(v ?? '') ?? 0) <= 0 ? 'Escribe el precio' : null,
          ),
          espacio,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _stock,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Stock'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _minimo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Stock mínimo', helperText: 'Avisa al llegar aquí'),
              ),
            ),
          ]),
          espacio,
          TextFormField(
            controller: _descripcion,
            maxLines: 3,
            maxLength: 250,
            decoration: const InputDecoration(labelText: 'Descripción (notas olfativas, tamaño...)'),
          ),
          FilledButton.icon(
            onPressed: _guardar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.save),
            label: Text(_editando ? 'Guardar cambios' : 'Crear producto'),
          ),
        ]),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(_editando ? 'Editar producto' : 'Nuevo producto')), body: cuerpo);
  }
}
