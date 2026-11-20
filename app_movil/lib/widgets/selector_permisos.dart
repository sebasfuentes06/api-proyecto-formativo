import 'package:flutter/material.dart';

import '../core/permisos.dart';
import 'comunes.dart';

/// Permisos de una persona en forma de tabla (igual que en la web): una fila
/// por módulo y columnas Ver · Crear · Editar · Eliminar; las acciones
/// especiales (anular, pasar a venta, activar...) van debajo del módulo.
///
/// Al elegir el rol salen marcados los de ese rol. Al Vendedor se le pueden
/// quitar o dar (valor = lista personalizada; null = los del rol). El
/// Administrador los tiene todos y el Cliente los de su rol: solo se ven.
class SelectorPermisos extends StatelessWidget {
  const SelectorPermisos({super.key, required this.rol, required this.valor, required this.onCambio, this.bloqueado = false});

  final String rol;
  final List<String>? valor;
  final ValueChanged<List<String>?> onCambio;
  final bool bloqueado;

  static const _columnas = [('view', 'Ver'), ('create', 'Crear'), ('edit', 'Editar'), ('delete', 'Elim.')];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final editables = permisosAsignables(rol);
    final porRol = permisosPorRol[rol] ?? const <String>[];
    final visibles = rol == 'Administrador'
        ? todosLosPermisos.where((p) => !p.endsWith('.own') && p != 'orders.cancel').toList()
        : rol == 'Cliente'
            ? porRol
            : editables;
    final marcados = {...(valor ?? porRol)};
    final personalizado = valor != null;
    final puedeEditar = !bloqueado && editables.isNotEmpty;

    void guardar(Set<String> seleccion) {
      final lista = editables.where(seleccion.contains).toList();
      final base = editables.where(porRol.contains).toList();
      final igual = lista.length == base.length && lista.every(base.contains);
      onCambio(igual ? null : lista);
    }

    void alternar(String clave) {
      final s = {...visibles.where(marcados.contains)};
      if (!s.remove(clave)) s.add(clave);
      guardar(s);
    }

    void alternarModulo(List<String> claves, bool marcar) {
      final s = {...visibles.where(marcados.contains)};
      marcar ? s.addAll(claves) : s.removeAll(claves);
      guardar(s);
    }

    Widget casilla(String? clave, String etiqueta) => SizedBox(
          width: 44,
          child: clave == null
              ? Center(child: Text('—', style: TextStyle(color: tema.colorScheme.outlineVariant)))
              : Checkbox(
                  value: rol == 'Administrador' || marcados.contains(clave),
                  onChanged: puedeEditar ? (_) => alternar(clave) : null,
                  semanticLabel: etiqueta,
                  visualDensity: VisualDensity.compact,
                ),
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.verified_user_outlined, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 6),
            const Text('Permisos', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (personalizado) const Etiqueta('Personalizados', color: ambar),
            const Spacer(),
            if (puedeEditar && personalizado)
              TextButton.icon(onPressed: () => onCambio(null), icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Los del rol')),
          ]),
          Text(
            switch (rol) {
              'Administrador' => 'El Administrador tiene todos los permisos (no se le pueden quitar).',
              'Cliente' => 'El Cliente tiene los permisos de su rol: catálogo, sus pedidos y sus pagos.',
              _ => bloqueado ? 'Solo el Administrador puede cambiar los permisos.' : 'Marcados según el rol Vendedor. Quita o da permisos solo a esta persona.',
            },
            style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          // Encabezado de la tabla.
          Container(
            color: tema.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Padding(padding: EdgeInsets.only(left: 8), child: Text('MÓDULO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))),
              for (final c in _columnas) SizedBox(width: 44, child: Text(c.$2.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
            ]),
          ),
          for (final g in agruparPermisos(visibles)) ...[
            Builder(builder: (context) {
              final todas = rol == 'Administrador' || g.claves.every(marcados.contains);
              final otras = g.claves.where((k) => !_columnas.any((c) => k.endsWith('.${c.$1}'))).toList();
              String? claveDe(String accion) => g.claves.where((k) => k.endsWith('.$accion')).firstOrNull;
              return Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tema.colorScheme.outlineVariant.withAlpha(120)))),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(g.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (puedeEditar && g.claves.length > 1)
                            InkWell(
                              onTap: () => alternarModulo(g.claves, !todas),
                              child: Text(todas ? 'Ninguno' : 'Todos', style: TextStyle(fontSize: 11, color: tema.colorScheme.primary)),
                            ),
                        ]),
                      ),
                    ),
                    for (final c in _columnas) casilla(claveDe(c.$1), '${g.nombre}: ${c.$2}'),
                  ]),
                  if (otras.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Wrap(children: [
                        for (final k in otras)
                          InkWell(
                            onTap: puedeEditar ? () => alternar(k) : null,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              casilla(k, '${g.nombre}: ${nombreAccion(k)}'),
                              Padding(padding: const EdgeInsets.only(right: 8), child: Text(nombreAccion(k), style: const TextStyle(fontSize: 12))),
                            ]),
                          ),
                      ]),
                    ),
                ]),
              );
            }),
          ],
        ]),
      ),
    );
  }
}
