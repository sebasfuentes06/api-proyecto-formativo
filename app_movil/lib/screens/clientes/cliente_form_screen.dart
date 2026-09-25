import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/modelos.dart';
import '../../widgets/campos_persona.dart';
import '../../widgets/comunes.dart';

/// Crear o editar un cliente. Al guardar, devuelve el Cliente con
/// Navigator.pop, así quien lo abrió (por ejemplo, el selector de cliente de
/// una venta) lo recibe listo para usar.
///
/// Mismos campos y mismo orden que el registro: nombre, tipo y número de
/// documento, celular, municipio de Antioquia (API), dirección y correo.
class ClienteFormScreen extends StatefulWidget {
  const ClienteFormScreen({super.key, this.cliente});
  final Cliente? cliente;

  @override
  State<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

/// Un teléfono viejo guardado como "+57 300 123 4567" queda en 3001234567.
String _celularLimpio(String? t) {
  var d = (t ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 12 && d.startsWith('57')) d = d.substring(2);
  return d;
}

class _ClienteFormScreenState extends State<ClienteFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _datos = DatosPersona(
    nombre: widget.cliente?.nombre ?? '',
    tipoDocumento: tiposDocumento.containsKey(widget.cliente?.tipoDocumento) ? widget.cliente?.tipoDocumento : null,
    documento: widget.cliente?.documento ?? '',
    telefono: _celularLimpio(widget.cliente?.telefono),
    municipio: widget.cliente?.ciudad,
    direccion: widget.cliente?.direccion ?? '',
    correo: widget.cliente?.correo ?? '',
  );
  late final _notas = TextEditingController(text: widget.cliente?.notas);

  bool get _editando => widget.cliente != null;

  @override
  void dispose() {
    _datos.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) {
      mostrarMensaje(context, 'Revisa los campos marcados en rojo.', error: true);
      return;
    }
    final datos = <String, dynamic>{..._datos.aJson(), 'notas': _notas.text.trim()};
    // Al crear no se mandan campos vacíos. Al editar, el correo vacío no se
    // manda (es único en la base y no puede quedar "").
    if (!_editando) datos.removeWhere((_, v) => v == null || v.toString().isEmpty);
    if (_editando && (datos['correo'] as String).isEmpty) datos.remove('correo');

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
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar cliente' : 'Nuevo cliente')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CamposPersona(datos: _datos),
            const SizedBox(height: 14),
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
