import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/formato.dart';
import '../../models/modelos.dart';
import '../../widgets/carrito.dart';
import '../../widgets/comunes.dart';

/// Acciones de cobro que se usan desde el detalle de una venta y desde la
/// pestaña Pagos: registrar abono, crear link de Wompi y verificar un pago.

/// Registra un pago total o un abono. Devuelve true si se guardó.
Future<bool> registrarAbono(BuildContext context, Venta venta) async {
  final datos = await showModalBottomSheet<DatosPago>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _HojaAbono(venta: venta),
  );
  if (datos == null || !context.mounted) return false;
  final r = await conCarga(context, Api.i.post('/api/pagos', {'id_venta': venta.id, ...datos.aJson()}));
  if (r == null || !context.mounted) return false;
  mostrarMensaje(context, r['mensaje'] ?? 'Pago registrado.');
  return true;
}

class _HojaAbono extends StatefulWidget {
  const _HojaAbono({required this.venta});
  final Venta venta;

  @override
  State<_HojaAbono> createState() => _HojaAbonoState();
}

class _HojaAbonoState extends State<_HojaAbono> {
  final _form = GlobalKey<FormState>();
  final _datos = DatosPago();

  @override
  Widget build(BuildContext context) {
    final v = widget.venta;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Registrar pago', style: Theme.of(context).textTheme.titleLarge),
            Text('${v.numeroFactura} · ${v.cliente}'),
            const SizedBox(height: 12),
            FilaValor('Total', dinero(v.total)),
            FilaValor('Pagado', dinero(v.pagado)),
            FilaValor('Saldo', dinero(v.saldo), destacado: true, color: rojo),
            const SizedBox(height: 16),
            CamposPago(datos: _datos, maximo: v.saldo),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.check),
              label: const Text('Registrar'),
              onPressed: () {
                if (_form.currentState!.validate()) Navigator.pop(context, _datos);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Crea un link de pago de Wompi y ofrece mandarlo por WhatsApp.
Future<void> crearLinkWompi(BuildContext context, Venta venta) async {
  final control = TextEditingController(text: venta.saldo.round().toString());
  final monto = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Link de pago Wompi'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('El cliente paga con tarjeta, PSE, Nequi o Bancolombia. Cuando Wompi apruebe el pago, el abono se registra solo.'),
        const SizedBox(height: 16),
        TextField(
          controller: control,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Monto a cobrar', prefixText: '\$ ', helperText: 'Saldo: ${dinero(venta.saldo)}'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, leerDinero(control.text)), child: const Text('Crear link')),
      ],
    ),
  );
  if (monto == null || monto <= 0 || !context.mounted) return;
  if (monto > venta.saldo.round()) {
    mostrarMensaje(context, 'El monto no puede superar el saldo (${dinero(venta.saldo)}).', error: true);
    return;
  }

  final r = await conCarga(context, Api.i.post('/api/pagos/wompi/links', {'id_venta': venta.id, 'monto': monto}));
  if (r == null || !context.mounted) return;
  final link = WompiLink.desdeJson(r['datos']);
  await mostrarLinkWompi(context, venta, link);
}

/// Muestra un link ya creado con las opciones para compartirlo.
Future<void> mostrarLinkWompi(BuildContext context, Venta venta, WompiLink link) {
  final mensaje = 'Hola ${venta.cliente.split(' ').first}, este es el link para pagar '
      '${dinero(link.monto)} de tu compra ${venta.numeroFactura} en Essence Don Aire:\n${link.url}\n'
      '¡Gracias!';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Link de pago · ${dinero(link.monto)}', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(link.url, style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
          if (link.expiraEn != null) Text('Vence: ${fechaHora(link.expiraEn)}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => abrirWhatsApp(venta.clienteTelefono, mensaje),
            icon: const Icon(Icons.chat),
            label: const Text('Enviar por WhatsApp'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link.url));
                  mostrarMensaje(ctx, 'Link copiado.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(onPressed: () => Share.share(mensaje), icon: const Icon(Icons.share), label: const Text('Compartir')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(onPressed: () => abrirUrl(link.url), icon: const Icon(Icons.open_in_new), label: const Text('Abrir')),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            'Modo pruebas: paga con la tarjeta 4242 4242 4242 4242 (aprobada) o 4111 1111 1111 1111 (rechazada), '
            'cualquier fecha futura y CVC.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.outline),
          ),
        ]),
      ),
    ),
  );
}

/// Plan B si el webhook de Wompi no llegó: se escribe el id de la
/// transacción (sale en el comprobante de Wompi) y la API la consulta.
Future<void> verificarPagoWompi(BuildContext context) async {
  final id = await pedirTexto(
    context,
    titulo: 'Verificar pago Wompi',
    etiqueta: 'Id de la transacción',
    ayuda: 'Lo encuentras en el comprobante de Wompi o en el panel de comercios (ej. 12345-1668624561-38705).',
    textoOk: 'Verificar',
    minimo: 5,
  );
  if (id == null || !context.mounted) return;
  final r = await conCarga(context, Api.i.post('/api/pagos/wompi/verificar', {'id_transaccion': id}));
  if (r != null && context.mounted) mostrarMensaje(context, r['mensaje'] ?? 'Verificado.');
}

/// Para el rol Cliente: crea el link por el monto que quiera abonar y abre
/// el checkout de Wompi en el navegador. Cuando Wompi aprueba el pago, el
/// webhook registra el abono y al volver a la app el saldo ya aparece
/// actualizado.
Future<void> pagarConWompi(BuildContext context, Venta venta) async {
  final control = TextEditingController(text: venta.saldo.round().toString());
  final monto = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Pagar en línea'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Compra ${venta.numeroFactura}. Puedes pagar todo el saldo o solo una parte (abono).'),
        const SizedBox(height: 16),
        TextField(
          controller: control,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: '¿Cuánto vas a pagar?', prefixText: '\$ ', helperText: 'Saldo: ${dinero(venta.saldo)}'),
        ),
        const SizedBox(height: 8),
        const Text('Tarjeta, PSE, Nequi o Bancolombia a través de Wompi.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, leerDinero(control.text)), child: const Text('Ir a pagar')),
      ],
    ),
  );
  if (monto == null || monto <= 0 || !context.mounted) return;
  if (monto > venta.saldo.round()) {
    mostrarMensaje(context, 'El monto no puede superar tu saldo (${dinero(venta.saldo)}).', error: true);
    return;
  }
  final r = await conCarga(context, Api.i.post('/api/pagos/wompi/links', {'id_venta': venta.id, 'monto': monto}));
  if (r == null || !context.mounted) return;
  final link = WompiLink.desdeJson(r['datos']);
  await abrirUrl(link.url);
  if (context.mounted) {
    mostrarMensaje(context, 'Cuando termines de pagar, vuelve y desliza hacia abajo para ver tu saldo actualizado.');
  }
}
