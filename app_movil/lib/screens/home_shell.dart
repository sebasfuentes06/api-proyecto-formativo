import 'package:flutter/material.dart';

import '../core/sesion.dart';
import 'catalogo/catalogo_screen.dart';
import 'clientes/clientes_screen.dart';
import 'cuenta/mi_cuenta_screen.dart';
import 'pagos/pagos_screen.dart';
import 'pedidos/pedidos_screen.dart';
import 'ventas/ventas_screen.dart';

/// Estructura principal: pestañas en la parte de abajo, según el rol.
///
///   Administrador y Vendedor: Clientes · Catálogo · Pedidos · Ventas · Pagos
///   Cliente:                  Catálogo · Mis pedidos · Mis compras · Mi cuenta
///
/// Dentro de cada pantalla se ocultan las acciones que el rol no puede hacer
/// (por ejemplo, el Vendedor no ve "Anular venta"). La API valida lo mismo,
/// así que ocultar un botón es comodidad, no la única protección.
///
/// IndexedStack mantiene vivas las pantallas: al cambiar de pestaña no se
/// pierde la búsqueda ni la posición de la lista.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _Pestana {
  const _Pestana(this.pantalla, this.icono, this.iconoActivo, this.etiqueta);
  final Widget pantalla;
  final IconData icono, iconoActivo;
  final String etiqueta;
}

const _equipo = [
  _Pestana(ClientesScreen(), Icons.people_outline, Icons.people, 'Clientes'),
  _Pestana(CatalogoScreen(), Icons.local_florist_outlined, Icons.local_florist, 'Catálogo'),
  _Pestana(PedidosScreen(), Icons.assignment_outlined, Icons.assignment, 'Pedidos'),
  _Pestana(VentasScreen(), Icons.point_of_sale_outlined, Icons.point_of_sale, 'Ventas'),
  _Pestana(PagosScreen(), Icons.payments_outlined, Icons.payments, 'Pagos'),
];

const _cliente = [
  _Pestana(CatalogoScreen(), Icons.local_florist_outlined, Icons.local_florist, 'Catálogo'),
  _Pestana(PedidosScreen(), Icons.assignment_outlined, Icons.assignment, 'Mis pedidos'),
  _Pestana(VentasScreen(), Icons.receipt_long_outlined, Icons.receipt_long, 'Mis compras'),
  _Pestana(MiCuentaScreen(), Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Mi cuenta'),
];

class _HomeShellState extends State<HomeShell> {
  // El equipo arranca en Ventas (ahí está el resumen del día); el cliente,
  // en el catálogo.
  late int _indice = Sesion.i.esCliente ? 0 : 3;

  @override
  Widget build(BuildContext context) {
    final pestanas = Sesion.i.esCliente ? _cliente : _equipo;
    return Scaffold(
      body: IndexedStack(index: _indice, children: [for (final p in pestanas) p.pantalla]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final p in pestanas)
            NavigationDestination(icon: Icon(p.icono), selectedIcon: Icon(p.iconoActivo), label: p.etiqueta),
        ],
      ),
    );
  }
}
