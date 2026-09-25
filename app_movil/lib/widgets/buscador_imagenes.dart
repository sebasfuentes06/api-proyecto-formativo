import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'comunes.dart';

/// Imagen encontrada en la API externa.
class ImagenExterna {
  ImagenExterna({required this.titulo, required this.miniatura, required this.pagina, required this.mime});
  final String titulo;
  final String miniatura; // URL de la miniatura (~600 px)
  final String pagina; // página de la imagen, con autor y licencia
  final String mime;
}

/// Imagen ya descargada, lista para subir a nuestra API.
class ImagenElegida {
  ImagenElegida(this.bytes, this.mime, this.origen);
  final Uint8List bytes;
  final String mime;
  final String origen;
}

/// Consumo de la API pública de Wikimedia Commons (millones de fotos con
/// licencia libre, no pide llave). https://commons.wikimedia.org/w/api.php
///
/// Wikimedia exige un User-Agent que identifique la app; sin él puede
/// responder 403.
class ApiImagenes {
  ApiImagenes._();

  static const cabeceras = {
    'User-Agent': 'EssenceDonAireApp/1.0 (proyecto formativo SENA; https://api-proyecto-formativo.vercel.app)',
    'Accept': 'application/json',
  };

  static Future<List<ImagenExterna>> buscar(String texto) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrnamespace': '6', // archivos
      'gsrsearch': '$texto filetype:bitmap',
      'gsrlimit': '30',
      'prop': 'imageinfo',
      'iiprop': 'url|mime',
      'iiurlwidth': '600',
    });
    final r = await http.get(uri, headers: cabeceras).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('La API de imágenes respondió ${r.statusCode}.');
    final datos = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final paginas = ((datos['query'] as Map<String, dynamic>?)?['pages'] as List?) ?? [];
    paginas.sort((a, b) => ((a['index'] ?? 0) as num).compareTo((b['index'] ?? 0) as num));
    return [
      for (final p in paginas)
        if ((p['imageinfo'] as List?)?.isNotEmpty ?? false)
          if (['image/jpeg', 'image/png', 'image/webp'].contains(p['imageinfo'][0]['mime']) &&
              p['imageinfo'][0]['thumburl'] != null)
            ImagenExterna(
              titulo: (p['title'] as String? ?? '').replaceFirst('File:', '').replaceAll(RegExp(r'\.\w+$'), ''),
              miniatura: p['imageinfo'][0]['thumburl'],
              pagina: p['imageinfo'][0]['descriptionurl'] ?? '',
              mime: p['imageinfo'][0]['mime'],
            ),
    ];
  }

  static Future<ImagenElegida> descargar(ImagenExterna img) async {
    final r = await http.get(Uri.parse(img.miniatura), headers: cabeceras).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw Exception('No se pudo descargar la imagen (${r.statusCode}).');
    if (r.bodyBytes.length > 1400 * 1024) throw Exception('La imagen pesa demasiado. Elige otra.');
    final tipo = r.headers['content-type']?.split(';').first ?? img.mime;
    return ImagenElegida(r.bodyBytes, tipo, img.pagina);
  }
}

/// Pantalla para buscar una foto en internet (API de Wikimedia Commons) y
/// usarla como foto del producto. Devuelve la imagen ya descargada.
class BuscadorImagenesScreen extends StatefulWidget {
  const BuscadorImagenesScreen({super.key, required this.busquedaInicial});
  final String busquedaInicial;

  @override
  State<BuscadorImagenesScreen> createState() => _BuscadorImagenesScreenState();
}

class _BuscadorImagenesScreenState extends State<BuscadorImagenesScreen> {
  late final _texto = TextEditingController(text: widget.busquedaInicial);
  List<ImagenExterna>? _resultados;
  Object? _error;
  bool _cargando = false;
  int _solicitud = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_buscar);
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final t = _texto.text.trim();
    if (t.isEmpty) return;
    final n = ++_solicitud;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await ApiImagenes.buscar(t);
      if (mounted && n == _solicitud) setState(() => _resultados = r);
    } catch (e) {
      if (mounted && n == _solicitud) setState(() => _error = e);
    } finally {
      if (mounted && n == _solicitud) setState(() => _cargando = false);
    }
  }

  Future<void> _elegir(ImagenExterna img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Usar esta imagen?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(img.miniatura, headers: ApiImagenes.cabeceras, height: 220, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(img.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text('Imagen de Wikimedia Commons (licencia libre).', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final elegida = await conCarga(context, ApiImagenes.descargar(img), avisarCambio: false);
    if (elegida != null && mounted) Navigator.pop(context, elegida);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar imagen en internet')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _texto,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              hintText: 'Ej. perfume, rosa, frasco de vidrio',
              prefixIcon: const Icon(Icons.image_search),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _buscar),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Fotos de Wikimedia Commons. Tip: busca en inglés para ver más resultados (perfume bottle, rose).',
              style: TextStyle(fontSize: 12)),
        ),
        if (_cargando) const LinearProgressIndicator(),
        Expanded(child: _cuerpo()),
      ]),
    );
  }

  Widget _cuerpo() {
    if (_error != null) return ErrorReintentar(error: _error!, onReintentar: _buscar);
    final r = _resultados;
    if (r == null) return const SizedBox();
    if (r.isEmpty) return const EstadoVacio(icono: Icons.image_not_supported_outlined, titulo: 'Sin resultados. Prueba otras palabras.');
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: r.length,
      itemBuilder: (_, i) => InkWell(
        onTap: () => _elegir(r[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            r[i].miniatura,
            headers: ApiImagenes.cabeceras,
            fit: BoxFit.cover,
            loadingBuilder: (_, hijo, p) => p == null ? hijo : const ColoredBox(color: Color(0x11000000)),
            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x11000000), child: Icon(Icons.broken_image)),
          ),
        ),
      ),
    );
  }
}
