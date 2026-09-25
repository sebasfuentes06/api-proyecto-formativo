import { query, transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { paginacion, respuestaListado } from "../utils/consulta.js";
import { validarPago, insertarPago, saldoVenta, METODOS_REPORTE, redondear } from "../services/ventas.service.js";
import * as wompi from "../services/wompi.service.js";
import { esCliente } from "../middlewares/auth.js";
import { correos } from "../services/correo.service.js";
import { leerImagenBase64 } from "../utils/imagen.js";
import { env } from "../config/env.js";

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
  if (["aplicado", "anulado", "pendiente", "rechazado"].includes(f.estado)) agregar("p.estado = ?", f.estado);
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
    `SELECT p.*, v.numero_factura, v.id_cliente, c.nombre AS cliente, c.telefono AS cliente_telefono,
            EXISTS (SELECT 1 FROM pago_comprobante pc WHERE pc.id_pago = p.id_pago) AS tiene_comprobante
       ${desde}
      ORDER BY (p.estado = 'pendiente') DESC, p.fecha DESC, p.id_pago DESC
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );
  res.json({ ...respuestaListado(rows, t[0].total, { pagina, porPagina }), resumen: { recaudado: t[0].recaudado } });
});

/** Guarda (o reemplaza) el comprobante de un pago dentro de la transacción. */
async function guardarComprobante(db, idPago, comprobante) {
  const { bytes, tipo } = leerImagenBase64(comprobante);
  await db.query(
    `INSERT INTO pago_comprobante (id_pago, contenido, tipo_mime) VALUES ($1, $2, $3)
     ON CONFLICT (id_pago) DO UPDATE SET contenido = EXCLUDED.contenido, tipo_mime = EXCLUDED.tipo_mime,
                                         subido_en = CURRENT_TIMESTAMP`,
    [idPago, bytes, tipo]
  );
}

/** Suma de lo que el cliente ya reportó y sigue esperando revisión. */
async function reportadoPendiente(db, idVenta) {
  const { rows } = await db.query(
    "SELECT COALESCE(SUM(monto), 0) AS total FROM pagos WHERE id_venta = $1 AND estado = 'pendiente'",
    [idVenta]
  );
  return Number(rows[0].total);
}

/**
 * POST /api/pagos  { id_venta, monto, metodo, referencia?, nota?, comprobante?: { base64, tipo_mime } }
 *
 * - Administrador / Vendedor: el pago queda APLICADO de una vez (abono o pago total).
 * - Cliente: es un REPORTE ("ya te transferí"). Queda PENDIENTE hasta que el
 *   Administrador lo apruebe; mientras tanto no baja el saldo.
 */
const registrar = asyncHandler(async (req, res) => {
  const idVenta = Number(req.body.id_venta);
  if (!Number.isInteger(idVenta) || idVenta < 1) throw new ErrorHttp(400, "Indica la venta.", { id_venta: "Obligatorio." });
  const reporte = esCliente(req);
  if (reporte && !METODOS_REPORTE.includes(req.body.metodo)) {
    throw new ErrorHttp(400, "Desde la app puedes reportar pagos por transferencia, Nequi o Daviplata.", {
      metodo: METODOS_REPORTE.join(", ")
    });
  }
  if (reporte && !req.body.comprobante && !String(req.body.referencia ?? "").trim()) {
    throw new ErrorHttp(400, "Adjunta el comprobante o escribe el número de la transacción.", {
      comprobante: "Obligatorio si no hay referencia."
    });
  }

  const { pago, venta } = await transaccion(async (db) => {
    const venta = await saldoVenta(db, idVenta);
    if (reporte) {
      const { rows } = await db.query("SELECT id_cliente FROM ventas WHERE id_venta = $1", [idVenta]);
      if (rows[0].id_cliente !== req.usuario.idCliente) throw new ErrorHttp(404, "No existe esa venta.");
    }
    if (venta.estado === "anulada") throw new ErrorHttp(409, "No se pueden registrar pagos en una venta anulada.");
    if (venta.saldo <= 0) throw new ErrorHttp(409, `La venta ${venta.numero_factura} ya está pagada.`);

    // Un cliente no puede reportar más de lo que debe, contando lo que ya
    // reportó y está por revisar.
    const maximo = reporte ? redondear(venta.saldo - (await reportadoPendiente(db, idVenta))) : venta.saldo;
    if (reporte && maximo <= 0) {
      throw new ErrorHttp(409, "Ya reportaste pagos por todo el saldo. Espera a que la administradora los revise.");
    }
    const monto = validarPago(req.body, { maximo });
    const pago = await insertarPago(db, {
      ...req.body,
      id_venta: idVenta,
      monto,
      id_usuario: req.usuario.id,
      estado: reporte ? "pendiente" : "aplicado"
    });
    if (req.body.comprobante) await guardarComprobante(db, pago.id_pago, req.body.comprobante);
    return { pago, venta: await saldoVenta(db, idVenta, { bloquear: false }) };
  });

  if (reporte) {
    const { rows: admins } = await query("SELECT correo FROM usuarios WHERE rol = 'Administrador' AND estado");
    const { rows: c } = await query("SELECT nombre FROM clientes WHERE id_cliente = $1", [req.usuario.idCliente]);
    for (const a of admins) {
      await correos.pagoReportado(a.correo, {
        cliente: c[0]?.nombre ?? req.usuario.nombre,
        factura: venta.numero_factura,
        monto: pago.monto,
        metodo: pago.metodo,
        referencia: pago.referencia
      });
    }
    return res.status(201).json({
      ok: true,
      mensaje: "Pago reportado. La administradora lo revisará y te llegará un correo cuando lo apruebe.",
      datos: { pago, venta }
    });
  }

  const tipo = venta.saldo <= 0 ? "Pago completo" : "Abono";
  res.status(201).json({
    ok: true,
    mensaje: `${tipo} registrado en ${venta.numero_factura}. Saldo: $${venta.saldo.toLocaleString("es-CO")}.`,
    datos: { pago, venta }
  });
});

/** Trae el pago reportado (bloqueado) y exige que siga pendiente. */
async function pagoPendiente(db, idPago) {
  const { rows } = await db.query("SELECT * FROM pagos WHERE id_pago = $1 FOR UPDATE", [idPago]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe ese pago.");
  if (rows[0].estado !== "pendiente") throw new ErrorHttp(409, `Ese pago ya fue revisado (${rows[0].estado}).`);
  return rows[0];
}

/** A quién avisarle del resultado: el usuario que reportó el pago. */
async function avisarRevision(pago, venta, { aprobado, motivo }) {
  const { rows } = await query("SELECT correo, nombre FROM usuarios WHERE id_usuario = $1", [pago.id_usuario]);
  if (!rows[0]) return;
  await correos.pagoRevisado(rows[0].correo, {
    nombre: rows[0].nombre,
    factura: venta.numero_factura,
    monto: pago.monto,
    aprobado,
    motivo,
    saldo: venta.saldo
  });
}

/** POST /api/pagos/:id/aprobar — el Administrador confirma que el dinero llegó. */
const aprobar = asyncHandler(async (req, res) => {
  const { pago, venta } = await transaccion(async (db) => {
    const { rows: v } = await db.query("SELECT id_venta FROM pagos WHERE id_pago = $1", [req.idNumerico]);
    if (!v[0]) throw new ErrorHttp(404, "No existe ese pago.");
    // Primero la venta y después el pago: el mismo orden que usa registrar.
    const antes = await saldoVenta(db, v[0].id_venta);
    const pago = await pagoPendiente(db, req.idNumerico);
    if (antes.estado === "anulada") throw new ErrorHttp(409, "La venta está anulada: rechaza este pago.");
    if (Number(pago.monto) > antes.saldo + 0.001) {
      throw new ErrorHttp(
        409,
        `El pago ($${Number(pago.monto).toLocaleString("es-CO")}) supera el saldo actual ($${antes.saldo.toLocaleString("es-CO")}). Recházalo y pídele al cliente que reporte el valor correcto.`
      );
    }
    const { rows } = await db.query(
      `UPDATE pagos SET estado = 'aplicado', revisado_por = $2, revisado_en = CURRENT_TIMESTAMP
        WHERE id_pago = $1 RETURNING *`,
      [pago.id_pago, req.usuario.id]
    );
    return { pago: rows[0], venta: await saldoVenta(db, pago.id_venta, { bloquear: false }) };
  });
  await avisarRevision(pago, venta, { aprobado: true });
  res.json({
    ok: true,
    mensaje: `Pago aprobado en ${venta.numero_factura}. Saldo: $${venta.saldo.toLocaleString("es-CO")}.`,
    datos: { pago, venta }
  });
});

/** POST /api/pagos/:id/rechazar  { motivo } */
const rechazar = asyncHandler(async (req, res) => {
  const motivo = String(req.body?.motivo ?? "").trim();
  if (motivo.length < 3) throw new ErrorHttp(400, "Escribe el motivo del rechazo.", { motivo: "Obligatorio." });
  const { pago, venta } = await transaccion(async (db) => {
    const pago = await pagoPendiente(db, req.idNumerico);
    const { rows } = await db.query(
      `UPDATE pagos SET estado = 'rechazado', motivo_rechazo = LEFT($3, 250), revisado_por = $2,
              revisado_en = CURRENT_TIMESTAMP
        WHERE id_pago = $1 RETURNING *`,
      [pago.id_pago, req.usuario.id, motivo]
    );
    return { pago: rows[0], venta: await saldoVenta(db, pago.id_venta, { bloquear: false }) };
  });
  await avisarRevision(pago, venta, { aprobado: false, motivo });
  res.json({ ok: true, mensaje: "Pago rechazado. Le avisamos al cliente por correo.", datos: { pago, venta } });
});

/** El pago, si quien pregunta puede verlo (el Cliente solo los suyos). */
async function pagoVisible(req) {
  const { rows } = await query(
    "SELECT p.*, v.id_cliente FROM pagos p JOIN ventas v ON v.id_venta = p.id_venta WHERE p.id_pago = $1",
    [req.idNumerico]
  );
  if (!rows[0] || (esCliente(req) && rows[0].id_cliente !== req.usuario.idCliente)) {
    throw new ErrorHttp(404, "No existe ese pago.");
  }
  return rows[0];
}

/** GET /api/pagos/:id/comprobante — la imagen. Requiere sesión (es un dato privado). */
const verComprobante = asyncHandler(async (req, res) => {
  await pagoVisible(req);
  const { rows } = await query("SELECT contenido, tipo_mime FROM pago_comprobante WHERE id_pago = $1", [req.idNumerico]);
  if (!rows[0]) throw new ErrorHttp(404, "Ese pago no tiene comprobante.");
  res.set("Content-Type", rows[0].tipo_mime);
  res.set("Cache-Control", "private, max-age=3600");
  res.send(rows[0].contenido);
});

/**
 * PUT /api/pagos/:id/comprobante  { base64, tipo_mime }
 * El equipo puede adjuntarlo a cualquier pago; el Cliente, solo a sus pagos
 * que siguen pendientes (después de revisado ya no se cambia).
 */
const subirComprobante = asyncHandler(async (req, res) => {
  const pago = await pagoVisible(req);
  if (esCliente(req) && pago.estado !== "pendiente") {
    throw new ErrorHttp(409, "Ese pago ya fue revisado; no se puede cambiar el comprobante.");
  }
  await transaccion((db) => guardarComprobante(db, pago.id_pago, req.body));
  res.json({ ok: true, mensaje: "Comprobante guardado.", datos: { id_pago: pago.id_pago } });
});

/**
 * GET /api/pagos/datos-pago — lo que la app le muestra al cliente para pagar:
 * a qué cuenta transferir y dónde queda el punto físico (se configuran en
 * Vercel, así se cambian sin publicar otra versión de la app).
 */
const datosPago = (_req, res) =>
  res.json({
    ok: true,
    datos: {
      transferencia: env.pagos.transferencia,
      punto_fisico: env.pagos.puntoFisico,
      wompi: wompi.estadoConfiguracion().links
    }
  });

/** POST /api/pagos/:id/anular  { motivo } */
const anular = asyncHandler(async (req, res) => {
  const motivo = String(req.body?.motivo ?? "").trim();
  if (motivo.length < 3) throw new ErrorHttp(400, "Escribe el motivo de la anulación.", { motivo: "Obligatorio." });

  const venta = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM pagos WHERE id_pago = $1 FOR UPDATE", [req.idNumerico]);
    if (!rows[0]) throw new ErrorHttp(404, "No existe ese pago.");
    if (rows[0].estado === "anulado") throw new ErrorHttp(409, "Ese pago ya estaba anulado.");
    if (rows[0].estado !== "aplicado") {
      throw new ErrorHttp(409, "Ese pago es un reporte del cliente: apruébalo o recházalo en lugar de anularlo.");
    }
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

export default {
  listar,
  registrar,
  aprobar,
  rechazar,
  verComprobante,
  subirComprobante,
  datosPago,
  anular,
  pendientes,
  wompiEstado,
  wompiCrearLink,
  wompiVerificar,
  wompiWebhook
};
