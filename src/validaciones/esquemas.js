/**
 * Reglas de validación por entidad.
 *
 * Están separadas de las rutas para poder leerlas de corrido y ver, de un
 * vistazo, qué acepta la API en cada recurso.
 *
 * `requerido: true` solo aplica al crear (POST). Al actualizar (PUT) se usa
 * el mismo esquema en modo parcial: se revisa lo que venga, y lo que no venga
 * se conserva como estaba.
 */

const categoria = {
  nombre: { etiqueta: "El nombre", requerido: true, texto: { max: 100 } },
  descripcion: { etiqueta: "La descripción", texto: { max: 200 } },
  estado: { etiqueta: "El estado", booleano: true }
};

const proveedor = {
  nombre: { etiqueta: "El nombre", requerido: true, texto: { max: 100 } },
  contacto: { etiqueta: "El contacto", texto: { max: 100 } },
  email: { etiqueta: "El correo", correo: true, texto: { max: 100 } },
  telefono: { etiqueta: "El teléfono", telefono: true },
  ciudad: { etiqueta: "La ciudad", texto: { max: 100 } },
  calificacion: { etiqueta: "La calificación", decimal: { min: 0, max: 5 } },
  estado: { etiqueta: "El estado", booleano: true }
};

const cliente = {
  nombre: { etiqueta: "El nombre", requerido: true, texto: { max: 150 } },
  // Opcional: la ficha pide nombre, dirección y teléfono; el correo no
  // siempre lo da un cliente que escribe por WhatsApp.
  correo: { etiqueta: "El correo", correo: true, texto: { max: 100 } },
  telefono: { etiqueta: "El teléfono", telefono: true },
  direccion: { etiqueta: "La dirección", texto: { max: 150 } },
  ciudad: { etiqueta: "La ciudad", texto: { max: 100 } },
  tipo_documento: { etiqueta: "El tipo de documento", texto: { max: 5 } },
  documento: { etiqueta: "El documento", texto: { max: 20 } },
  notas: { etiqueta: "Las notas", texto: { max: 250 } },
  estado: { etiqueta: "El estado", booleano: true }
};

const producto = {
  sku: { etiqueta: "El SKU", requerido: true, texto: { max: 30 } },
  nombre: { etiqueta: "El nombre", requerido: true, texto: { max: 100 } },
  descripcion: { etiqueta: "La descripción", texto: { max: 250 } },
  id_categoria: { etiqueta: "La categoría", requerido: true, entero: { min: 1 } },
  id_proveedor: { etiqueta: "El proveedor", requerido: true, entero: { min: 1 } },
  precio: { etiqueta: "El precio", requerido: true, decimal: { min: 0 } },
  stock: { etiqueta: "El stock", entero: { min: 0 } },
  stock_minimo: { etiqueta: "El stock mínimo", entero: { min: 0 } },
  estado: { etiqueta: "El estado", booleano: true }
};

export { categoria, proveedor, cliente, producto };
