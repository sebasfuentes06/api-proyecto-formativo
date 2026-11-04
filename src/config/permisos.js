/**
 * Permisos de la API y de la web: "<módulo>.<acción>".
 *
 * Cada rol trae un juego por defecto (POR_ROL). El Administrador puede
 * ajustarle los permisos a una persona concreta (columna usuarios.permisos):
 *   - NULL  -> usa los del rol
 *   - lista -> usa exactamente esa lista
 * El Administrador siempre tiene todos (no se le pueden quitar, así nadie
 * se queda sin poder administrar el sistema). Un Cliente solo puede tener
 * permisos de cliente.
 */

const TODOS = [
  "dashboard.view",
  "catalog.view", "catalog.edit",
  "products.view", "products.create", "products.edit", "products.delete",
  "categories.view", "categories.create", "categories.edit", "categories.delete",
  "sales.view", "sales.create", "sales.edit", "sales.delete", "sales.cancel", "sales.own",
  "orders.view", "orders.create", "orders.edit", "orders.delete", "orders.status", "orders.convert", "orders.cancel", "orders.own",
  "payments.view", "payments.create", "payments.edit", "payments.delete", "payments.statement", "payments.own",
  "purchases.view", "purchases.create", "purchases.edit", "purchases.delete",
  "customers.view", "customers.create", "customers.edit", "customers.delete", "customers.toggle",
  "suppliers.view", "suppliers.create", "suppliers.edit", "suppliers.delete", "suppliers.toggle",
  "users.view", "users.create", "users.edit", "users.delete",
  "roles.view",
  "data.export",
  "profile.view", "profile.edit"
];

const POR_ROL = {
  Administrador: TODOS.filter((p) => !p.endsWith(".own") && p !== "orders.cancel"),
  Vendedor: [
    "dashboard.view",
    "catalog.view",
    "products.view",
    "categories.view",
    "sales.view", "sales.create", "sales.own",
    "orders.view", "orders.own", "orders.create", "orders.edit", "orders.delete", "orders.convert",
    "payments.view", "payments.own", "payments.create", "payments.statement",
    "purchases.view",
    "customers.view", "customers.create", "customers.edit",
    "suppliers.view",
    "data.export",
    "profile.view", "profile.edit"
  ],
  Cliente: [
    "dashboard.view",
    "catalog.view",
    "orders.view", "orders.own", "orders.create", "orders.cancel",
    "payments.view", "payments.own", "payments.statement",
    "profile.view", "profile.edit"
  ]
};

/** Los que se le pueden asignar a una persona según su rol. */
function asignablesPara(rol) {
  if (rol === "Cliente") return POR_ROL.Cliente;
  if (rol === "Vendedor") return TODOS.filter((p) => p !== "orders.cancel" && !p.endsWith(".own"));
  return POR_ROL.Administrador;
}

/** Permisos que de verdad tiene una persona. */
function permisosEfectivos(rol, personalizados) {
  if (rol === "Administrador") return POR_ROL.Administrador;
  // El Cliente siempre tiene los permisos de su rol (no se personalizan).
  if (rol === "Cliente" || !Array.isArray(personalizados)) return POR_ROL[rol] ?? [];
  const validos = asignablesPara(rol);
  // Los permisos de "solo lo suyo" y el perfil van siempre con el rol.
  const fijos = (POR_ROL[rol] ?? []).filter((p) => p.endsWith(".own") || p.startsWith("profile."));
  return [...new Set([...fijos, ...personalizados.filter((p) => validos.includes(p))])];
}

export { TODOS, POR_ROL, asignablesPara, permisosEfectivos };
