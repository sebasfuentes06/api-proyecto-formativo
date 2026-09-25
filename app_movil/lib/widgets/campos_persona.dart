import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Tipos de documento (los mismos que valida la API).
const tiposDocumento = <String, String>{
  'CC': 'Cédula de ciudadanía',
  'TI': 'Tarjeta de identidad',
  'CE': 'Cédula de extranjería',
  'PPT': 'Permiso por protección temporal',
  'PAS': 'Pasaporte',
  'NIT': 'NIT',
};

/// Municipios de Antioquia, consumidos de una API pública externa:
/// API Colombia (https://api-colombia.com), departamento 2 = Antioquia.
///
/// Se piden una sola vez por sesión de la app. Si no hay internet o la API
/// externa falla, se usa la lista que viene dentro de la app para que el
/// formulario nunca quede bloqueado.
class Municipios {
  Municipios._();

  static const url = 'https://api-colombia.com/api/v1/Department/2/cities';
  static List<String>? _cache;
  static bool desdeApi = false;

  static Future<List<String>> cargar() async {
    if (_cache != null) return _cache!;
    try {
      final r = await http.get(Uri.parse(url), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final lista = (jsonDecode(utf8.decode(r.bodyBytes)) as List)
            .map((m) => (m as Map<String, dynamic>)['name']?.toString().trim() ?? '')
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList();
        if (lista.length > 50) {
          desdeApi = true;
          return _cache = _ordenar(lista);
        }
      }
    } catch (_) {/* sin internet o API caída: se usa la lista local */}
    // La lista de respaldo no se guarda en caché: la próxima vez se vuelve
    // a intentar con la API.
    desdeApi = false;
    return _ordenar(_respaldo);
  }

  /// Orden alfabético sin que las tildes manden al final "Ámaga" o "Ébéjico".
  static List<String> _ordenar(List<String> l) {
    String base(String s) => s
        .toLowerCase()
        .replaceAll(RegExp('[áà]'), 'a')
        .replaceAll(RegExp('[éè]'), 'e')
        .replaceAll(RegExp('[íì]'), 'i')
        .replaceAll(RegExp('[óò]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n{');
    return List.of(l)..sort((a, b) => base(a).compareTo(base(b)));
  }

  static const _respaldo = [
    'Medellín', 'Abejorral', 'Abriaquí', 'Alejandría', 'Amagá', 'Amalfi', 'Andes', 'Angelópolis', 'Angostura',
    'Anorí', 'Anzá', 'Apartadó', 'Arboletes', 'Argelia', 'Armenia', 'Barbosa', 'Bello', 'Belmira', 'Betania',
    'Betulia', 'Briceño', 'Buriticá', 'Cáceres', 'Caicedo', 'Caldas', 'Campamento', 'Cañasgordas', 'Caracolí',
    'Caramanta', 'Carepa', 'Carolina', 'Caucasia', 'Chigorodó', 'Cisneros', 'Ciudad Bolívar', 'Cocorná',
    'Concepción', 'Concordia', 'Copacabana', 'Dabeiba', 'Don Matías', 'Ebéjico', 'El Bagre', 'El Carmen de Viboral',
    'El Santuario', 'Entrerríos', 'Envigado', 'Fredonia', 'Frontino', 'Giraldo', 'Girardota', 'Gómez Plata',
    'Granada', 'Guadalupe', 'Guarne', 'Guatapé', 'Heliconia', 'Hispania', 'Itagüí', 'Ituango', 'Jardín', 'Jericó',
    'La Ceja', 'La Estrella', 'La Pintada', 'La Unión', 'Liborina', 'Maceo', 'Marinilla', 'Montebello', 'Murindó',
    'Mutatá', 'Nariño', 'Nechí', 'Necoclí', 'Olaya', 'Peñol', 'Peque', 'Pueblorrico', 'Puerto Berrío',
    'Puerto Nare', 'Puerto Triunfo', 'Remedios', 'Retiro', 'Rionegro', 'Sabanalarga', 'Sabaneta', 'Salgar',
    'San Andrés de Cuerquia', 'San Carlos', 'San Francisco', 'San Jerónimo', 'San José de La Montaña',
    'San Juan de Urabá', 'San Luis', 'San Pedro', 'San Pedro de Urabá', 'San Rafael', 'San Roque', 'San Vicente',
    'Santa Bárbara', 'Santa Rosa de Osos', 'Santafé de Antioquia', 'Santo Domingo', 'Segovia', 'Sonsón',
    'Sopetrán', 'Támesis', 'Tarazá', 'Tarso', 'Titiribí', 'Toledo', 'Turbo', 'Uramita', 'Urrao', 'Valdivia',
    'Valparaíso', 'Vegachí', 'Venecia', 'Vigía del Fuerte', 'Yalí', 'Yarumal', 'Yolombó', 'Yondó', 'Zaragoza',
  ];
}

/// Los datos de una persona, en el orden que pide la ficha. Lo usan el
/// registro (Crear cuenta) y la ficha de cliente que llena el equipo.
class DatosPersona {
  DatosPersona({
    String nombre = '',
    this.tipoDocumento,
    String documento = '',
    String telefono = '',
    this.municipio,
    String direccion = '',
    String correo = '',
  })  : nombre = TextEditingController(text: nombre),
        documento = TextEditingController(text: documento),
        telefono = TextEditingController(text: telefono),
        direccion = TextEditingController(text: direccion),
        correo = TextEditingController(text: correo);

