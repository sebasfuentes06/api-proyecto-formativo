/**
 * Documentación de los endpoints de la APP MÓVIL (proceso de ventas).
 * Se mezcla con la especificación principal en openapi.js.
 */

const SESION = [{ sesion: [] }];
const ID = { name: "id", in: "path", required: true, schema: { type: "integer", minimum: 1 } };
const ok = (descripcion) => ({ description: descripcion, content: { "application/json": { schema: { type: "object" } } } });
const errores = {
  400: { description: "Datos inválidos" },
  401: { description: "Sin sesión o sesión vencida" },
  404: { description: "No existe" },
  409: { description: "Choca con una regla de negocio (stock, saldo, estado)" }
};
const cuerpo = (ejemplo) => ({ required: true, content: { "application/json": { schema: { type: "object" }, example: ejemplo } } });
const q = (name, descripcion, esquema = { type: "string" }) => ({ name, in: "query", description: descripcion, schema: esquema });

const ITEMS = [{ id_producto: 1, cantidad: 2 }, { id_producto: 3, cantidad: 1, precio_unitario: 230000 }];

const tagsMovil = [
  { name: "Sesión", description: "Login del administrador de la app móvil (JWT)." },
  { name: "Pedidos", description: "Pedidos temporales por WhatsApp o punto físico. No mueven stock hasta convertirse en venta." },
  { name: "Ventas", description: "Ventas confirmadas con factura automática. Descuentan stock en tiempo real." },
  { name: "Pagos", description: "Pagos totales o parciales (abonos), cartera pendiente y Wompi." },
  { name: "Cuentas de cliente", description: "Historial de compras y estado de cuenta." },
  { name: "Dashboard", description: "Indicadores para la pantalla principal de la app." }
];

