import { query, transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { paginacion, respuestaListado } from "../utils/consulta.js";
import { redondear } from "../services/ventas.service.js";

/**
 * Compras a proveedores (entrada de mercancía).
 *
 * Reglas:
 * 1. Los totales se calculan aquí (cantidad × costo), nunca se toman del
 *    formulario.
 * 2. Registrar una compra SUMA al stock; cancelarla lo RESTA, y solo si
 *    alcanza (si ya se vendió parte, se explica qué producto no alcanza).
 * 3. Una compra no se edita. Si quedó mal, se cancela y se registra otra.
 * 4. El estado de pago (pendiente, parcial, pagada) sale de los abonos
 *    (vista v_compras_saldo), no se escoge a mano.
 */

const METODOS = ["efectivo", "transferencia", "nequi", "daviplata", "tarjeta"];

const SELECT_LISTA = `
  SELECT c.id_compra, c.folio, c.fecha, c.id_proveedor, pr.nombre AS proveedor,
         c.subtotal, c.impuesto, c.total, c.estado, c.notas, c.motivo_cancelacion, c.cancelada_en,
         s.pagado, s.saldo, s.estado_pago,
         u.nombre AS registro,
         (SELECT COALESCE(SUM(d.cantidad), 0)::INT FROM detalle_compra d WHERE d.id_compra = c.id_compra) AS unidades,
         (SELECT COUNT(*)::INT FROM detalle_compra d WHERE d.id_compra = c.id_compra) AS lineas
    FROM compras c
    JOIN proveedores pr    ON pr.id_proveedor = c.id_proveedor
    JOIN v_compras_saldo s ON s.id_compra = c.id_compra
    LEFT JOIN usuarios u   ON u.id_usuario = c.id_usuario`;

async function detalle(id, db = { query }) {
  const { rows } = await db.query(`${SELECT_LISTA} WHERE c.id_compra = $1`, [id]);
  if (!rows[0]) return null;
  const { rows: items } = await db.query(
    `SELECT d.id_producto, p.nombre, p.sku, d.cantidad, d.costo_unitario, d.subtotal, p.stock AS stock_actual
       FROM detalle_compra d JOIN productos p ON p.id_producto = d.id_producto
      WHERE d.id_compra = $1 ORDER BY d.id_detalle`,
    [id]
  );
  const { rows: pagos } = await db.query(
    `SELECT pc.id_pago_compra, pc.monto, pc.metodo, pc.referencia, pc.fecha, u.nombre AS registro
       FROM pagos_compra pc LEFT JOIN usuarios u ON u.id_usuario = pc.id_usuario
      WHERE pc.id_compra = $1 ORDER BY pc.fecha, pc.id_pago_compra`,
    [id]
  );
  return { ...rows[0], items, pagos };
}

/** GET /api/compras  ?search, id_proveedor, estado, estado_pago, desde, hasta, page, limit */
const listar = asyncHandler(async (req, res) => {
  const { pagina, porPagina, offset } = paginacion(req.query);
  const f = req.query;
  const condiciones = [];
  const valores = [];
  const agregar = (sql, valor) => {
    valores.push(valor);
    condiciones.push(sql.replaceAll("?", `$${valores.length}`));
  };
  if (f.search?.trim()) agregar("(c.folio ILIKE ? OR pr.nombre ILIKE ?)", `%${f.search.trim()}%`);
  if (f.id_proveedor) agregar("c.id_proveedor = ?", Number(f.id_proveedor));
  if (["vigente", "cancelada"].includes(f.estado)) agregar("c.estado = ?", f.estado);
  if (["pendiente", "parcial", "pagada"].includes(f.estado_pago)) agregar("s.estado_pago = ?", f.estado_pago);
  if (f.desde) agregar("fecha_local(c.fecha) >= ?::DATE", f.desde);
  if (f.hasta) agregar("fecha_local(c.fecha) < (?::DATE + 1)", f.hasta);
  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const desde = `FROM compras c JOIN proveedores pr ON pr.id_proveedor = c.id_proveedor JOIN v_compras_saldo s ON s.id_compra = c.id_compra ${where}`;
  const { rows: t } = await query(
    `SELECT COUNT(*)::INT AS total,
            COALESCE(SUM(c.total) FILTER (WHERE c.estado = 'vigente'), 0) AS comprado,
            COALESCE(SUM(s.saldo) FILTER (WHERE c.estado = 'vigente'), 0) AS por_pagar
       ${desde}`,
    valores
  );
  const { rows } = await query(
    `${SELECT_LISTA} ${where}
      ORDER BY c.fecha DESC, c.id_compra DESC
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );
  res.json({
    ...respuestaListado(rows, t[0].total, { pagina, porPagina }),
    resumen: { comprado: Number(t[0].comprado), por_pagar: Number(t[0].por_pagar) }
  });
});

/** GET /api/compras/siguiente-folio — sugerencia para el formulario (OC-001…). */
const siguienteFolio = asyncHandler(async (_req, res) => {
  const { rows } = await query(
    `SELECT COALESCE(MAX(NULLIF(regexp_replace(folio, '\\D', '', 'g'), '')::INT), 0) + 1 AS n
       FROM compras WHERE folio ~ '^OC-\\d+$'`
  );
  res.json({ ok: true, datos: { folio: `OC-${String(rows[0].n).padStart(3, "0")}` } });
});

/** GET /api/compras/:id */
const obtener = asyncHandler(async (req, res) => {
  const compra = await detalle(req.idNumerico);
  if (!compra) throw new ErrorHttp(404, "No existe esa compra.");
  res.json({ ok: true, datos: compra });
});

function validarPagoCompra(body, maximo) {
  const monto = redondear(body?.monto);
  if (!(monto > 0)) throw new ErrorHttp(400, "Escribe el monto del abono.", { monto: "Debe ser mayor a cero." });
  if (monto > maximo + 0.001) {
    throw new ErrorHttp(400, `El abono supera el saldo ($${maximo.toLocaleString("es-CO")}).`, { monto: "Mayor que el saldo." });
  }
  if (!METODOS.includes(body?.metodo)) throw new ErrorHttp(400, "Método de pago no válido.", { metodo: `Usa uno de: ${METODOS.join(", ")}.` });
  return { monto, metodo: body.metodo, referencia: String(body.referencia ?? "").trim().slice(0, 100) || null };
}

/**
 * POST /api/compras
 * { folio?, id_proveedor, fecha?, impuesto?, notas?,
 *   items: [{ id_producto, cantidad, costo_unitario }], pago_inicial?: { monto, metodo, referencia? } }
 */
const crear = asyncHandler(async (req, res) => {
  const b = req.body ?? {};
  const errores = {};
  const idProveedor = Number(b.id_proveedor);
  if (!Number.isInteger(idProveedor) || idProveedor < 1) errores.id_proveedor = "Elige el proveedor.";
  const items = Array.isArray(b.items) ? b.items : [];
  if (items.length === 0) errores.items = "Agrega al menos un producto.";
  const impuesto = redondear(b.impuesto ?? 0);
  if (!(impuesto >= 0)) errores.impuesto = "No puede ser negativo.";
  const folio = String(b.folio ?? "").trim().toUpperCase();
  if (folio.length > 20) errores.folio = "Máximo 20 caracteres.";
  let fecha = null;
  if (b.fecha) {
    fecha = new Date(b.fecha);
    if (Number.isNaN(fecha.getTime())) errores.fecha = "Fecha no válida.";
    else if (fecha.getTime() > Date.now() + 60_000) errores.fecha = "No puede ser una fecha futura.";
  }
  const lineas = new Map();
  items.forEach((it, i) => {
    const id = Number(it?.id_producto);
    const cantidad = Number(it?.cantidad);
    const costo = redondear(it?.costo_unitario);
    if (!Number.isInteger(id) || id < 1) errores[`items.${i}`] = "Producto no válido.";
    else if (!Number.isInteger(cantidad) || cantidad < 1) errores[`items.${i}`] = "La cantidad debe ser un entero mayor a cero.";
    else if (!(costo >= 0)) errores[`items.${i}`] = "El costo no puede ser negativo.";
    else if (lineas.has(id)) errores[`items.${i}`] = "Ese producto ya está en la lista.";
    else lineas.set(id, { id_producto: id, cantidad, costo_unitario: costo });
  });
  if (Object.keys(errores).length) throw new ErrorHttp(400, "Revisa los datos de la compra.", errores);

  const id = await transaccion(async (db) => {
    const { rows: prov } = await db.query("SELECT nombre, estado FROM proveedores WHERE id_proveedor = $1", [idProveedor]);
    if (!prov[0]) throw new ErrorHttp(400, "El proveedor no existe.", { id_proveedor: "No encontrado." });
    if (!prov[0].estado) throw new ErrorHttp(409, `${prov[0].nombre} está inactivo: actívalo antes de registrarle compras.`);

    const { rows: productos } = await db.query(
      "SELECT id_producto, nombre, estado, id_proveedor FROM productos WHERE id_producto = ANY($1::INT[]) FOR UPDATE",
      [[...lineas.keys()]]
    );
    for (const l of lineas.values()) {
      const p = productos.find((x) => x.id_producto === l.id_producto);
      if (!p) throw new ErrorHttp(400, `El producto ${l.id_producto} no existe.`);
      if (p.id_proveedor !== idProveedor) {
        throw new ErrorHttp(409, `"${p.nombre}" no es de ${prov[0].nombre}. Si ahora se lo compras a este proveedor, cámbialo primero en Productos.`);
      }
      l.nombre = p.nombre;
    }

    const subtotal = redondear([...lineas.values()].reduce((s, l) => s + l.cantidad * l.costo_unitario, 0));
    const total = redondear(subtotal + impuesto);

    let folioFinal = folio;
    if (!folioFinal) {
      const { rows } = await db.query(
        `SELECT COALESCE(MAX(NULLIF(regexp_replace(folio, '\\D', '', 'g'), '')::INT), 0) + 1 AS n FROM compras WHERE folio ~ '^OC-\\d+$'`
      );
      folioFinal = `OC-${String(rows[0].n).padStart(3, "0")}`;
    }
    const { rows: dup } = await db.query("SELECT 1 FROM compras WHERE folio = $1", [folioFinal]);
    if (dup[0]) throw new ErrorHttp(409, `Ya existe una compra con el folio ${folioFinal}.`, { folio: "Ya existe." });

    const { rows } = await db.query(
      `INSERT INTO compras (folio, id_proveedor, id_usuario, fecha, subtotal, impuesto, total, notas)
       VALUES ($1, $2, $3, COALESCE($4, CURRENT_TIMESTAMP), $5, $6, $7, $8) RETURNING id_compra`,
      [folioFinal, idProveedor, req.usuario?.id ?? null, fecha, subtotal, impuesto, total, String(b.notas ?? "").trim().slice(0, 250) || null]
    );
    const idCompra = rows[0].id_compra;
    for (const l of lineas.values()) {
      await db.query(
        `INSERT INTO detalle_compra (id_compra, id_producto, cantidad, costo_unitario, subtotal) VALUES ($1, $2, $3, $4, $5)`,
        [idCompra, l.id_producto, l.cantidad, l.costo_unitario, redondear(l.cantidad * l.costo_unitario)]
      );
      await db.query("UPDATE productos SET stock = stock + $2 WHERE id_producto = $1", [l.id_producto, l.cantidad]);
    }
    if (b.pago_inicial && Number(b.pago_inicial.monto) > 0) {
      const pago = validarPagoCompra(b.pago_inicial, total);
      await db.query(
        "INSERT INTO pagos_compra (id_compra, monto, metodo, referencia, id_usuario) VALUES ($1, $2, $3, $4, $5)",
        [idCompra, pago.monto, pago.metodo, pago.referencia, req.usuario?.id ?? null]
      );
    }
    return idCompra;
  });

  const compra = await detalle(id);
  res.status(201).json({ ok: true, mensaje: `Compra ${compra.folio} registrada: el stock ya se actualizó.`, datos: compra });
});

/** POST /api/compras/:id/pagos  { monto, metodo, referencia? } — abono al proveedor. */
const registrarPago = asyncHandler(async (req, res) => {
  const compra = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM compras WHERE id_compra = $1 FOR UPDATE", [req.idNumerico]);
    if (!rows[0]) throw new ErrorHttp(404, "No existe esa compra.");
    if (rows[0].estado === "cancelada") throw new ErrorHttp(409, `La compra ${rows[0].folio} está cancelada.`);
    const { rows: s } = await db.query("SELECT saldo FROM v_compras_saldo WHERE id_compra = $1", [req.idNumerico]);
    const saldo = Number(s[0].saldo);
    if (saldo <= 0) throw new ErrorHttp(409, `La compra ${rows[0].folio} ya está pagada.`);
    const pago = validarPagoCompra(req.body, saldo);
    await db.query(
      "INSERT INTO pagos_compra (id_compra, monto, metodo, referencia, id_usuario) VALUES ($1, $2, $3, $4, $5)",
      [req.idNumerico, pago.monto, pago.metodo, pago.referencia, req.usuario?.id ?? null]
    );
    return detalle(req.idNumerico, db);
  });
  res.status(201).json({
    ok: true,
    mensaje: `Abono registrado en ${compra.folio}. Saldo: $${Number(compra.saldo).toLocaleString("es-CO")}.`,
    datos: compra
  });
});

/** DELETE /api/compras/:id/pagos/:idPago — deshacer un abono mal registrado. */
const eliminarPago = asyncHandler(async (req, res) => {
  const idPago = Number(req.params.idPago);
  if (!Number.isInteger(idPago) || idPago < 1) throw new ErrorHttp(400, "Abono no válido.");
  const compra = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM compras WHERE id_compra = $1 FOR UPDATE", [req.idNumerico]);
    if (!rows[0]) throw new ErrorHttp(404, "No existe esa compra.");
    const { rowCount } = await db.query("DELETE FROM pagos_compra WHERE id_pago_compra = $1 AND id_compra = $2", [idPago, req.idNumerico]);
    if (!rowCount) throw new ErrorHttp(404, "Ese abono no existe en esta compra.");
    return detalle(req.idNumerico, db);
  });
  res.json({ ok: true, mensaje: "Abono eliminado.", datos: compra });
});

/**
 * POST /api/compras/:id/cancelar  { motivo }
 * Devuelve (resta) el stock que entró. Se bloquea si algún producto ya no
 * alcanza (se vendió) o si la compra tiene abonos (elimínalos primero).
 */
const cancelar = asyncHandler(async (req, res) => {
  const motivo = String(req.body?.motivo ?? "").trim();
  if (motivo.length < 3) throw new ErrorHttp(400, "Escribe el motivo de la cancelación.", { motivo: "Obligatorio." });
  const compra = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM compras WHERE id_compra = $1 FOR UPDATE", [req.idNumerico]);
    const c = rows[0];
    if (!c) throw new ErrorHttp(404, "No existe esa compra.");
    if (c.estado === "cancelada") throw new ErrorHttp(409, `La compra ${c.folio} ya estaba cancelada.`);
    const { rows: pagos } = await db.query("SELECT COUNT(*)::INT AS n FROM pagos_compra WHERE id_compra = $1", [c.id_compra]);
    if (pagos[0].n > 0) throw new ErrorHttp(409, `La compra ${c.folio} tiene ${pagos[0].n} abono(s). Elimínalos antes de cancelarla.`);
    const { rows: items } = await db.query(
      `SELECT d.id_producto, d.cantidad, p.nombre, p.stock
         FROM detalle_compra d JOIN productos p ON p.id_producto = d.id_producto
        WHERE d.id_compra = $1 FOR UPDATE OF p`,
      [c.id_compra]
    );
    const faltan = items.filter((i) => i.stock < i.cantidad);
    if (faltan.length) {
      throw new ErrorHttp(
        409,
        `No se puede cancelar: ya se vendió parte de la mercancía (${faltan.map((i) => `${i.nombre}: hay ${i.stock}, entraron ${i.cantidad}`).join("; ")}).`
      );
    }
    for (const i of items) await db.query("UPDATE productos SET stock = stock - $2 WHERE id_producto = $1", [i.id_producto, i.cantidad]);
    await db.query(
      "UPDATE compras SET estado = 'cancelada', motivo_cancelacion = $2, cancelada_en = CURRENT_TIMESTAMP WHERE id_compra = $1",
      [c.id_compra, motivo]
    );
    return detalle(c.id_compra, db);
  });
  res.json({ ok: true, mensaje: `Compra ${compra.folio} cancelada: el stock se descontó.`, datos: compra });
});

/** DELETE /api/compras/:id — solo una compra ya cancelada (el stock ya se devolvió). */
const eliminar = asyncHandler(async (req, res) => {
  const { rows } = await query("SELECT folio, estado FROM compras WHERE id_compra = $1", [req.idNumerico]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe esa compra.");
  if (rows[0].estado !== "cancelada") throw new ErrorHttp(409, `Cancela la compra ${rows[0].folio} antes de eliminarla.`);
  await query("DELETE FROM compras WHERE id_compra = $1", [req.idNumerico]);
  res.json({ ok: true, mensaje: `Compra ${rows[0].folio} eliminada.` });
});

export default { listar, siguienteFolio, obtener, crear, registrarPago, eliminarPago, cancelar, eliminar };
