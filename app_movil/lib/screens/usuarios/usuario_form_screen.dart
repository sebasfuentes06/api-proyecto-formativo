import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/sesion.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/selectores.dart';

/// Crear o editar un usuario de la app y su rol (solo Administrador).
///
/// Si el rol es Cliente, hay que enlazarlo a su ficha de cliente: así, al
/// entrar, ve solo sus pedidos, sus compras y su saldo.
class UsuarioFormScreen extends StatefulWidget {
  const UsuarioFormScreen({super.key, this.usuario, this.clienteInicial});

  final UsuarioApp? usuario;

  /// Desde la ficha de un cliente ("Dar acceso a la app"): llega el rol
  /// Cliente preseleccionado y los datos de la ficha.
  final Cliente? clienteInicial;

  @override
  State<UsuarioFormScreen> createState() => _UsuarioFormScreenState();
}

class _UsuarioFormScreenState extends State<UsuarioFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.usuario?.nombre ?? widget.clienteInicial?.nombre);
  late final _correo = TextEditingController(text: widget.usuario?.correo ?? widget.clienteInicial?.correo);
  final _clave = TextEditingController();
  late String _rol = widget.usuario?.rol ?? (widget.clienteInicial != null ? Rol.cliente : Rol.vendedor);
  late bool _estado = widget.usuario?.estado ?? true;
  late int? _idCliente = widget.usuario?.idCliente ?? widget.clienteInicial?.id;
  late String? _nombreCliente = widget.usuario?.cliente ?? widget.clienteInicial?.nombre;
  bool _verClave = false;

  bool get _editando => widget.usuario != null;
  bool get _soyYo => widget.usuario?.id == Sesion.i.usuario?.id;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _elegirFicha() async {
    final c = await elegirCliente(context);
    if (c == null || !mounted) return;
    setState(() {
      _idCliente = c.id;
      _nombreCliente = c.nombre;
      if (_nombre.text.trim().isEmpty) _nombre.text = c.nombre;
      if (_correo.text.trim().isEmpty && c.correo != null) _correo.text = c.correo!;
    });
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_rol == Rol.cliente && _idCliente == null) {
      mostrarMensaje(context, 'Elige la ficha del cliente.', error: true);
      return;
    }
    final datos = <String, dynamic>{
      'nombre': _nombre.text.trim(),
      'correo': _correo.text.trim(),
      'rol': _rol,
      'id_cliente': _rol == Rol.cliente ? _idCliente : null,
      if (_editando) 'estado': _estado,
      if (!_editando) 'password': _clave.text,
    };
    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/usuarios/${widget.usuario!.id}', datos) : Api.i.post('/api/usuarios', datos),
    );
    if (r == null || !mounted) return;
    if (!_editando) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Usuario creado'),
          content: SelectableText(
            'Compártele estos datos por un medio privado:\n\n'
            'Correo: ${_correo.text.trim()}\n'
            'Contraseña: ${_clave.text}\n\n'
            'Puede cambiarla al entrar, desde su avatar ▸ Cambiar contraseña.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
      if (!mounted) return;
    } else {
      mostrarMensaje(context, 'Usuario actualizado.');
    }
    Navigator.pop(context);
  }

  Future<void> _restablecerClave() async {
    final nueva = await pedirTexto(
      context,
      titulo: 'Restablecer contraseña',
      etiqueta: 'Contraseña nueva (mínimo 8)',
      ayuda: 'Para ${widget.usuario!.nombre}. Compártela por un medio privado.',
      textoOk: 'Restablecer',
      minimo: 8,
    );
    if (nueva == null || !mounted) return;
    final r = await conCarga(context, Api.i.put('/api/usuarios/${widget.usuario!.id}/password', {'nueva': nueva}), avisarCambio: false);
    if (r != null && mounted) mostrarMensaje(context, r['mensaje'] ?? 'Contraseña restablecida.');
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar usuario' : 'Nuevo usuario')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Rol'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: Rol.admin, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
              ButtonSegment(value: Rol.vendedor, label: Text('Vendedor'), icon: Icon(Icons.storefront_outlined)),
              ButtonSegment(value: Rol.cliente, label: Text('Cliente'), icon: Icon(Icons.person_outline)),
            ],
            selected: {_rol},
            onSelectionChanged: (s) => setState(() => _rol = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            switch (_rol) {
              Rol.admin => 'Todo: catálogo, anulaciones, usuarios y el resumen completo del negocio.',
              Rol.vendedor => 'Clientes, pedidos, ventas y abonos. No anula, no edita el catálogo ni usuarios.',
              _ => 'Solo lo suyo: catálogo, sus pedidos, sus compras, su saldo y pago en línea.',
            },
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          if (_rol == Rol.cliente) ...[
            espacio,
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(_nombreCliente ?? 'Elegir ficha de cliente'),
                subtitle: const Text('Ficha a la que queda enlazado'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _elegirFicha,
              ),
            ),
          ],
          espacio,
          TextFormField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre *', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe el nombre' : null,
          ),
          espacio,
          TextFormField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo (con el que entra) *', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim()) ? null : 'Correo no válido',
          ),
          if (!_editando) ...[
            espacio,
            TextFormField(
              controller: _clave,
              obscureText: !_verClave,
              decoration: InputDecoration(
                labelText: 'Contraseña inicial (mínimo 8) *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _verClave = !_verClave),
                ),
              ),
              validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
            ),
          ],
          if (_editando) ...[
            espacio,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              subtitle: Text(_soyYo ? 'Es tu propio usuario' : (_estado ? 'Puede entrar a la app' : 'No puede entrar')),
              value: _estado,
              onChanged: (v) => setState(() => _estado = v),
            ),
            OutlinedButton.icon(onPressed: _restablecerClave, icon: const Icon(Icons.key), label: const Text('Restablecer contraseña')),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.save),
            label: Text(_editando ? 'Guardar cambios' : 'Crear usuario'),
          ),
        ]),
      ),
    );
  }
}
