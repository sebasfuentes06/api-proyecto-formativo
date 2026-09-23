import { query, transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { paginacion, respuestaListado } from "../utils/consulta.js";
import { validarPago, insertarPago, saldoVenta } from "../services/ventas.service.js";
import * as wompi from "../services/wompi.service.js";
import { esCliente } from "../middlewares/auth.js";

/**
 * Controlador de Pagos y Abonos.
 *
 * Un pago puede cubrir toda la venta o solo una parte (abono). El estado de
 * la venta (pendiente / parcial / pagada) no se guarda a mano: lo calcula la
 * vista v_ventas_saldo a partir de los pagos aplicados.
 */

/** GET /api/pagos  ?id_venta= &id_cliente= &metodo= &estado= &desde= &hasta= */
const listar = asyncHandler(async (req, res) => {
  const { pagina, porPagina, offset } = paginacion(req.query);
  const condiciones = [];
  const valores = [];
  const agregar = (sql, valor) => {
    valores.push(valor);
    condiciones.push(sql.replaceAll("?", `$${valores.length}`));
  };
  // El Cliente solo ve sus pagos.
  const f = esCliente(req) ? { ...req.query, id_cliente: req.usuario.idCliente } : req.query;
  if (f.id_venta) agregar("p.id_venta = ?", Number(f.id_venta));
  if (f.id_cliente) agregar("v.id_cliente = ?", Number(f.id_cliente));
  if (f.metodo) agregar("p.metodo = ?", f.metodo);
  if (["aplicado", "anulado"].includes(f.estado)) agregar("p.estado = ?", f.estado);
  if (f.desde) agregar("fecha_local(p.fecha) >= ?::DATE", f.desde);
  if (f.hasta) agregar("fecha_local(p.fecha) < (?::DATE + 1)", f.hasta);
  if (f.search?.trim()) agregar("(v.numero_factura ILIKE ? OR c.nombre ILIKE ? OR p.referencia ILIKE ?)", `%${f.search.trim()}%`);
  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const desde = `FROM pagos p JOIN ventas v ON v.id_venta = p.id_venta JOIN clientes c ON c.id_cliente = v.id_cliente ${where}`;
  const { rows: t } = await query(
    `SELECT COUNT(*)::INT AS total, COALESCE(SUM(p.monto) FILTER (WHERE p.estado = 'aplicado'), 0) AS recaudado ${desde}`,
    valores
  );
  const { rows } = await query(
    `SELECT p.*, v.numero_factura, v.id_cliente, c.nombre AS cliente ${desde}
      ORDER BY p.fecha DESC, p.id_pago DESC
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );
  res.json({ ...respuestaListado(rows, t[0].total, { pagina, porPagina }), resumen: { recaudado: t[0].recaudado } });
});

/** POST /api/pagos  { id_venta, monto, metodo, referencia?, nota? } */
const registrar = asyncHandler(async (req, res) => {
  const idVenta = Number(req.body.id_venta);
  if (!Number.isInteger(idVenta) || idVenta < 1) throw new ErrorHttp(400, "Indica la venta.", { id_venta: "Obligatorio." });

  const { pago, venta } = await transaccion(async (db) => {
    const venta = await saldoVenta(db, idVenta);
    if (venta.estado === "anulada") throw new ErrorHttp(409, "No se pueden registrar pagos en una venta anulada.");
    if (venta.saldo <= 0) throw new ErrorHttp(409, `La venta ${venta.numero_factura} ya está pagada.`);
    const monto = validarPago(req.body, { maximo: venta.saldo });
    const pago = await insertarPago(db, { ...req.body, id_venta: idVenta, monto, id_usuario: req.usuario.id });
    return { pago, venta: await saldoVenta(db, idVenta, { bloquear: false }) };
  });

  const tipo = venta.saldo <= 0 ? "Pago completo" : "Abono";
  res.status(201).json({
    ok: true,
    mensaje: `${tipo} registrado en ${venta.numero_factura}. Saldo: $${venta.saldo.toLocaleString("es-CO")}.`,
    datos: { pago, venta }
  });
});

/** POST /api/pagos/:id/anular  { motivo } */
const anular = asyncHandler(async (req, res) => {
  const motivo = String(req.body?.motivo ?? "").trim();
  if (motivo.length < 3) throw new ErrorHttp(400, "Escribe el motivo de la anulación.", { motivo: "Obligatorio." });

  const venta = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM pagos WHERE id_pago = $1 FOR UPDATE", [req.idNumerico]);
    if (!rows[0]) throw new ErrorHttp(404, "No existe ese pago.");
    if (rows[0].estado === "anulado") throw new ErrorHttp(409, "Ese pago ya estaba anulado.");
    await db.query(
      `UPDATE pagos SET estado = 'anulado', anulado_en = CURRENT_TIMESTAMP,
              nota = LEFT(COALESCE(nota || ' | ', '') || 'Anulado: ' || $2, 250)
        WHERE id_pago = $1`,
      [req.idNumerico, motivo]
    );
    return saldoVenta(db, rows[0].id_venta, { bloquear: false });
  });
  res.json({ ok: true, mensaje: `Pago anulado. Nuevo saldo de ${venta.numero_factura}: $${venta.saldo.toLocaleString("es-CO")}.`, datos: { venta } });
});

/**
 * GET /api/pagos/pendientes — reporte de cartera.
 * Ventas confirmadas con saldo, agrupadas por cliente, de la más vieja a la
 * más nueva (la que lleva más días sin pagarse es la primera a cobrar).
 */
const pendientes = asyncHandler(async (_req, res) => {
  const { rows } = await query(
    `SELECT v.id_venta, v.numero_factura, v.fecha, v.total, s.pagado, s.saldo, s.estado_pago,
            (hoy_local() - fecha_local(v.fecha)::DATE)::INT AS dias,
            c.id_cliente, c.nombre AS cliente, c.telefono AS cliente_telefono
       FROM ventas v
       JOIN v_ventas_saldo s ON s.id_venta = v.id_venta
       JOIN clientes c       ON c.id_cliente = v.id_cliente
      WHERE v.estado = 'confirmada' AND s.saldo > 0
      ORDER BY v.fecha ASC`
  );

  const porCliente = new Map();
  for (const v of rows) {
    const grupo = porCliente.get(v.id_cliente) ?? {
      id_cliente: v.id_cliente,
      cliente: v.cliente,
      telefono: v.cliente_telefono,
      saldo: 0,
      ventas: []
    };
    grupo.saldo += Number(v.saldo);
    grupo.ventas.push(v);
    porCliente.set(v.id_cliente, grupo);
  }
  const clientes = [...porCliente.values()].sort((a, b) => b.saldo - a.saldo);

  res.json({
    ok: true,
    datos: {
      generado: new Date().toISOString(),
      total_pendiente: rows.reduce((s, v) => s + Number(v.saldo), 0),
      cantidad_ventas: rows.length,
      cantidad_clientes: clientes.length,
      clientes
    }
  });
});

/** GET /api/pagos/wompi — qué tan configurado está Wompi (la app lo muestra). */
const wompiEstado = (_req, res) => res.json({ ok: true, datos: wompi.estadoConfiguracion() });

/** POST /api/pagos/wompi/links  { id_venta, monto? }  (monto por defecto: todo el saldo) */
const wompiCrearLink = asyncHandler(async (req, res) => {
  const idVenta = Number(req.body.id_venta);
  if (!Number.isInteger(idVenta) || idVenta < 1) throw new ErrorHttp(400, "Indica la venta.", { id_venta: "Obligatorio." });

  const venta = await transaccion((db) => saldoVenta(db, idVenta, { bloquear: false }));
  if (esCliente(req)) {
    const { rows: dueno } = await query("SELECT id_cliente FROM ventas WHERE id_venta = $1", [idVenta]);
    if (dueno[0]?.id_cliente !== req.usuario.idCliente) throw new ErrorHttp(404, "No existe esa venta.");
  }
  if (venta.estado === "anulada") throw new ErrorHttp(409, "La venta está anulada.");
  if (venta.saldo <= 0) throw new ErrorHttp(409, `La venta ${venta.numero_factura} ya está pagada.`);

  const monto = req.body.monto ? Number(req.body.monto) : venta.saldo;
  if (!(monto > 0) || monto > venta.saldo) {
    throw new ErrorHttp(400, `El monto debe estar entre $1 y el saldo ($${venta.saldo.toLocaleString("es-CO")}).`);
  }

  const { rows: c } = await query(
    "SELECT c.nombre FROM ventas v JOIN clientes c ON c.id_cliente = v.id_cliente WHERE v.id_venta = $1",
    [idVenta]
  );
  const link = await wompi.crearLink({ venta, cliente: c[0].nombre, monto });
  const { rows } = await query(
    `INSERT INTO wompi_links (id_link, id_venta, monto, url, expira_en) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [link.id, idVenta, monto, link.url, link.expira]
  );
  res.status(201).json({ ok: true, mensaje: "Link de pago creado. Compártelo con el cliente.", datos: rows[0] });
});

/**
 * POST /api/pagos/wompi/verificar  { id_transaccion }
 * Plan B cuando el webhook no llegó: se consulta la transacción en Wompi.
 */
const wompiVerificar = asyncHandler(async (req, res) => {
  const id = String(req.body.id_transaccion ?? "").trim();
  if (!id) throw new ErrorHttp(400, "Escribe el id de la transacción de Wompi.", { id_transaccion: "Obligatorio." });
  const tx = await wompi.consultarTransaccion(id);
  const r = await wompi.aplicarTransaccion(tx);
  const mensajes = {
    registrado: "Pago confirmado y abonado a la venta.",
    ya_registrado: "Ese pago ya estaba registrado.",
    no_aprobada: `La transacción está en estado ${tx.status}; no se registró ningún abono.`,
    link_desconocido: "Esa transacción no corresponde a ningún link de pago de esta app.",
    venta_anulada: "El pago entró pero la venta está anulada: hay que devolver el dinero."
  };
  const ok = ["registrado", "ya_registrado"].includes(r.resultado);
  res.status(ok ? 200 : 409).json({ ok, mensaje: mensajes[r.resultado], error: ok ? undefined : mensajes[r.resultado], datos: r });
});

/**
 * POST /api/webhooks/wompi — lo llama Wompi, no la app. Público, pero cada
 * evento trae una firma que solo puede generar quien conoce el secreto.
 */
const wompiWebhook = asyncHandler(async (req, res) => {
  const evento = req.body;
  if (!wompi.firmaValida(evento)) {
    return res.status(401).json({ ok: false, error: "Firma inválida." });
  }
  if (evento.event !== "transaction.updated") return res.json({ ok: true, ignorado: evento.event });

  const r = await wompi.aplicarTransaccion(evento.data?.transaction);
  // Siempre 200 cuando la firma es buena: si se responde otra cosa, Wompi
  // reintenta el mismo evento hasta 3 veces aunque no haya nada que hacer.
  res.json({ ok: true, ...r });
});

export default { listar, registrar, anular, pendientes, wompiEstado, wompiCrearLink, wompiVerificar, wompiWebhook };
