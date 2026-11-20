/// Permisos de la app: "<módulo>.<acción>", los mismos de la API
/// (src/config/permisos.js) y de la web (shared/auth/roles.js).
///
/// La API manda en la sesión la lista de permisos efectivos de la persona
/// (los de su rol o, para un Vendedor, los que el Administrador le
/// personalizó). La app solo los usa para decidir qué mostrar: la API los
/// vuelve a validar en cada petición.
library;

const todosLosPermisos = [
  'dashboard.view',
  'catalog.view', 'catalog.edit',
  'products.view', 'products.create', 'products.edit', 'products.delete',
  'categories.view', 'categories.create', 'categories.edit', 'categories.delete',
  'sales.view', 'sales.create', 'sales.edit', 'sales.delete', 'sales.cancel', 'sales.own',
  'orders.view', 'orders.create', 'orders.edit', 'orders.delete', 'orders.status', 'orders.convert', 'orders.cancel', 'orders.own',
  'payments.view', 'payments.create', 'payments.edit', 'payments.delete', 'payments.statement', 'payments.own',
  'purchases.view', 'purchases.create', 'purchases.edit', 'purchases.delete',
  'customers.view', 'customers.create', 'customers.edit', 'customers.delete', 'customers.toggle',
  'suppliers.view', 'suppliers.create', 'suppliers.edit', 'suppliers.delete', 'suppliers.toggle',
  'users.view', 'users.create', 'users.edit', 'users.delete',
  'roles.view',
  'data.export',
  'profile.view', 'profile.edit',
];

const permisosPorRol = <String, List<String>>{
  'Administrador': [
    'dashboard.view',
    'catalog.view', 'catalog.edit',
    'products.view', 'products.create', 'products.edit', 'products.delete',
    'categories.view', 'categories.create', 'categories.edit', 'categories.delete',
    'sales.view', 'sales.create', 'sales.edit', 'sales.delete', 'sales.cancel',
    'orders.view', 'orders.create', 'orders.edit', 'orders.delete', 'orders.status', 'orders.convert',
    'payments.view', 'payments.create', 'payments.edit', 'payments.delete', 'payments.statement',
    'purchases.view', 'purchases.create', 'purchases.edit', 'purchases.delete',
    'customers.view', 'customers.create', 'customers.edit', 'customers.delete', 'customers.toggle',
    'suppliers.view', 'suppliers.create', 'suppliers.edit', 'suppliers.delete', 'suppliers.toggle',
    'users.view', 'users.create', 'users.edit', 'users.delete',
    'roles.view',
    'data.export',
    'profile.view', 'profile.edit',
  ],
  'Vendedor': [
    'dashboard.view',
    'catalog.view',
    'products.view',
    'categories.view',
    'sales.view', 'sales.create', 'sales.own',
    'orders.view', 'orders.own', 'orders.create', 'orders.edit', 'orders.delete', 'orders.convert',
    'payments.view', 'payments.own', 'payments.create', 'payments.statement',
    'purchases.view',
    'customers.view', 'customers.create', 'customers.edit',
    'suppliers.view',
    'data.export',
    'profile.view', 'profile.edit',
  ],
  'Cliente': [
    'dashboard.view',
    'catalog.view',
    'orders.view', 'orders.own', 'orders.create', 'orders.cancel',
    'payments.view', 'payments.own', 'payments.statement',
    'profile.view', 'profile.edit',
  ],
};

/// Los que el Administrador puede marcar o desmarcar a una persona. El
/// Administrador los tiene todos y el Cliente los de su rol: para ellos la
/// lista sale vacía (no se personalizan).
List<String> permisosAsignables(String rol) => rol == 'Vendedor'
    ? todosLosPermisos.where((p) => p != 'orders.cancel' && !p.endsWith('.own')).toList()
    : const [];

const nombresModulo = {
  'dashboard': 'Dashboard',
  'catalog': 'Catálogo',
  'products': 'Productos',
  'categories': 'Categorías',
  'sales': 'Ventas',
  'orders': 'Pedidos',
  'payments': 'Pagos',
  'purchases': 'Compras',
  'customers': 'Clientes',
  'suppliers': 'Proveedores',
  'users': 'Usuarios',
  'roles': 'Roles',
  'data': 'Exportar datos',
  'profile': 'Mi perfil',
};

const nombresAccion = {
  'view': 'ver',
  'create': 'crear',
  'edit': 'editar',
  'delete': 'eliminar',
  'toggle': 'activar',
  'own': 'solo lo suyo',
  'status': 'cambiar estado',
  'convert': 'pasar a venta',
  'cancel': 'anular',
  'statement': 'estado de cuenta',
  'export': 'CSV y PDF',
};

/// Un módulo con sus acciones, para pintar listas de permisos.
class GrupoPermisos {
  GrupoPermisos(this.modulo, this.nombre, this.claves);
  final String modulo, nombre;
  final List<String> claves;
}

List<GrupoPermisos> agruparPermisos(Iterable<String> permisos) {
  final grupos = <String, List<String>>{};
  for (final p in permisos) {
    grupos.putIfAbsent(p.split('.').first, () => []).add(p);
  }
  return [for (final e in grupos.entries) GrupoPermisos(e.key, nombresModulo[e.key] ?? e.key, e.value)];
}

String nombreAccion(String clave) {
  final accion = clave.split('.').last;
  return nombresAccion[accion] ?? accion;
}
