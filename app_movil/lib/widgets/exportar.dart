import 'package:flutter/material.dart';

import '../core/sesion.dart';
import 'comunes.dart';

/// Botón "PDF" de los listados (igual que en la web): exporta lo que se ve
/// con los filtros puestos. Solo para quien tiene el permiso data.export.
class BotonPdf extends StatelessWidget {
  const BotonPdf({super.key, required this.exportar, this.tooltip = 'Descargar en PDF'});

  /// Trae los datos y comparte el PDF.
  final Future<void> Function() exportar;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (!Sesion.i.puede('data.export')) return const SizedBox.shrink();
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      onPressed: () => conCarga(context, exportar(), avisarCambio: false),
    );
  }
}
