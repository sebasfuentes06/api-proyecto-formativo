import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/eventos.dart';
import '../models/modelos.dart';

/// Piezas de interfaz que se repiten en todas las pantallas.

// ---------------------------------------------------------------------------
// Mensajes y diálogos
// ---------------------------------------------------------------------------

void mostrarMensaje(BuildContext context, String texto, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: Duration(seconds: error ? 5 : 3),
    ));
}

void mostrarError(BuildContext context, Object e) =>
    mostrarMensaje(context, e is ApiException ? e.completo : 'Error: $e', error: true);

Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String textoOk = 'Aceptar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(textoOk),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un texto (por ejemplo, el motivo de una anulación).
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  String? ayuda,
  String textoOk = 'Aceptar',
  bool peligro = false,
  int minimo = 3,
}) {
  final control = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ayuda != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(ayuda)),
            TextFormField(
              controller: control,
              autofocus: true,
              maxLength: 250,
              decoration: InputDecoration(labelText: etiqueta),
              validator: (v) => (v ?? '').trim().length < minimo ? 'Escribe al menos $minimo caracteres' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          style: peligro ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(ctx, control.text.trim());
          },
          child: Text(textoOk),
        ),
      ],
    ),
  );
}

/// Ejecuta una operación mostrando un indicador de carga que bloquea la
/// pantalla. Si falla, muestra el error y devuelve null.
///
///   final r = await conCarga(context, Api.i.post(...));
///   if (r == null) return; // ya se mostró el error
Future<T?> conCarga<T>(BuildContext context, Future<T> operacion, {bool avisarCambio = true}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))),
    ),
  );
  try {
    final r = await operacion;
    navigator.pop();
    if (avisarCambio) Eventos.cambiaron();
    return r;
  } catch (e) {
    navigator.pop();
    if (context.mounted) mostrarError(context, e);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Estados de pantalla
// ---------------------------------------------------------------------------

class EstadoVacio extends StatelessWidget {
  const EstadoVacio({super.key, required this.icono, required this.titulo, this.subtitulo, this.accion});
  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: tema.colorScheme.outline),
            const SizedBox(height: 12),
            Text(titulo, style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitulo != null) ...[
              const SizedBox(height: 6),
              Text(subtitulo!, style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.outline), textAlign: TextAlign.center),
            ],
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ],
        ),
      ),
    );
  }
}

class ErrorReintentar extends StatelessWidget {
  const ErrorReintentar({super.key, required this.error, required this.onReintentar});
  final Object error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar',
        subtitulo: error is ApiException ? (error as ApiException).completo : '$error',
        accion: FilledButton.tonalIcon(onPressed: onReintentar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
      );
}

// ---------------------------------------------------------------------------
// Etiquetas de estado
// ---------------------------------------------------------------------------

class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, required this.color, this.icono});
  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 4)],
          Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

const verde = Color(0xFF2E7D32);
const ambar = Color(0xFFB26A00);
const rojo = Color(0xFFC62828);
const gris = Color(0xFF757575);
const azul = Color(0xFF1565C0);

Etiqueta etiquetaEstadoPago(String estado) => switch (estado) {
      'pagada' => const Etiqueta('Pagada', color: verde, icono: Icons.check_circle),
      'parcial' => const Etiqueta('Abonada', color: ambar, icono: Icons.timelapse),
      'anulada' => const Etiqueta('Anulada', color: gris, icono: Icons.block),
      _ => const Etiqueta('Pendiente', color: rojo, icono: Icons.schedule),
    };

Etiqueta etiquetaEstadoPedido(String estado) => switch (estado) {
      'confirmado' => const Etiqueta('Confirmado', color: verde, icono: Icons.check_circle),
      'cancelado' => const Etiqueta('Cancelado', color: gris, icono: Icons.cancel),
      _ => const Etiqueta('Pendiente', color: ambar, icono: Icons.schedule),
    };

Etiqueta etiquetaCanal(String canal) => switch (canal) {
      'whatsapp' => const Etiqueta('WhatsApp', color: Color(0xFF128C7E), icono: Icons.chat),
      'app' => const Etiqueta('App', color: Color(0xFF6A1B9A), icono: Icons.phone_iphone),
      _ => const Etiqueta('Punto físico', color: azul, icono: Icons.storefront),
    };

Widget etiquetaStock(Producto p) {
  if (!p.estado) return const Etiqueta('Inactivo', color: gris);
  if (p.agotado) return const Etiqueta('Agotado', color: rojo);
  if (p.stockBajo) return Etiqueta('Quedan ${p.stock}', color: ambar);
  return Etiqueta('${p.stock} en stock', color: verde);
}

// ---------------------------------------------------------------------------
// Imagen de producto
// ---------------------------------------------------------------------------

