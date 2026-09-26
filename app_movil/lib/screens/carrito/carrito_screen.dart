import 'package:flutter/material.dart';

import '../../core/carrito.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../pedidos/pedido_form_screen.dart';

/// Carrito del Cliente: ícono con el número de productos, barra que queda
/// visible en todas las pestañas y la pantalla para revisar y hacer el pedido.

void abrirCarrito(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CarritoScreen()));

/// Agrega un producto y avisa, con atajo para ir al carrito.
void agregarAlCarrito(BuildContext context, Producto p, {int cantidad = 1}) {
  final ok = Carrito.i.agregar(p, cantidad: cantidad);
  final mensajero = ScaffoldMessenger.of(context);
  mensajero.hideCurrentSnackBar();
  mensajero.showSnackBar(SnackBar(
    content: Text(ok ? '${p.nombre} agregado al carrito' : 'Solo hay ${p.stock} unidad(es) de ${p.nombre}.'),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    action: ok ? SnackBarAction(label: 'Ver carrito', onPressed: () => abrirCarrito(context)) : null,
  ));
}

/// Ícono del carrito con el número de unidades (solo para el Cliente).
class BotonCarrito extends StatelessWidget {
  const BotonCarrito({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Sesion.i.esCliente) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Carrito.i,
      builder: (_, __) => IconButton(
        tooltip: 'Carrito',
        onPressed: () => abrirCarrito(context),
        icon: Badge(
          isLabelVisible: !Carrito.i.vacio,
          label: Text('${Carrito.i.unidades}'),
          child: const Icon(Icons.shopping_cart_outlined),
        ),
      ),
    );
  }
}

/// Barra que aparece encima de las pestañas cuando hay algo en el carrito.
/// Como vive en la pantalla principal, se ve en cualquier pestaña.
class BarraCarrito extends StatelessWidget {
  const BarraCarrito({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListenableBuilder(
      listenable: Carrito.i,
      builder: (_, __) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Carrito.i.vacio
            ? const SizedBox(width: double.infinity)
            : Material(
                color: tema.colorScheme.primary,
                child: InkWell(
                  onTap: () => abrirCarrito(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Badge(
                        label: Text('${Carrito.i.unidades}'),
                        backgroundColor: tema.colorScheme.onPrimary,
                        textColor: tema.colorScheme.primary,
                        child: Icon(Icons.shopping_cart, color: tema.colorScheme.onPrimary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${Carrito.i.unidades} producto${Carrito.i.unidades == 1 ? '' : 's'} · ${dinero(Carrito.i.total)}',
                          style: TextStyle(color: tema.colorScheme.onPrimary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('Ver carrito', style: TextStyle(color: tema.colorScheme.onPrimary)),
                      Icon(Icons.chevron_right, color: tema.colorScheme.onPrimary),
                    ]),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Revisar el carrito, cambiar cantidades y hacer el pedido.
class CarritoScreen extends StatelessWidget {
  const CarritoScreen({super.key});

  Future<void> _vaciar(BuildContext context) async {
    final ok = await confirmar(context, titulo: 'Vaciar carrito', mensaje: '¿Quitar todos los productos?', textoOk: 'Vaciar');
    if (ok) Carrito.i.vaciar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListenableBuilder(
      listenable: Carrito.i,
      builder: (context, _) {
        final c = Carrito.i;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mi carrito'),
            actions: [
              if (!c.vacio) IconButton(tooltip: 'Vaciar', icon: const Icon(Icons.delete_sweep_outlined), onPressed: () => _vaciar(context)),
            ],
          ),
          bottomNavigationBar: c.vacio
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Total', style: tema.textTheme.bodySmall),
                          Text(dinero(c.total), style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Hacer pedido'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PedidoFormScreen(desdeCarrito: true)),
                        ),
                      ),
                    ]),
                  ),
                ),
          body: c.vacio
              ? EstadoVacio(
                  icono: Icons.shopping_cart_outlined,
                  titulo: 'Tu carrito está vacío',
                  subtitulo: 'Agrega productos desde el catálogo.',
                  accion: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Ver catálogo')),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  for (final l in List.of(c.lineas))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          ProductoImagen(l.producto, tam: 56),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.producto.nombre, style: tema.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(dinero(l.precio), style: TextStyle(color: tema.colorScheme.outline)),
                              const SizedBox(height: 4),
                              Text(dinero(l.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                          Column(children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton.outlined(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(l.cantidad == 1 ? Icons.delete_outline : Icons.remove),
                                onPressed: () => c.cambiarCantidad(l, l.cantidad - 1),
                              ),
                              SizedBox(width: 32, child: Text('${l.cantidad}', textAlign: TextAlign.center, style: tema.textTheme.titleMedium)),
                              IconButton.outlined(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.add),
                                onPressed: l.cantidad >= l.producto.stock ? null : () => c.cambiarCantidad(l, l.cantidad + 1),
                              ),
                            ]),
                            if (l.cantidad >= l.producto.stock)
                              Text('Máximo ${l.producto.stock}', style: tema.textTheme.bodySmall?.copyWith(color: rojo)),
                          ]),
                        ]),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Seguir comprando'),
                    ),
                  ),
                ]),
        );
      },
    );
  }
}
