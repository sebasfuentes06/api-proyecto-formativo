import { ErrorHttp } from "../middlewares/errores.js";
import { leerImagenBase64 } from "../utils/imagen.js";

/**
 * Reglas de negocio compartidas por Ventas, Pedidos y Pagos.
 *
 * Todas reciben `db`, que es la conexión de una transacción abierta (ver
 * transaccion() en db/pool.js). Así la misma lógica sirve para registrar una
 * venta directa y para convertir un pedido en venta, sin copiar código.
 */

const METODOS_PAGO = ["efectivo", "transferencia", "nequi", "daviplata", "tarjeta"];
const CANALES = ["whatsapp", "punto_fisico", "app"];
// Cómo se va a pagar una venta o un pedido. Wompi no es un método para
// registrar a mano (entra solo cuando Wompi confirma), pero sí se puede
// escoger como forma de pago.
const METODOS_VENTA = [...METODOS_PAGO, "wompi"];
// Lo que puede reportar un Cliente desde la app (pagos que no se ven en caja).
const METODOS_REPORTE = ["transferencia", "nequi", "daviplata"];

/** Método de pago de una venta o pedido: obligatorio y de la lista. */
function validarMetodoVenta(metodo, { obligatorio = true } = {}) {
  if (metodo === undefined || metodo === null || metodo === "") {
    if (!obligatorio) return null;
    throw new ErrorHttp(400, "Elige el método de pago.", { metodo_pago: `Usa uno de: ${METODOS_VENTA.join(", ")}.` });
  }
  if (!METODOS_VENTA.includes(metodo)) {
    throw new ErrorHttp(400, "Método de pago no válido.", { metodo_pago: `Usa uno de: ${METODOS_VENTA.join(", ")}.` });
  }
  return metodo;
}

const redondear = (n) => Math.round(Number(n) * 100) / 100;

/**
 * Revisa y normaliza la lista de productos que llega de la app.
 *
 * Si el mismo producto viene dos veces se suman las cantidades: para quien
 * vende es lo mismo "2 + 1 Rosa Eterna" que "3 Rosa Eterna", y la tabla de
 * detalle no admite el producto repetido.
 */
function normalizarItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new ErrorHttp(400, "Agrega al menos un producto.", { items: "La lista de productos está vacía." });
  }

  const porProducto = new Map();
  items.forEach((item, i) => {
    const id = Number(item?.id_producto);
    const cantidad = Number(item?.cantidad);
    if (!Number.isInteger(id) || id < 1) {
      throw new ErrorHttp(400, "Revisa los productos.", { [`items[${i}]`]: "Producto no válido." });
    }
    if (!Number.isInteger(cantidad) || cantidad < 1) {
      throw new ErrorHttp(400, "Revisa los productos.", { [`items[${i}]`]: "La cantidad debe ser un entero mayor que 0." });
    }
    let precio = null;
    if (item.precio_unitario !== undefined && item.precio_unitario !== null && item.precio_unitario !== "") {
      precio = Number(item.precio_unitario);
      if (Number.isNaN(precio) || precio < 0) {
        throw new ErrorHttp(400, "Revisa los productos.", { [`items[${i}]`]: "El precio no puede ser negativo." });
      }
    }
    const previo = porProducto.get(id);
    porProducto.set(id, {
      id_producto: id,
      cantidad: (previo?.cantidad ?? 0) + cantidad,
      precio_unitario: precio ?? previo?.precio_unitario ?? null
    });
  });

  return [...porProducto.values()];
}

