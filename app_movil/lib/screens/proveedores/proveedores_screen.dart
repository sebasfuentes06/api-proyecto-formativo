import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/contacto.dart';
import '../../core/eventos.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../pdf/documentos_pdf.dart';
import '../../widgets/campos_persona.dart';
import '../../widgets/comunes.dart';
import '../../widgets/exportar.dart';
import '../compras/compras_screen.dart';

/// Proveedores (igual que en la web): listar, buscar, filtrar, ordenar,
/// registrar, editar, activar/desactivar, eliminar (si no tiene productos ni
/// compras), ver la ficha con sus compras y exportar a PDF.
class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  String _buscar = '';
  String _estado = 'all';
  String _orden = 'nombre|asc';
  int _total = 0;

  Map<String, dynamic> get _query => {
        'search': _buscar,
        'status': _estado,
        'sortBy': _orden.split('|').first,
        'sortDir': _orden.split('|').last,
      };

  Future<void> _exportar() async {
    final filas = await Api.i.todos('/api/proveedores', Proveedor.desdeJson, query: _query);
    await compartirListadoPdf<Proveedor>(
      titulo: 'proveedores',
      filas: filas,
      columnas: [
        ColumnaPdf('Nombre', (p) => p.nombre),
        ColumnaPdf('Documento', (p) => p.documento == null ? null : '${p.tipoDocumento ?? ''} ${p.documento}'.trim()),
        ColumnaPdf('Contacto', (p) => p.contacto),
        ColumnaPdf('Teléfono', (p) => p.telefono),
        ColumnaPdf('Ciudad', (p) => p.ciudad),
        ColumnaPdf('Compras', (p) => p.totalCompras, numero: true),
        ColumnaPdf('Total comprado', (p) => p.totalComprado, dinero: true),
        ColumnaPdf('Estado', (p) => p.estado ? 'Activo' : 'Inactivo'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Proveedores${_total > 0 ? ' ($_total)' : ''}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: _orden,
            onSelected: (v) => setState(() => _orden = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'nombre|asc', child: Text('Nombre (A-Z)')),
              PopupMenuItem(value: 'nombre|desc', child: Text('Nombre (Z-A)')),
              PopupMenuItem(value: 'ciudad|asc', child: Text('Ciudad')),
              PopupMenuItem(value: 'fecha_alta|desc', child: Text('Más recientes')),
            ],
          ),
          BotonPdf(exportar: _exportar),
        ],
      ),
      floatingActionButton: !Sesion.i.puede('suppliers.create')
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_proveedores',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProveedorFormScreen())),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Proveedor'),
            ),
      body: Column(children: [
        CampoBusqueda(pista: 'Nombre, contacto o documento', onBuscar: (v) => setState(() => _buscar = v)),
        FiltroChips<String>(
          opciones: const {'all': 'Todos', 'active': 'Activos', 'inactive': 'Inactivos'},
          valor: _estado,
          onCambio: (v) => setState(() => _estado = v),
        ),
        Expanded(
          child: ListaPaginada<Proveedor>(
            key: ValueKey('$_buscar|$_estado|$_orden'),
            cargar: (p) => Api.i.pagina('/api/proveedores', Proveedor.desdeJson, query: {..._query, 'page': p, 'limit': 20}),
            alCargar: (p) {
              if (p.total != _total) setState(() => _total = p.total);
            },
            vacio: const EstadoVacio(icono: Icons.local_shipping_outlined, titulo: 'No hay proveedores en este filtro'),
            itemBuilder: (ctx, p) => ListTile(
              leading: CircleAvatar(child: Icon(p.tipoPersona == 'juridica' ? Icons.business : Icons.person_outline, color: p.estado ? null : gris)),
              title: Text(p.nombre, style: TextStyle(color: p.estado ? null : gris)),
              subtitle: Text([
                p.contacto,
                [p.ciudad, p.departamento].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                '${p.totalProductos} producto(s) · ${p.totalCompras} compra(s)',
              ].whereType<String>().where((s) => s.isNotEmpty).join('\n')),
              isThreeLine: true,
              trailing: p.estado ? const Etiqueta('Activo', color: verde) : const Etiqueta('Inactivo', color: gris),
              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ProveedorDetalleScreen(proveedor: p))),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Ficha de un proveedor (solo lectura) con sus compras y acciones.
class ProveedorDetalleScreen extends StatefulWidget {
  const ProveedorDetalleScreen({super.key, required this.proveedor});
  final Proveedor proveedor;

  @override
  State<ProveedorDetalleScreen> createState() => _ProveedorDetalleScreenState();
}

class _ProveedorDetalleScreenState extends State<ProveedorDetalleScreen> {
  late Proveedor _p = widget.proveedor;

  @override
  void initState() {
    super.initState();
    Eventos.datos.addListener(_recargar);
    _recargar();
  }

  @override
  void dispose() {
    Eventos.datos.removeListener(_recargar);
    super.dispose();
  }

  Future<void> _recargar() async {
    try {
      final r = await Api.i.get('/api/proveedores/${_p.id}');
      if (mounted) setState(() => _p = Proveedor.desdeJson(r['datos']));
    } catch (_) {/* se queda con lo que tenía */}
  }

  Future<void> _cambiarEstado() async {
    final ok = await confirmar(
      context,
      titulo: _p.estado ? 'Desactivar proveedor' : 'Activar proveedor',
      mensaje: _p.estado
          ? '${_p.nombre} no aparecerá para registrar compras nuevas. Sus productos y su historial siguen intactos.'
          : '${_p.nombre} volverá a estar disponible.',
      textoOk: _p.estado ? 'Desactivar' : 'Activar',
      peligro: _p.estado,
    );
    if (!ok || !mounted) return;
    await conCarga(context, Api.i.put('/api/proveedores/${_p.id}', {'estado': !_p.estado}));
  }

  Future<void> _eliminar() async {
    final ok = await eliminarConAviso(
      context,
      nombre: _p.nombre,
      ruta: '/api/proveedores/${_p.id}',
      nota: 'Nota: no se puede eliminar un proveedor que ya está agregado a una compra o que surte productos; desactívalo en su lugar.',
    );
    if (ok && mounted) {
      mostrarMensaje(context, 'Proveedor eliminado.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedor'),
        actions: [
          if (Sesion.i.puede('data.export'))
            IconButton(
              tooltip: 'Descargar PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => conCarga(context, compartirProveedorPdf(p), avisarCambio: false),
            ),
          if (Sesion.i.puede('suppliers.edit'))
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProveedorFormScreen(proveedor: p))),
            ),
          if (Sesion.i.puedeAlguno(['suppliers.toggle', 'suppliers.edit', 'suppliers.delete']))
            PopupMenuButton<String>(
              onSelected: (v) => v == 'estado' ? _cambiarEstado() : _eliminar(),
              itemBuilder: (_) => [
                if (Sesion.i.puedeAlguno(['suppliers.toggle', 'suppliers.edit']))
                  PopupMenuItem(value: 'estado', child: Text(p.estado ? 'Desactivar' : 'Activar')),
                if (Sesion.i.puede('suppliers.delete'))
                  const PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: rojo))),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(p.tipoPersona == 'juridica' ? Icons.business : Icons.person_outline)),
            title: Text(p.nombre, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(p.contacto ?? 'Sin contacto registrado'),
            trailing: p.estado ? const Etiqueta('Activo', color: verde) : const Etiqueta('Inactivo', color: gris),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            _Cifra('Órdenes de compra', '${p.totalCompras}'),
            _Cifra('Total comprado', dinero(p.totalComprado)),
            _Cifra('Productos', '${p.totalProductos}'),
          ]),
        ),
        const TituloSeccion('Datos'),
        ListTile(
          dense: true,
          leading: const Icon(Icons.badge_outlined),
          title: Text(p.documento == null ? 'Sin documento' : '${p.tipoDocumento ?? ''} ${p.documento}'.trim()),
          subtitle: Text(p.tipoPersona == 'juridica' ? 'Persona jurídica' : p.tipoPersona == 'natural' ? 'Persona natural' : 'Tipo de persona no registrado'),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.phone_outlined),
          title: Text(p.telefono ?? 'Sin teléfono'),
          trailing: p.telefono == null ? null : IconButton(icon: const Icon(Icons.chat, color: Color(0xFF128C7E)), onPressed: () => abrirWhatsApp(p.telefono, 'Hola ${p.contacto ?? p.nombre}, ')),
        ),
        ListTile(dense: true, leading: const Icon(Icons.mail_outline), title: Text(p.email ?? 'Sin correo')),
        ListTile(
          dense: true,
          leading: const Icon(Icons.place_outlined),
          title: Text([p.ciudad, p.departamento].whereType<String>().where((s) => s.isNotEmpty).join(', ').isEmpty
              ? 'Sin ubicación'
              : [p.ciudad, p.departamento].whereType<String>().where((s) => s.isNotEmpty).join(', ')),
        ),
        if (p.fechaAlta != null) ListTile(dense: true, leading: const Icon(Icons.event_outlined), title: Text('Proveedor desde ${fecha(p.fechaAlta)}')),
        if (Sesion.i.puede('purchases.view')) ...[
          const TituloSeccion('Compras'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Ver historial de compras'),
              subtitle: Text('${p.totalCompras} compra(s) vigentes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComprasScreen(proveedor: p))),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.titulo, this.valor);
  final String titulo, valor;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          margin: const EdgeInsets.all(4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
          ),
        ),
      );
}