  final TextEditingController nombre;
  String? tipoDocumento;
  final TextEditingController documento;
  final TextEditingController telefono;
  String? municipio;
  final TextEditingController direccion;
  final TextEditingController correo;

  Map<String, dynamic> aJson() => {
        'nombre': nombre.text.trim(),
        'tipo_documento': tipoDocumento,
        'documento': documento.text.trim(),
        'telefono': telefono.text.trim(),
        'ciudad': municipio,
        'direccion': direccion.text.trim(),
        'correo': correo.text.trim(),
      };

  void dispose() {
    for (final c in [nombre, documento, telefono, direccion, correo]) {
      c.dispose();
    }
  }
}

final _soloDigitos = FilteringTextInputFormatter.digitsOnly;

String? validarNombre(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'El nombre completo es obligatorio';
  if (t.length < 3 || !t.contains(' ')) return 'Escribe nombre y apellido';
  return null;
}

String? validarDocumento(String? tipo, String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'El documento es obligatorio';
  if (tipo == 'CC' || tipo == 'TI') {
    return RegExp(r'^\d{5,11}$').hasMatch(t) ? null : 'Solo números, entre 5 y 11 dígitos';
  }
  if (tipo == 'NIT') return RegExp(r'^\d{6,12}(-\d)?$').hasMatch(t) ? null : 'NIT no válido (ej. 900123456-7)';
  return RegExp(r'^[A-Za-z0-9]{4,15}$').hasMatch(t) ? null : 'Documento no válido';
}

String? validarCelular(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'El celular es obligatorio';
  return RegExp(r'^3\d{9}$').hasMatch(t) ? null : 'Deben ser 10 números y empezar por 3';
}

String? validarCorreo(String? v, {required bool obligatorio}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return obligatorio ? 'El correo es obligatorio' : null;
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t) ? null : 'Correo no válido';
}

/// Los campos, en orden: nombre*, tipo de documento*, documento*, celular*,
/// municipio de Antioquia* (lista de la API), dirección y correo.
/// La contraseña (solo en el registro) la agrega cada pantalla después.
class CamposPersona extends StatefulWidget {
  const CamposPersona({super.key, required this.datos, this.correoObligatorio = false});

  final DatosPersona datos;
  final bool correoObligatorio;

  @override
  State<CamposPersona> createState() => _CamposPersonaState();
}

class _CamposPersonaState extends State<CamposPersona> {
  List<String>? _municipios;
  bool _error = false;