/** El cliente debe existir y estar activo. */
async function clienteActivo(db, idCliente) {
  const id = Number(idCliente);
  if (!Number.isInteger(id) || id < 1) throw new ErrorHttp(400, "Selecciona un cliente.", { id_cliente: "Obligatorio." });
  const { rows } = await db.query("SELECT id_cliente, nombre, estado FROM clientes WHERE id_cliente = $1", [id]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe ese cliente.");
  if (!rows[0].estado) throw new ErrorHttp(409, `El cliente ${rows[0].nombre} está inactivo. Actívalo antes de venderle.`);
  return rows[0];
}

/**
 * Trae los productos y comprueba que se puedan vender.
 *
 * `bloquear` agrega FOR UPDATE: las filas quedan reservadas hasta que termine
 * la transacción. Sin eso, dos ventas simultáneas del último frasco podrían
 * leer "stock 1" las dos y venderlo dos veces. Se ordenan por id para que dos
 * transacciones bloqueen siempre en el mismo orden y no se crucen (deadlock).
 */
async function revisarProductos(db, items, { bloquear = false, exigirStock = true } = {}) {
  const ids = items.map((i) => i.id_producto).sort((a, b) => a - b);
  const { rows } = await db.query(
    `SELECT id_producto, sku, nombre, precio, stock, estado
       FROM productos
      WHERE id_producto = ANY($1::INT[])
      ORDER BY id_producto
      ${bloquear ? "FOR UPDATE" : ""}`,
    [ids]
  );
  const porId = new Map(rows.map((p) => [p.id_producto, p]));

  const problemas = {};
  for (const item of items) {
    const p = porId.get(item.id_producto);
    if (!p) {
      problemas[`producto_${item.id_producto}`] = `No existe el producto ${item.id_producto}.`;
    } else if (!p.estado) {
      problemas[`producto_${item.id_producto}`] = `${p.nombre} está inactivo.`;
    } else if (exigirStock && p.stock < item.cantidad) {
      problemas[`producto_${item.id_producto}`] =
        `${p.nombre}: pediste ${item.cantidad} y hay ${p.stock} en stock.`;
    }
  }
  if (Object.keys(problemas).length) {
    throw new ErrorHttp(409, "Hay productos que no se pueden vender.", problemas);
  }

  // Si la app no manda precio, se usa el precio actual del catálogo.
  return items.map((item) => {
    const p = porId.get(item.id_producto);
    return {
      ...item,
      nombre: p.nombre,
      precio_unitario: redondear(item.precio_unitario ?? p.precio)
    };
  });
}

function validarPago({ monto, metodo }, { maximo }) {
  const valor = redondear(monto);
  if (!(valor > 0)) throw new ErrorHttp(400, "El monto del pago debe ser mayor que 0.", { monto: "Mayor que 0." });
  if (!METODOS_PAGO.includes(metodo)) {
    throw new ErrorHttp(400, "Método de pago no válido.", { metodo: `Usa uno de: ${METODOS_PAGO.join(", ")}.` });
  }
  if (valor > maximo + 0.001) {
    throw new ErrorHttp(409, `El pago supera el saldo pendiente ($${maximo.toLocaleString("es-CO")}).`, {
      monto: "Mayor que el saldo."
    });
  }
  return valor;
}

async function insertarPago(
  db,
  { id_venta, monto, metodo, referencia, nota, id_usuario, wompi_transaccion_id = null, estado = "aplicado" }
) {
  const { rows } = await db.query(
    `INSERT INTO pagos (id_venta, monto, metodo, referencia, nota, id_usuario, wompi_transaccion_id, estado)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [id_venta, monto, metodo, referencia?.trim() || null, nota?.trim() || null, id_usuario ?? null, wompi_transaccion_id, estado]
  );
  return rows[0];
}

/**
 * Registra una venta completa dentro de la transacción `db`:
 * encabezado, detalle, descuento de stock, última compra del cliente y,
 * si viene, el primer pago (pago total o abono inicial).
 */
async function registrarVenta(db, datos) {
  const cliente = await clienteActivo(db, datos.id_cliente);
  const canal = datos.canal ?? "punto_fisico";
  if (!CANALES.includes(canal)) throw new ErrorHttp(400, "Canal no válido.", { canal: CANALES.join(" o ") });

  // Si no mandan el método de la venta pero sí un pago inicial, se toma ese.
  const metodoPago = validarMetodoVenta(datos.metodo_pago ?? datos.pago_inicial?.metodo);

  const items = await revisarProductos(db, normalizarItems(datos.items), { bloquear: true });

  const subtotal = redondear(items.reduce((s, i) => s + i.cantidad * i.precio_unitario, 0));
  const descuento = redondear(datos.descuento ?? 0);
  if (Number.isNaN(descuento) || descuento < 0 || descuento > subtotal) {
    throw new ErrorHttp(400, "El descuento no puede ser negativo ni mayor que el subtotal.", { descuento: "Fuera de rango." });
  }
  const total = redondear(subtotal - descuento);

  const { rows } = await db.query(
    `INSERT INTO ventas (id_cliente, id_pedido, canal, subtotal, descuento, total, notas, id_usuario, metodo_pago)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING id_venta, numero_factura`,
    [cliente.id_cliente, datos.id_pedido ?? null, canal, subtotal, descuento, total, datos.notas?.trim() || null, datos.id_usuario ?? null, metodoPago]
  );
  const venta = rows[0];

  for (const item of items) {
    await db.query(
      `INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario) VALUES ($1, $2, $3, $4)`,
      [venta.id_venta, item.id_producto, item.cantidad, item.precio_unitario]
    );
    // Stock en tiempo real. El CHECK (stock >= 0) de la tabla es la última
    // barrera si algo se escapara de la validación de arriba.
    await db.query("UPDATE productos SET stock = stock - $2 WHERE id_producto = $1", [item.id_producto, item.cantidad]);
  }

  await db.query("UPDATE clientes SET ultima_compra = CURRENT_TIMESTAMP WHERE id_cliente = $1", [cliente.id_cliente]);

  let pago = null;
  // El pago inicial usa por defecto el método de la venta.
  const inicial = datos.pago_inicial && { ...datos.pago_inicial, metodo: datos.pago_inicial.metodo ?? metodoPago };
  if (inicial && Number(inicial.monto) > 0) {
    const monto = validarPago(inicial, { maximo: total });
    pago = await insertarPago(db, { ...inicial, monto, id_venta: venta.id_venta, id_usuario: datos.id_usuario });
    if (inicial.comprobante) {
      const { bytes, tipo } = leerImagenBase64(inicial.comprobante);
      await db.query("INSERT INTO pago_comprobante (id_pago, contenido, tipo_mime) VALUES ($1, $2, $3)", [pago.id_pago, bytes, tipo]);
    }
  }

  return { ...venta, total, pago, metodo_pago: metodoPago };
}

/** Saldo de una venta, bloqueando su fila para que dos abonos no se crucen. */
async function saldoVenta(db, idVenta, { bloquear = true } = {}) {
  const { rows } = await db.query(
    `SELECT id_venta, numero_factura, estado, total FROM ventas WHERE id_venta = $1 ${bloquear ? "FOR UPDATE" : ""}`,
    [idVenta]
  );
  const venta = rows[0];
  if (!venta) throw new ErrorHttp(404, "No existe esa venta.");
  const { rows: s } = await db.query("SELECT pagado, saldo, estado_pago FROM v_ventas_saldo WHERE id_venta = $1", [idVenta]);
  return { ...venta, pagado: Number(s[0].pagado), saldo: Number(s[0].saldo), estado_pago: s[0].estado_pago };
}

export {
  METODOS_PAGO,
  METODOS_VENTA,
  METODOS_REPORTE,
  CANALES,
  validarMetodoVenta,
  redondear,
  normalizarItems,
  clienteActivo,
  revisarProductos,
  validarPago,
  insertarPago,
  registrarVenta,
  saldoVenta
};
