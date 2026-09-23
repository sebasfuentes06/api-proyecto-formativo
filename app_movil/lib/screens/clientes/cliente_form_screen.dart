import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/modelos.dart';
import '../../widgets/comunes.dart';

/// Crear o editar un cliente. Al guardar, devuelve el Cliente con
/// Navigator.pop, así quien lo abrió (por ejemplo, el selector de cliente de
/// una venta) lo recibe listo para usar.
class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({super.key, this.cliente});
  final Cliente? cliente;

  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.cliente?.nombre);
  late final _telefono = TextEditingController(text: widget.cliente?.telefono);
  late final _direccion = TextEditingController(text: widget.cliente?.direccion);
  late final _ciudad = TextEditingController(text: widget.cliente?.ciudad ?? (widget.cliente == null ? 'La Pintada' : null));
  late final _correo = TextEditingController(text: widget.cliente?.correo);
  late final _documento = TextEditingController(text: widget.cliente?.documento);
  late final _notas = TextEditingController(text: widget.cliente?.notas);

  bool get _editando => widget.cliente != null;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _direccion, _ciudad, _correo, _documento, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final datos = {
      'nombre': _nombre.text.trim(),
      'telefono': _telefono.text.trim(),
      'direccion': _direccion.text.trim(),
      'ciudad': _ciudad.text.trim(),
      'correo': _correo.text.trim(),
      'documento': _documento.text.trim(),
      'notas': _notas.text.trim(),
    };
    // Al crear no se mandan campos vacíos; al editar sí (para poder borrarlos
    // se manda el texto vacío y la API lo guarda así).
    if (!_editando) datos.removeWhere((_, v) => v.isEmpty);
    if (_editando && datos['correo']!.isEmpty) datos.remove('correo');

    final r = await conCarga(
      context,
      _editando ? Api.i.put('/api/clientes/${widget.cliente!.id}', datos) : Api.i.post('/api/clientes', datos),
    );
    if (r == null || !mounted) return;
    mostrarMensaje(context, _editando ? 'Cliente actualizado.' : 'Cliente registrado.');
    Navigator.pop(context, Cliente.desdeJson(r['datos']));
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar cliente' : 'Nuevo cliente')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Escribe el nombre' : null,
            ),
            espacio,
            TextFormField(
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp *', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (v) {
                final digitos = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                if (digitos.length < 7) return 'Escribe un teléfono válido';
                if (!RegExp(r'^[+()\d\s-]{7,20}$').hasMatch(v!.trim())) return 'Solo números, espacios y + ( ) -';
                return null;
              },
            ),
            espacio,
            TextFormField(
              controller: _direccion,
              decoration: const InputDecoration(labelText: 'Dirección', prefixIcon: Icon(Icons.home_outlined)),
            ),
            espacio,
            TextFormField(
              controller: _ciudad,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ciudad / vereda', prefixIcon: Icon(Icons.location_city_outlined)),
            ),
            espacio,
            TextFormField(
              controller: _correo,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo (opcional)', prefixIcon: Icon(Icons.mail_outline)),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t) ? null : 'Correo no válido';
              },
            ),
            espacio,
            TextFormField(
              controller: _documento,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Documento (opcional)', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            espacio,
            TextFormField(
              controller: _notas,
              maxLines: 2,
              maxLength: 250,
              decoration: const InputDecoration(labelText: 'Notas (gustos, referencias)', prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _guardar,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.save),
              label: Text(_editando ? 'Guardar cambios' : 'Registrar cliente'),
            ),
          ],
        ),
      ),
    );
  }
}
