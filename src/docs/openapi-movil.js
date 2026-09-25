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
  { name: "Dashboard", description: "Indicadores para la pantalla principal de la app." },
  { name: "Usuarios", description: "Cuentas de la app y sus roles: Administrador, Vendedor y Cliente. Solo Administrador." }
];

const pathsMovil = {
  "/api/auth/login": {
    post: {
      tags: ["Sesión"], summary: "Iniciar sesión",
      requestBody: cuerpo({ correo: "admin@essence.com", password: "Essence2026*" }),
      responses: { 200: ok("Token JWT y datos del usuario"), 401: errores[401] }
    }
  },
  "/api/auth/registro": {
    post: {
      tags: ["Sesión"], summary: "Registrarse (queda pendiente de aprobación)",
      description: "Crea la cuenta como Cliente pendiente y su ficha de cliente inactiva. Avisa por correo al usuario y a los administradores. No puede entrar hasta que el Administrador la apruebe.",
      requestBody: cuerpo({ nombre: "Ana Gómez", tipo_documento: "CC", documento: "1037654321", telefono: "3001234567", ciudad: "La Pintada", direccion: "Calle 5 # 3-10", correo: "ana@correo.com", password: "MiClave2026", acepta_datos: true }),
      responses: { 201: ok("Solicitud enviada"), 400: errores[400], 409: { description: "Ya existe una cuenta o solicitud con ese correo" } }
    }
  },
  "/api/auth/olvide": {
    post: {
      tags: ["Sesión"], summary: "Olvidé mi contraseña: enviar código al correo",
      description: "Envía un código de 6 dígitos (vence en 15 minutos). Responde igual exista o no el correo, para no revelar quién tiene cuenta. Máximo un código por minuto.",
      requestBody: cuerpo({ correo: "ana@correo.com" }),
      responses: { 200: ok("Código enviado si la cuenta existe"), 429: { description: "Espera antes de pedir otro" }, 503: { description: "Correo sin configurar" } }
    }
  },
  "/api/auth/restablecer": {
    post: {
      tags: ["Sesión"], summary: "Restablecer contraseña con el código",
      description: "El código sirve una vez; tras 5 intentos fallidos se invalida.",
      requestBody: cuerpo({ correo: "ana@correo.com", codigo: "482915", nueva: "OtraClave2026" }),
      responses: { 200: ok("Contraseña actualizada"), 400: errores[400] }
    }
  },
  "/api/auth/yo": { get: { tags: ["Sesión"], summary: "Usuario de la sesión actual", security: SESION, responses: { 200: ok("Usuario"), 401: errores[401] } } },
  "/api/auth/password": {
    put: { tags: ["Sesión"], summary: "Cambiar la contraseña propia", security: SESION, requestBody: cuerpo({ actual: "Essence2026*", nueva: "OtraClave2026" }), responses: { 200: ok("Actualizada"), 400: errores[400] } }
  },

  "/api/pedidos": {
    get: {
      tags: ["Pedidos"], summary: "Listar pedidos", security: SESION,
      parameters: [q("search", "Código o cliente"), q("estado", "pendiente | confirmado | cancelado"), q("canal", "whatsapp | punto_fisico | app"), q("id_cliente", "Filtrar por cliente", { type: "integer" }), q("page", "Página", { type: "integer" }), q("limit", "Por página", { type: "integer" })],
      responses: { 200: ok("Listado paginado") }
    },
    post: {
      tags: ["Pedidos"], summary: "Registrar pedido", security: SESION,
      description: "metodo_pago: cómo va a pagar. Para el rol Cliente es obligatorio y solo puede ser wompi, transferencia o efectivo (en el punto físico).",
      requestBody: cuerpo({ id_cliente: 1, canal: "whatsapp", metodo_pago: "transferencia", direccion_entrega: "Vereda La Loma", notas: "Envolver para regalo", items: ITEMS }),
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
      description: "En una sola transacción: crea la venta con su factura, descuenta el stock y marca el pedido como confirmado. Si un producto se agotó, no se guarda nada. La venta hereda el metodo_pago del pedido si no se manda otro.",
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
      description: "metodo_pago es obligatorio (efectivo, transferencia, nequi, daviplata, tarjeta o wompi); el pago inicial lo usa si no trae el suyo. Bloquea las filas de los productos (SELECT ... FOR UPDATE) para que dos ventas simultáneas no vendan la misma unidad.",
      requestBody: cuerpo({ id_cliente: 1, canal: "punto_fisico", metodo_pago: "efectivo", items: ITEMS, descuento: 0, pago_inicial: { monto: 50000 } }),
      responses: { 201: ok("Venta creada"), ...errores }
    }
  },
  "/api/ventas/{id}": { get: { tags: ["Ventas"], summary: "Venta completa: cliente, productos, pagos y links de Wompi", security: SESION, parameters: [ID], responses: { 200: ok("Venta"), 404: errores[404] } } },
  "/api/ventas/{id}/anular": { post: { tags: ["Ventas"], summary: "Anular venta (devuelve stock y anula sus pagos)", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "Producto defectuoso" }), responses: { 200: ok("Anulada"), ...errores } } },

  "/api/pagos": {
    get: {
      tags: ["Pagos"], summary: "Listar pagos", security: SESION,
      parameters: [q("id_venta", "Venta", { type: "integer" }), q("id_cliente", "Cliente", { type: "integer" }), q("metodo", "efectivo | transferencia | nequi | daviplata | tarjeta | wompi"), q("estado", "aplicado | anulado | pendiente (por aprobar) | rechazado"), q("desde", "YYYY-MM-DD"), q("hasta", "YYYY-MM-DD")],
      responses: { 200: ok("Listado con total recaudado") }
    },
    post: {
      tags: ["Pagos"], summary: "Registrar pago o abono (equipo) / reportar un pago (Cliente)", security: SESION,
      description: "Administrador y Vendedor: el pago queda aplicado. Cliente: queda 'pendiente' hasta que el Administrador lo apruebe; solo transferencia, Nequi o Daviplata, y exige comprobante o referencia. comprobante es opcional: { base64, tipo_mime } (JPG, PNG o WEBP, máx. 1,5 MB).",
      requestBody: cuerpo({ id_venta: 1, monto: 50000, metodo: "transferencia", referencia: "TR-889", comprobante: { base64: "iVBORw0KGgo...", tipo_mime: "image/png" } }),
      responses: { 201: ok("Pago registrado (o reportado) y saldo"), ...errores }
    }
  },
  "/api/pagos/datos-pago": { get: { tags: ["Pagos"], summary: "Datos para pagar: cuenta de transferencia, punto físico y si hay Wompi", security: SESION, responses: { 200: ok("Datos de pago") } } },
  "/api/pagos/{id}/aprobar": { post: { tags: ["Pagos"], summary: "Aprobar un pago reportado por un cliente (Administrador)", security: SESION, parameters: [ID], responses: { 200: ok("Aplicado y nuevo saldo"), ...errores } } },
  "/api/pagos/{id}/rechazar": { post: { tags: ["Pagos"], summary: "Rechazar un pago reportado (Administrador)", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "No llegó la transferencia" }), responses: { 200: ok("Rechazado"), ...errores } } },
  "/api/pagos/{id}/comprobante": {
    get: { tags: ["Pagos"], summary: "Imagen del comprobante (requiere sesión; el Cliente solo los suyos)", security: SESION, parameters: [ID], responses: { 200: { description: "Imagen", content: { "image/jpeg": {}, "image/png": {}, "image/webp": {} } }, 404: errores[404] } },
    put: { tags: ["Pagos"], summary: "Subir o cambiar el comprobante", security: SESION, parameters: [ID], requestBody: cuerpo({ base64: "iVBORw0KGgo...", tipo_mime: "image/png" }), responses: { 200: ok("Guardado"), ...errores } }
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
  "/api/usuarios": {
    get: { tags: ["Usuarios"], summary: "Listar usuarios y solicitudes", security: SESION, parameters: [q("search", "Nombre o correo"), q("rol", "Administrador | Vendedor | Cliente"), q("status", "active | inactive"), q("aprobacion", "pendiente | aprobado | rechazado")], responses: { 200: ok("Listado"), 403: { description: "Solo Administrador" } } },
    post: {
      tags: ["Usuarios"], summary: "Crear usuario", security: SESION,
      description: "Un usuario con rol Cliente debe llevar id_cliente (su ficha). Una ficha tiene como máximo un usuario.",
      requestBody: cuerpo({ nombre: "Carlos Vendedor", correo: "carlos@essence.com", password: "Clave12345", rol: "Vendedor" }),
      responses: { 201: ok("Creado"), ...errores }
    }
  },
  "/api/usuarios/{id}": {
    put: {
      tags: ["Usuarios"], summary: "Editar usuario (nombre, correo, rol, estado, ficha)", security: SESION, parameters: [ID],
      description: "No deja desactivar ni quitarle el rol al único Administrador activo.",
      requestBody: cuerpo({ rol: "Cliente", id_cliente: 3, estado: true }),
      responses: { 200: ok("Actualizado"), ...errores }
    }
  },
  "/api/usuarios/{id}/aprobar": {
    post: { tags: ["Usuarios"], summary: "Aprobar una solicitud de registro y asignar rol", security: SESION, parameters: [ID], requestBody: cuerpo({ rol: "Cliente" }), responses: { 200: ok("Aprobada; se avisa por correo"), 409: errores[409] } }
  },
  "/api/usuarios/{id}/rechazar": {
    post: { tags: ["Usuarios"], summary: "Rechazar una solicitud de registro", security: SESION, parameters: [ID], requestBody: cuerpo({ motivo: "No es cliente de la tienda" }), responses: { 200: ok("Rechazada; se avisa por correo"), 400: errores[400], 409: errores[409] } }
  },
  "/api/usuarios/{id}/password": {
    put: { tags: ["Usuarios"], summary: "Restablecer la contraseña de un usuario", security: SESION, parameters: [ID], requestBody: cuerpo({ nueva: "NuevaClave2026" }), responses: { 200: ok("Restablecida"), 400: errores[400] } }
  },
  "/api/dashboard/resumen": { get: { tags: ["Dashboard"], summary: "Ventas de hoy y del mes, cartera, pedidos pendientes, stock bajo y más vendidos", security: SESION, responses: { 200: ok("Resumen") } } }
};

const seguridad = {
  sesion: { type: "http", scheme: "bearer", bearerFormat: "JWT", description: "Token que devuelve POST /api/auth/login" }
};

export { tagsMovil, pathsMovil, seguridad };
