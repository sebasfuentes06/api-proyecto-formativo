import 'package:flutter/foundation.dart';

/// Aviso global de "algo cambió en los datos".
///
/// Las cinco pestañas viven al mismo tiempo (IndexedStack). Si registras una
/// venta desde la ficha de un cliente, la pestaña Ventas, el catálogo (stock)
/// y Pagos deben enterarse. Cada lista escucha este aviso y se recarga.
class Eventos {
  static final ValueNotifier<int> datos = ValueNotifier(0);
  static void cambiaron() => datos.value++;
}