class ProductoImagen extends StatelessWidget {
  const ProductoImagen(this.producto, {super.key, this.tam = 56, this.radio = 10});
  final Producto producto;
  final double? tam;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final marcador = Container(
      width: tam,
      height: tam,
      color: color.primaryContainer,
      alignment: Alignment.center,
      child: Icon(Icons.local_florist_outlined, color: color.onPrimaryContainer, size: (tam ?? 80) * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: producto.imagenUrl == null
          ? marcador
          : Image.network(
              producto.imagenUrl!,
              width: tam,
              height: tam,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => marcador,
              loadingBuilder: (_, hijo, progreso) => progreso == null ? hijo : marcador,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Campo de búsqueda con espera (no consulta la API en cada letra)
// ---------------------------------------------------------------------------

class CampoBusqueda extends StatefulWidget {
  const CampoBusqueda({super.key, required this.onBuscar, this.pista = 'Buscar...'});
  final ValueChanged<String> onBuscar;
  final String pista;

  @override
  State<CampoBusqueda> createState() => _CampoBusquedaState();
}

class _CampoBusquedaState extends State<CampoBusqueda> {
  final _control = TextEditingController();
  Timer? _espera;

  void _cambio(String v) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () => widget.onBuscar(v.trim()));
    setState(() {});
  }

  @override
  void dispose() {
    _espera?.cancel();
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SearchBar(
          controller: _control,
          hintText: widget.pista,
          elevation: const WidgetStatePropertyAll(0.0),
          leading: const Icon(Icons.search),
          trailing: [
            if (_control.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _control.clear();
                  _cambio('');
                },
              ),
          ],
          onChanged: _cambio,
        ),
      );
}

// ---------------------------------------------------------------------------
// Lista paginada con "jalar para recargar" y carga al llegar al final
// ---------------------------------------------------------------------------

/// Lista genérica para todos los listados de la app.
///
/// Recibe una función que trae la página N. Se recarga sola cuando cambia su
/// `key` (por ejemplo, al cambiar un filtro) o cuando algo cambia en los
/// datos (ver core/eventos.dart).
class ListaPaginada<T> extends StatefulWidget {
  const ListaPaginada({
    super.key,
    required this.cargar,
    required this.itemBuilder,
    required this.vacio,
    this.encabezado,
    this.alCargar,
    this.separador = true,
    this.relleno = const EdgeInsets.only(bottom: 88),
  });

  final Future<Pagina<T>> Function(int pagina) cargar;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget vacio;
  final Widget? encabezado;
  final void Function(Pagina<T>)? alCargar;
  final bool separador;
  final EdgeInsets relleno;

  @override
  State<ListaPaginada<T>> createState() => _ListaPaginadaState<T>();
}

class _ListaPaginadaState<T> extends State<ListaPaginada<T>> {
  final _items = <T>[];
  final _scroll = ScrollController();
  int _pagina = 0;
  int _totalPaginas = 1;
  bool _cargando = true;
  Object? _error;
  // Cada carga lleva un número. Si llega la respuesta de una carga vieja
  // (por ejemplo, el usuario cambió el filtro mientras tanto), se descarta.
  int _solicitud = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _siguiente();
    });
    Eventos.datos.addListener(_recargar);
    // No se puede llamar setState dentro de initState: se agenda para
    // justo después de que se dibuje el primer cuadro.
    Future.microtask(_recargar);
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_recargar);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _recargar() async {
    _pagina = 0;
    _totalPaginas = 1;
    _error = null;
    await _siguiente(reiniciar: true);
  }

  Future<void> _siguiente({bool reiniciar = false}) async {
    if (!mounted) return;
    if (_cargando && !reiniciar) return;
    if (!reiniciar && _pagina >= _totalPaginas) return;
    final numero = ++_solicitud;
    setState(() => _cargando = true);
    try {
      final p = await widget.cargar(reiniciar ? 1 : _pagina + 1);
      if (!mounted || numero != _solicitud) return;
      setState(() {
        if (reiniciar) _items.clear();
        _items.addAll(p.items);
        _pagina = reiniciar ? 1 : _pagina + 1;
        _totalPaginas = p.totalPaginas;
        _error = null;
      });
      widget.alCargar?.call(p);
    } catch (e) {
      if (mounted && numero == _solicitud) setState(() => _error = e);
    } finally {
      if (mounted && numero == _solicitud) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget cuerpo;
    if (_items.isEmpty && _cargando) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty && _error != null) {
      cuerpo = ListView(children: [ErrorReintentar(error: _error!, onReintentar: _recargar)]);
    } else if (_items.isEmpty) {
      cuerpo = ListView(children: [if (widget.encabezado != null) widget.encabezado!, widget.vacio]);
    } else {
      final extra = widget.encabezado != null ? 1 : 0;
      cuerpo = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.relleno,
        itemCount: _items.length + extra + 1,
        separatorBuilder: (_, i) =>
            widget.separador && i >= extra && i < _items.length + extra - 1 ? const Divider(height: 1, indent: 16) : const SizedBox.shrink(),
        itemBuilder: (ctx, i) {
          if (extra == 1 && i == 0) return widget.encabezado!;
          final idx = i - extra;
          if (idx == _items.length) {
            return _pagina < _totalPaginas
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : const SizedBox(height: 8);
          }
          return widget.itemBuilder(ctx, _items[idx]);
        },
      );
    }
    return RefreshIndicator(onRefresh: _recargar, child: cuerpo);
  }
}

// ---------------------------------------------------------------------------
// Otros
// ---------------------------------------------------------------------------

class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.accion});
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text(texto.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    )),
          ),
          if (accion != null) accion!,
        ]),
      );
}

/// Fila "Etiqueta ............ valor" para totales.
class FilaValor extends StatelessWidget {
  const FilaValor(this.etiqueta, this.valor, {super.key, this.destacado = false, this.color});
  final String etiqueta, valor;
  final bool destacado;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final estilo = destacado
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(etiqueta, style: estilo)), Text(valor, style: estilo)]),
    );
  }
}

/// Selector de filtro con chips horizontales.
class FiltroChips<T> extends StatelessWidget {
  const FiltroChips({super.key, required this.opciones, required this.valor, required this.onCambio});
  final Map<T, String> opciones;
  final T valor;
  final ValueChanged<T> onCambio;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final e in opciones.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: e.key == valor,
                  onSelected: (_) => onCambio(e.key),
                ),
              ),
          ],
        ),
      );
}
