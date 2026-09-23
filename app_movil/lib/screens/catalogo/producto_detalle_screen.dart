import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../pedidos/pedido_form_screen.dart';
import '../ventas/venta_form_screen.dart';
import 'producto_form_screen.dart';

/// Ficha de un producto del catálogo: foto, precio, stock y acciones.
class ProductoDetalleScreen extends StatefulWidget {
  const ProductoDetalleScreen({super.key, required this.producto});
  final Producto producto;

  @override
  State<ProductoDetalleScreen> createState() => _ProductoDetalleScreenState();
}

class _ProductoDetalleScreenState extends State<ProductoDetalleScreen> {
  late Producto _p = widget.producto;

  @override
  void initState() {
    super.initState();
    Eventos.datos.addListener(_recargar);
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_recargar);
    super.dispose();
  }

  Future<void> _recargar() async {
    try {
      final r = await Api.i.get('/api/productos/${_p.id}');
      if (mounted) setState(() => _p = Producto.desdeJson(r['datos']));
    } catch (_) {/* se queda con los datos que tenía */}
  }

  // -------------------------------------------------------------------------
  // Foto
  // -------------------------------------------------------------------------

  Future<void> _cambiarFoto() async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, 'camara')),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(ctx, 'galeria')),
          if (_p.imagenUrl != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: rojo),
              title: const Text('Quitar foto', style: TextStyle(color: rojo)),
              onTap: () => Navigator.pop(ctx, 'quitar'),
            ),
        ]),
      ),
    );
    if (opcion == null || !mounted) return;

    if (opcion == 'quitar') {
      await conCarga(context, Api.i.delete('/api/productos/${_p.id}/imagen'));
      return;
    }

    // La foto se reduce y comprime en el teléfono antes de subirla: una foto
    // de cámara pesa varios MB; así queda en ~100 KB y carga rápido.
    final XFile? foto;
    try {
      foto = await ImagePicker().pickImage(
        source: opcion == 'camara' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 72,
      );
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudo abrir la ${opcion == 'camara' ? 'cámara' : 'galería'}: $e', error: true);
      return;
    }
    if (foto == null || !mounted) return;

    final bytes = await foto.readAsBytes();
    final nombre = foto.name.toLowerCase();
    final tipo = nombre.endsWith('.png')
        ? 'image/png'
        : nombre.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    if (!mounted) return;
    final r = await conCarga(context, Api.i.put('/api/productos/${_p.id}/imagen', {'base64': base64Encode(bytes), 'tipo_mime': tipo}));
    if (r != null && mounted) mostrarMensaje(context, 'Foto actualizada.');
  }

  // -------------------------------------------------------------------------
  // Stock
  // -------------------------------------------------------------------------

  /// Ingreso rápido de mercancía: suma unidades al stock sin abrir el
  /// formulario completo.
  Future<void> _ingresarStock() async {
    final control = TextEditingController();
    final cantidad = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ingreso de mercancía'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Stock actual: ${_p.stock} unidades'),
          const SizedBox(height: 12),
          TextField(
            controller: control,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Unidades que llegaron'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(control.text)), child: const Text('Sumar')),
        ],
      ),
    );
    if (cantidad == null || cantidad <= 0 || !mounted) return;
    final r = await conCarga(context, Api.i.put('/api/productos/${_p.id}', {'stock': _p.stock + cantidad}));
    if (r != null && mounted) mostrarMensaje(context, 'Stock actualizado: ${_p.stock + cantidad} unidades.');
  }

  Future<void> _cambiarEstado() async {
    final ok = await confirmar(
      context,
      titulo: _p.estado ? 'Desactivar producto' : 'Activar producto',
      mensaje: _p.estado ? '${_p.nombre} dejará de aparecer para vender.' : '${_p.nombre} volverá a estar a la venta.',
      textoOk: _p.estado ? 'Desactivar' : 'Activar',
      peligro: _p.estado,
    );
    if (!ok || !mounted) return;
    await conCarga(context, Api.i.put('/api/productos/${_p.id}', {'estado': !_p.estado}));
  }

  void _compartir() {
    final texto = StringBuffer()
      ..writeln('*${_p.nombre}*')
      ..writeln(_p.descripcion ?? _p.categoria)
      ..writeln('Precio: ${dinero(_p.precio)}')
      ..writeln(_p.stock > 0 ? 'Disponible ✅' : 'Agotado por ahora');
    if (_p.imagenUrl != null) texto.writeln(_p.imagenUrl);
    texto.writeln('\nEssence Don Aire · La Pintada');
    abrirWhatsApp(null, texto.toString());
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final admin = Sesion.i.esAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.nombre),
        actions: [
          IconButton(tooltip: 'Compartir por WhatsApp', icon: const Icon(Icons.share), onPressed: _compartir),
          // Editar el catálogo es del Administrador.
          if (admin)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductoFormScreen(producto: _p))),
            ),
          if (admin)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'estado' ? _cambiarEstado() : null,
              itemBuilder: (_) => [PopupMenuItem(value: 'estado', child: Text(_p.estado ? 'Desactivar' : 'Activar'))],
            ),
        ],
      ),
      bottomNavigationBar: !_p.vendible
          ? null
          : Sesion.i.esCliente
              // El cliente no vende: pide.
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoFormScreen(productoInicial: _p))),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Pedir este producto'),
                    ),
                  ),
                )
              : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedidoFormScreen(productoInicial: _p))),
                      icon: const Icon(Icons.add_task),
                      label: const Text('Pedido'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VentaFormScreen(productoInicial: _p))),
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Vender'),
                    ),
                  ),
                ]),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          Stack(children: [
            AspectRatio(aspectRatio: 1.3, child: ProductoImagen(_p, tam: null, radio: 0)),
            if (admin)
              Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.tonalIcon(
                onPressed: _cambiarFoto,
                icon: const Icon(Icons.photo_camera),
                label: Text(_p.imagenUrl == null ? 'Agregar foto' : 'Cambiar foto'),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_p.nombre, style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('${_p.categoria} · ${_p.sku}', style: TextStyle(color: tema.colorScheme.outline)),
              const SizedBox(height: 12),
              Row(children: [
                Text(dinero(_p.precio), style: tema.textTheme.headlineSmall?.copyWith(color: tema.colorScheme.primary, fontWeight: FontWeight.w700)),
                const Spacer(),
                etiquetaStock(_p),
              ]),
              if (_p.descripcion != null && _p.descripcion!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_p.descripcion!, style: tema.textTheme.bodyLarge),
              ],
            ]),
          ),
          if (Sesion.i.esEquipo)
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${_p.stock} unidades en stock'),
                subtitle: Text('Mínimo: ${_p.stockMinimo}${_p.stockBajo ? ' · ¡Hay que reponer!' : ''}'),
                trailing: admin ? FilledButton.tonal(onPressed: _ingresarStock, child: const Text('+ Ingreso')) : null,
              ),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.local_shipping_outlined), title: Text(_p.proveedor), subtitle: const Text('Proveedor')),
              ListTile(leading: const Icon(Icons.category_outlined), title: Text(_p.categoria), subtitle: const Text('Categoría')),
            ]),
          ),
        ]),
      ),
    );
  }
}