/// Tipos de documento según el tipo de persona (los mismos de la web).
const _documentosNatural = {'CC': 'Cédula de ciudadanía', 'CE': 'Cédula de extranjería', 'PPT': 'Permiso por protección temporal', 'PAS': 'Pasaporte'};
const _documentosJuridica = {'NIT': 'NIT'};

/// Registrar o editar un proveedor.
class ProveedorFormScreen extends StatefulWidget {
  const ProveedorFormScreen({super.key, this.proveedor});
  final Proveedor? proveedor;

  @override
  State<ProveedorFormScreen> createState() => _ProveedorFormScreenState();
}

class _ProveedorFormScreenState extends State<ProveedorFormScreen> {
  final _form = GlobalKey<FormState>();
  late String? _tipoPersona = widget.proveedor?.tipoPersona;
  late String? _tipoDocumento = widget.proveedor?.tipoDocumento;
  late final _documento = TextEditingController(text: widget.proveedor?.documento);
  late final _nombre = TextEditingController(text: widget.proveedor?.nombre);
  late final _contacto = TextEditingController(text: widget.proveedor?.contacto);
  late final _email = TextEditingController(text: widget.proveedor?.email);
  late final _telefono = TextEditingController(text: widget.proveedor?.telefono);
  late String _departamento = (widget.proveedor?.departamento ?? '').isEmpty ? 'Antioquia' : widget.proveedor!.departamento!;
  late String? _ciudad = widget.proveedor?.ciudad;
  late bool _estado = widget.proveedor?.estado ?? true;

