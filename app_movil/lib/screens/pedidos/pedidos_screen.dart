import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/perfil.dart';
import 'pedido_detalle_screen.dart';
import 'pedido_form_screen.dart';

/// Subproceso de pedidos: pedidos temporales por WhatsApp o en el local.
class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  String _buscar = '';
  String _estado = 'pendiente';
  String _canal = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Sesion.i.esCliente ? 'Mis pedidos' : 'Pedidos'),
        actions: [
          if (Sesion.i.esEquipo)
          PopupMenuButton<String>(
            tooltip: 'Canal',
            icon: Icon(_canal.isEmpty ? Icons.filter_list : Icons.filter_list_alt),
            initialValue: _canal,
            onSelected: (v) => setState(() => _canal = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: '', child: Text('Todos los canales')),
              PopupMenuItem(value: 'whatsapp', child: Text('Solo WhatsApp')),
              PopupMenuItem(value: 'punto_fisico', child: Text('Solo punto físico')),
            ],
          ),
          const BotonPerfil(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_pedidos',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PedidoFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Pedido'),
      ),
      body: Column(children: [
        CampoBusqueda(pista: 'Código o cliente', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'pendiente': 'Pendientes', 'confirmado': 'Confirmados', 'cancelado': 'Cancelados', '': 'Todos'},
          valor: _estado,
          onCambio: (v) => setState(() => _estado = v),
        ),
        Expanded(
          child: ListaPaginada<Pedido>(
            key: ValueKey('$_buscar|$_estado|$_canal'),
            cargar: (p) => Api.i.pagina('/api/pedidos', Pedido.desdeJson,
                query: {'search': _buscar, 'estado': _estado, 'canal': _canal, 'page': p, 'limit': 20}),
            vacio: EstadoVacio(
              icono: Icons.assignment_outlined,
              titulo: _estado == 'pendiente' ? 'No hay pedidos pendientes' : 'No hay pedidos aquí',
              subtitulo: Sesion.i.esCliente
                  ? 'Haz tu pedido desde el catálogo o con el botón de abajo.'
                  : 'Registra los pedidos que llegan por WhatsApp para no perder ninguno.',
            ),
            itemBuilder: (ctx, p) => ListTile(
              leading: CircleAvatar(
                backgroundColor: p.canal == 'whatsapp' ? const Color(0xFFDCF8C6) : Theme.of(ctx).colorScheme.secondaryContainer,
                child: Icon(
                  p.canal == 'whatsapp' ? Icons.chat : p.canal == 'app' ? Icons.phone_iphone : Icons.storefront,
                  color: p.canal == 'whatsapp' ? const Color(0xFF128C7E) : null,
                ),
              ),
              title: Row(children: [
                Expanded(child: Text(p.cliente, overflow: TextOverflow.ellipsis)),
                Text(dinero(p.total), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(child: Text('${p.codigo} · ${p.unidades} und. · ${fecha(p.fecha)}')),
                  etiquetaEstadoPedido(p.estado),
                ]),
              ),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => PedidoDetalleScreen(idPedido: p.id))),
            ),
          ),
        ),
      ]),
    );
  }
}