  DatosPersona get d => widget.datos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await Municipios.cargar();
    if (!mounted) return;
    setState(() {
      // Si la ficha ya tenía una ciudad que no está en la lista (datos
      // viejos), se agrega para no perderla al editar.
      _municipios = [
        if (d.municipio != null && d.municipio!.isNotEmpty && !lista.contains(d.municipio)) d.municipio!,
        ...lista,
      ];
      _error = !Municipios.desdeApi;
    });
  }

  @override
  Widget build(BuildContext context) {
    const espacio = SizedBox(height: 14);
    final tema = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(
        controller: d.nombre,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Nombre completo *', prefixIcon: Icon(Icons.person_outline)),
        validator: validarNombre,
      ),
      espacio,
      DropdownButtonFormField<String>(
        initialValue: d.tipoDocumento,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tipo de documento *', prefixIcon: Icon(Icons.badge_outlined)),
        items: [
          for (final e in tiposDocumento.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}')),
        ],
        onChanged: (v) => setState(() => d.tipoDocumento = v),
        validator: (v) => v == null ? 'Elige el tipo de documento' : null,
      ),
      espacio,
      TextFormField(
        controller: d.documento,
        keyboardType: ['CC', 'TI', 'NIT', null].contains(d.tipoDocumento) ? TextInputType.number : TextInputType.text,
        inputFormatters: [
          if (d.tipoDocumento == 'CC' || d.tipoDocumento == 'TI') _soloDigitos,
          LengthLimitingTextInputFormatter(15),
        ],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Número de documento *', prefixIcon: Icon(Icons.numbers)),
        validator: (v) => validarDocumento(d.tipoDocumento, v),
      ),
      espacio,
      TextFormField(
        controller: d.telefono,
        keyboardType: TextInputType.number,
        // Solo números: el teclado no deja escribir letras, espacios ni signos.
        inputFormatters: [_soloDigitos, LengthLimitingTextInputFormatter(10)],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Celular *',
          hintText: '3001234567',
          prefixIcon: Icon(Icons.phone_iphone),
          counterText: '',
        ),
        maxLength: 10,
        validator: validarCelular,
      ),
      espacio,
      if (_municipios == null)
        const InputDecorator(
          decoration: InputDecoration(labelText: 'Municipio (Antioquia) *', prefixIcon: Icon(Icons.location_city_outlined)),
          child: Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Cargando municipios...'),
          ]),
        )
      else
        FormField<String>(
          initialValue: d.municipio,
          validator: (v) => (v == null || v.isEmpty) ? 'Elige el municipio' : null,
          builder: (campo) => InkWell(
            onTap: () async {
              final elegido = await elegirMunicipio(context, _municipios!, actual: campo.value);
              if (elegido != null) {
                campo.didChange(elegido);
                setState(() => d.municipio = elegido);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Municipio (Antioquia) *',
                prefixIcon: const Icon(Icons.location_city_outlined),
                suffixIcon: const Icon(Icons.arrow_drop_down),
                errorText: campo.errorText,
              ),
              isEmpty: campo.value == null,
              child: Text(campo.value ?? ''),
            ),
          ),
        ),
      if (_error)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 12),
          child: Row(children: [
            Expanded(
              child: Text('Sin conexión con la API de municipios: se usa la lista guardada.',
                  style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline)),
            ),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      espacio,
      TextFormField(
        controller: d.direccion,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Dirección de residencia', prefixIcon: Icon(Icons.home_outlined)),
        validator: (v) => (v ?? '').length > 150 ? 'Máximo 150 caracteres' : null,
      ),
      espacio,
      TextFormField(
        controller: d.correo,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: widget.correoObligatorio ? 'Correo *' : 'Correo (opcional)',
          prefixIcon: const Icon(Icons.mail_outline),
        ),
        validator: (v) => validarCorreo(v, obligatorio: widget.correoObligatorio),
      ),
    ]);
  }
}

/// Lista desplegable con buscador (son 125 municipios: sin buscar sería
/// muy largo de recorrer).
Future<String?> elegirMunicipio(BuildContext context, List<String> municipios, {String? actual}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BuscadorMunicipio(municipios: municipios, actual: actual),
  );
}

class _BuscadorMunicipio extends StatefulWidget {
  const _BuscadorMunicipio({required this.municipios, this.actual});
  final List<String> municipios;
  final String? actual;

  @override
  State<_BuscadorMunicipio> createState() => _BuscadorMunicipioState();
}

class _BuscadorMunicipioState extends State<_BuscadorMunicipio> {
  String _filtro = '';

  static String _sinTildes(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  @override
  Widget build(BuildContext context) {
    final f = _sinTildes(_filtro.trim());
    final lista = widget.municipios.where((m) => _sinTildes(m).contains(f)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar municipio (${widget.municipios.length})',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _filtro = v),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('No hay municipios con ese nombre'))
              : ListView.builder(
                  itemCount: lista.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(lista[i]),
                    trailing: lista[i] == widget.actual ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, lista[i]),
                  ),
                ),
        ),
      ]),
    );
  }
}