  bool get _editando => widget.proveedor != null;
  bool get _juridica => _tipoPersona == 'juridica';

  @override
  void dispose() {
    for (final c in [_documento, _nombre, _contacto, _email, _telefono]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validarDocumento(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'El número de documento es obligatorio';
    if (_tipoDocumento == 'NIT' && !RegExp(r'^\d{6,12}(-\d)?$').hasMatch(t)) return 'NIT: números y dígito de verificación (900123456-7)';
    if (_tipoDocumento == 'CC' && !RegExp(r'^\d{5,11}$').hasMatch(t)) return 'Solo números, entre 5 y 11 dígitos';
    return null;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      mostrarMensaje(context, 'Revisa los campos marcados en rojo.', error: true);
      return;
    }
    final datos = <String, dynamic>{
      'tipo_persona': _tipoPersona,
      'tipo_documento': _tipoDocumento,
      'documento': _documento.text.trim(),
      'nombre': _nombre.text.trim(),
      'contacto': _contacto.text.trim(),
      'email': _email.text.trim(),
      'telefono': _telefono.text.trim(),
      'departamento': _departamento,
      'ciudad': _ciudad,
      'estado': _estado,
    };
    if (!_editando) datos.removeWhere((_, v) => v == null || v == '');
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/proveedores/${widget.proveedor!.id}', datos) : Api.i.post('/api/proveedores', datos),
    );
    if (r == null || !mounted) return;
    mostrarMensaje(context, _editando ? 'Proveedor actualizado.' : 'Proveedor registrado.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    final documentos = _juridica ? _documentosJuridica : _documentosNatural;
    return ProtegerSalida(
      child: Scaffold(
        appBar: AppBar(title: Text(_editando ? 'Editar proveedor' : 'Nuevo proveedor')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
              initialValue: _tipoPersona,
              decoration: const InputDecoration(labelText: 'Tipo de persona *', prefixIcon: Icon(Icons.account_box_outlined)),
              items: const [
                DropdownMenuItem(value: 'natural', child: Text('Persona natural')),
                DropdownMenuItem(value: 'juridica', child: Text('Persona jurídica (empresa)')),
              ],
              onChanged: (v) => setState(() {
                _tipoPersona = v;
                _tipoDocumento = v == 'juridica' ? 'NIT' : (_tipoDocumento == 'NIT' ? null : _tipoDocumento);
              }),
              validator: (v) => v == null ? 'Elige el tipo de persona' : null,
            ),
            espacio,
            DropdownButtonFormField<String>(
              key: ValueKey('doc|$_tipoPersona'),
              initialValue: documentos.containsKey(_tipoDocumento) ? _tipoDocumento : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo de documento *', prefixIcon: Icon(Icons.badge_outlined)),
              items: [for (final e in documentos.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}'))],
              onChanged: (v) => setState(() => _tipoDocumento = v),
              validator: (v) => v == null ? 'Elige el tipo de documento' : null,
            ),
            espacio,
            TextFormField(
              controller: _documento,
              keyboardType: ['CC', 'NIT'].contains(_tipoDocumento) ? TextInputType.number : TextInputType.text,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              decoration: const InputDecoration(labelText: 'Número de documento *', prefixIcon: Icon(Icons.numbers)),
              validator: _validarDocumento,
            ),
            espacio,
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              maxLength: 100,
              decoration: InputDecoration(labelText: _juridica ? 'Razón social *' : 'Nombre *', prefixIcon: const Icon(Icons.store_outlined)),
              validator: (v) => (v ?? '').trim().isEmpty ? (_juridica ? 'La razón social es obligatoria' : 'El nombre es obligatorio') : null,
            ),
            TextFormField(
              controller: _contacto,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Persona de contacto *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'El contacto es obligatorio' : null,
            ),
            espacio,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
              validator: (v) => validarCorreo(v, obligatorio: false),
            ),
            espacio,
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +-]')), LengthLimitingTextInputFormatter(15)],
              decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\+?[0-9\s-]{7,15}$').hasMatch(v!.trim()) ? null : 'Teléfono no válido',
            ),
            espacio,
            CamposUbicacion(
              departamento: _departamento,
              municipio: _ciudad,
              etiquetaMunicipio: 'Ciudad',
              onCambio: (d, c) => setState(() {
                _departamento = d;
                _ciudad = c;
              }),
            ),
            if (_editando)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                subtitle: Text(_estado ? 'Aparece para registrar compras' : 'No aparece para compras nuevas'),
                value: _estado,
                onChanged: Sesion.i.puedeAlguno(['suppliers.toggle', 'suppliers.edit']) ? (v) => setState(() => _estado = v) : null,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _guardar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.save),
              label: Text(_editando ? 'Guardar cambios' : 'Registrar proveedor'),
            ),
          ]),
        ),
      ),
    );
  }
}
