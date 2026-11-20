import 'package:flutter/material.dart';

import '../core/carrito.dart';
import '../core/sesion.dart';
import 'carrito/carrito_screen.dart';
import 'catalogo/catalogo_screen.dart';
import 'cuenta/mi_cuenta_screen.dart';
import 'inicio/inicio_cliente_screen.dart';
import 'inicio/inicio_screen.dart';
import 'mas/mas_screen.dart';
import 'pagos/pagos_screen.dart';
import 'pedidos/pedidos_screen.dart';
import 'ventas/ventas_screen.dart';

/// Estructura principal: pestañas en la parte de abajo, según el rol y los
/// permisos de la persona (los mismos módulos que la web).
///
///   Equipo (Administrador / Vendedor): Inicio · Catálogo · Pedidos · Ventas · Más
///     (en "Más": Clientes, Pagos, Compras, Categorías, Proveedores, Usuarios,
///      Roles y Mi perfil, cada uno solo si tiene el permiso de verlo).
///   Cliente: Catálogo · Mis pedidos · Mis compras · Mi cuenta
///
/// Dentro de cada pantalla se ocultan las acciones sin permiso. La API valida
/// lo mismo, así que ocultar un botón es comodidad, no la única protección.
///
/// IndexedStack mantiene vivas las pantallas: al cambiar de pestaña no se
/// pierde la búsqueda ni la posición de la lista.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Pestana {
  const _Pestana(this.id, this.pantalla, this.icono, this.iconoActivo, this.etiqueta);
  final String id;
  final Widget pantalla;
  final IconData icono, iconoActivo;
  final String etiqueta;
}

class _HomeShellState extends State<HomeShell> {
  int _indice = 0;
  late final List<_Pestana> _pestanas = _armar();

  List<_Pestana> _armar() {
    final s = Sesion.i;
    if (s.esCliente) {
      return const [
        _Pestana('inicio', InicioClienteScreen(), Icons.home_outlined, Icons.home, 'Inicio'),
        _Pestana('catalogo', CatalogoScreen(), Icons.local_florist_outlined, Icons.local_florist, 'Catálogo'),
        _Pestana('pedidos', PedidosScreen(), Icons.assignment_outlined, Icons.assignment, 'Mis pedidos'),
        _Pestana('ventas', VentasScreen(), Icons.receipt_long_outlined, Icons.receipt_long, 'Mis compras'),
        _Pestana('cuenta', MiCuentaScreen(), Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Mi cuenta'),
      ];
    }
    return [
      if (s.puede('dashboard.view'))
        _Pestana('inicio', InicioScreen(irA: _irA), Icons.dashboard_outlined, Icons.dashboard, 'Inicio'),
      if (s.puedeAlguno(['catalog.view', 'products.view']))
        const _Pestana('catalogo', CatalogoScreen(), Icons.local_florist_outlined, Icons.local_florist, 'Catálogo'),
      if (s.puede('orders.view')) const _Pestana('pedidos', PedidosScreen(), Icons.assignment_outlined, Icons.assignment, 'Pedidos'),
      if (s.puede('sales.view')) const _Pestana('ventas', VentasScreen(), Icons.point_of_sale_outlined, Icons.point_of_sale, 'Ventas'),
      const _Pestana('mas', MasScreen(), Icons.menu, Icons.menu_open, 'Más'),
    ];
  }

  /// Desde un aviso del Inicio se salta a otra pestaña (o se abre el módulo).
  void _irA(String id) {
    final i = _pestanas.indexWhere((p) => p.id == id);
    if (i >= 0) {
      setState(() => _indice = i);
    } else if (id == 'pagos' && Sesion.i.puede('payments.view')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PagosScreen()));
    }
  }

  late final int? _idUsuario = Sesion.i.usuario?.id;

  @override
  void initState() {
    super.initState();
    // El carrito (del cliente o del equipo que arma pedidos desde el
    // catálogo) se recupera del teléfono: sigue ahí aunque se cierre la app.
    // Si un Cliente venía de la vitrina con productos, se suman a su carrito
    // y, si tocó "Registrarme para continuar", se le abre para terminar.
    final id = _idUsuario;
    if (id != null && Sesion.i.puede('orders.create')) {
      Carrito.i.cargar(id, unirInvitado: Sesion.i.esCliente).then((_) {
        if (!mounted || !Carrito.i.abrirAlEntrar) return;
        Carrito.i.abrirAlEntrar = false;
        if (Sesion.i.esCliente && !Carrito.i.vacio) abrirCarrito(context);
      });
    }
  }

  @override
  void dispose() {
    final id = _idUsuario;
    if (id != null) Carrito.i.soltar(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pestanas = _pestanas;
    return Scaffold(
      body: IndexedStack(index: _indice, children: [for (final p in pestanas) p.pantalla]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        // Carrito: se ve en todas las pestañas mientras tenga algo.
        if (Sesion.i.puede('orders.create')) const BarraCarrito(),
        NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: (i) => setState(() => _indice = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final p in pestanas)
              NavigationDestination(icon: Icon(p.icono), selectedIcon: Icon(p.iconoActivo), label: p.etiqueta),
          ],
        ),
      ]),
    );
  }
}