const pathsMovil = {
  "/api/auth/login": {
    post: {
      tags: ["Sesión"], summary: "Iniciar sesión",
      requestBody: cuerpo({ correo: "admin@essence.com", password: "Essence2026*" }),
      responses: { 200: ok("Token JWT y datos del usuario"), 401: errores[401] }
    }
  },
  "/api/auth/yo": { get: { tags: ["Sesión"], summary: "Usuario de la sesión actual", security: SESION, responses: { 200: ok("Usuario"), 401: errores[401] } } },
  "/api/auth/password": {
    put: { tags: ["Sesión"], summary: "Cambiar la contraseña propia", security: SESION, requestBody: cuerpo({ actual: "Essence2026*", nueva: "OtraClave2026" }), responses: { 200: ok("Actualizada"), 400: errores[400] } }
  },

  "/api/pedidos": {
    get: {
      tags: ["Pedidos"], summary: "Listar pedidos", security: SESION,
      parameters: [q("search", "Código o cliente"), q("estado", "pendiente | confirmado | cancelado"), q("canal", "whatsapp | punto_fisico"), q("id_cliente", "Filtrar por cliente", { type: "integer" }), q("page", "Página", { type: "integer" }), q("limit", "Por página", { type: "integer" })],
      responses: { 200: ok("Listado paginado") }
    },
    post: {
      tags: ["Pedidos"], summary: "Registrar pedido", security: SESION,
      requestBody: cuerpo({ id_cliente: 1, canal: "whatsapp", direccion_entrega: "Vereda La Loma", notas: "Envolver para regalo", items: ITEMS }),
      responses: { 201: ok("Pedido creado"), ...errores }
    }
  },
  "/api/pedidos/{id}": {
    get: { tags: ["Pedidos"], summary: "Detalle del pedido (con stock actual de cada producto)", security: SESION, parameters: [ID], responses: { 200: ok("Pedido"), 404: errores[404] } },
    put: { tags: ["Pedidos"], summary: "Actualizar pedido pendiente (items reemplaza el detalle)", security: SESION, parameters: [ID], requestBody: cuerpo({ notas: "Llega el sábado", items: ITEMS }), responses: { 200: ok("Actualizado"), ...errores } }
  },
  "/api/pedidos/{id}/cancelar": { post: { tags: ["Pedidos"], summary: "Cancelar pedido pendiente", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "El cliente desistió" }), responses: { 200: ok("Cancelado"), 409: errores[409] } } },
  "/api/pedidos/{id}/convertir": {
    post: {
      tags: ["Pedidos"], summary: "Convertir pedido en venta confirmada", security: SESION, parameters: [ID],
      description: "En una sola transacción: crea la venta con su factura, descuenta el stock y marca el pedido como confirmado. Si un producto se agotó, no se guarda nada.",
      requestBody: cuerpo({ descuento: 10000, pago_inicial: { monto: 100000, metodo: "nequi", referencia: "M123456" } }),
      responses: { 201: ok("Venta creada"), ...errores }
    }
  },

  "/api/ventas": {
    get: {
      tags: ["Ventas"], summary: "Historial de ventas", security: SESION,
      parameters: [q("search", "Factura o cliente"), q("id_cliente", "Cliente", { type: "integer" }), q("estado", "confirmada | anulada"), q("estado_pago", "pendiente | parcial | pagada | con_saldo"), q("desde", "YYYY-MM-DD", { type: "string", format: "date" }), q("hasta", "YYYY-MM-DD", { type: "string", format: "date" }), q("page", "Página", { type: "integer" }), q("limit", "Por página", { type: "integer" })],
      responses: { 200: ok("Listado paginado con resumen de totales") }
    },
    post: {
      tags: ["Ventas"], summary: "Registrar venta (factura automática)", security: SESION,
      description: "Bloquea las filas de los productos (SELECT ... FOR UPDATE) para que dos ventas simultáneas no vendan la misma unidad.",
      requestBody: cuerpo({ id_cliente: 1, canal: "punto_fisico", items: ITEMS, descuento: 0, pago_inicial: { monto: 50000, metodo: "efectivo" } }),
      responses: { 201: ok("Venta creada"), ...errores }
    }
  },
  "/api/ventas/{id}": { get: { tags: ["Ventas"], summary: "Venta completa: cliente, productos, pagos y links de Wompi", security: SESION, parameters: [ID], responses: { 200: ok("Venta"), 404: errores[404] } } },
  "/api/ventas/{id}/anular": { post: { tags: ["Ventas"], summary: "Anular venta (devuelve stock y anula sus pagos)", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "Producto defectuoso" }), responses: { 200: ok("Anulada"), ...errores } } },

  "/api/pagos": {
    get: {
      tags: ["Pagos"], summary: "Listar pagos", security: SESION,
      parameters: [q("id_venta", "Venta", { type: "integer" }), q("id_cliente", "Cliente", { type: "integer" }), q("metodo", "efectivo | transferencia | nequi | daviplata | tarjeta | wompi"), q("estado", "aplicado | anulado"), q("desde", "YYYY-MM-DD"), q("hasta", "YYYY-MM-DD")],
      responses: { 200: ok("Listado con total recaudado") }
    },
    post: { tags: ["Pagos"], summary: "Registrar pago o abono", security: SESION, requestBody: cuerpo({ id_venta: 1, monto: 50000, metodo: "transferencia", referencia: "TR-889" }), responses: { 201: ok("Pago registrado y nuevo saldo"), ...errores } }
  },
  "/api/pagos/{id}/anular": { post: { tags: ["Pagos"], summary: "Anular un pago", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "Transferencia devuelta" }), responses: { 200: ok("Anulado"), ...errores } } },
  "/api/pagos/pendientes": { get: { tags: ["Pagos"], summary: "Reporte de pagos pendientes (cartera por cliente)", security: SESION, responses: { 200: ok("Cartera") } } },
  "/api/pagos/wompi": { get: { tags: ["Pagos"], summary: "¿Está configurado Wompi?", security: SESION, responses: { 200: ok("Estado") } } },
  "/api/pagos/wompi/links": { post: { tags: ["Pagos"], summary: "Crear link de pago Wompi para una venta", security: SESION, requestBody: cuerpo({ id_venta: 1, monto: 50000 }), responses: { 201: ok("Link con URL de checkout"), ...errores, 502: { description: "Wompi rechazó o no respondió" }, 503: { description: "Wompi sin configurar" } } } },
  "/api/pagos/wompi/verificar": { post: { tags: ["Pagos"], summary: "Verificar una transacción de Wompi a mano (si el webhook no llegó)", security: SESION, requestBody: cuerpo({ id_transaccion: "12345-1668624561-38705" }), responses: { 200: ok("Abono registrado"), 409: errores[409] } } },
  "/api/webhooks/wompi": { post: { tags: ["Pagos"], summary: "Webhook de eventos de Wompi (firmado con SHA-256)", responses: { 200: ok("Procesado"), 401: { description: "Firma inválida" } } } },

  "/api/clientes/{id}/historial": { get: { tags: ["Cuentas de cliente"], summary: "Historial de compras y productos favoritos", security: SESION, parameters: [ID], responses: { 200: ok("Historial"), 404: errores[404] } } },
  "/api/clientes/{id}/estado-cuenta": { get: { tags: ["Cuentas de cliente"], summary: "Estado de cuenta: facturado, pagado y saldo", security: SESION, parameters: [ID], responses: { 200: ok("Estado de cuenta"), 404: errores[404] } } },
  "/api/productos/{id}/imagen": {
    get: { tags: ["Productos"], summary: "Foto del producto (pública)", parameters: [ID], responses: { 200: { description: "Imagen", content: { "image/jpeg": {} } }, 404: errores[404] } },
    put: { tags: ["Productos"], summary: "Subir o reemplazar la foto (base64)", security: SESION, parameters: [ID], requestBody: cuerpo({ base64: "/9j/4AAQSkZJRg...", tipo_mime: "image/jpeg" }), responses: { 200: ok("Guardada"), 400: errores[400], 413: { description: "Demasiado pesada" } } },
    delete: { tags: ["Productos"], summary: "Quitar la foto", security: SESION, parameters: [ID], responses: { 200: ok("Eliminada"), 404: errores[404] } }
  },
  "/api/dashboard/resumen": { get: { tags: ["Dashboard"], summary: "Ventas de hoy y del mes, cartera, pedidos pendientes, stock bajo y más vendidos", security: SESION, responses: { 200: ok("Resumen") } } }
};

const seguridad = {
  sesion: { type: "http", scheme: "bearer", bearerFormat: "JWT", description: "Token que devuelve POST /api/auth/login" }
};

export { tagsMovil, pathsMovil, seguridad };
