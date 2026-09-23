import 'package:flutter/material.dart';

import 'catalogo/catalogo_screen.dart';
import 'clientes/clientes_screen.dart';
import 'pagos/pagos_screen.dart';
import 'pedidos/pedidos_screen.dart';
import 'ventas/ventas_screen.dart';

/// Estructura principal: los cinco subprocesos de la ficha como pestañas en
/// la parte de abajo.
///
/// IndexedStack mantiene vivas las cinco pantallas: al cambiar de pestaña no
/// se pierde la búsqueda ni la posición de la lista.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Arranca en Ventas: ahí está el resumen del día.
  int _indice = 3;

  static const _pantallas = [
    ClientesScreen(),
    CatalogoScreen(),
    PedidosScreen(),
    VentasScreen(),
    PagosScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indice, children: _pantallas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.local_florist_outlined), selectedIcon: Icon(Icons.local_florist), label: 'Catálogo'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Ventas'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Pagos'),
        ],
      ),
    );
  }
}
