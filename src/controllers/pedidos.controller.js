import modelo from "../models/pedidos.model.js";
import ventas from "../models/ventas.model.js";
import { transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";
import { esCliente } from "../middlewares/auth.js";
import {
  CANALES,
  redondear,
  normalizarItems,
  clienteActivo,
  revisarProductos,
  registrarVenta,
  validarMetodoVenta,
  saldoVenta,
  insertarPago
} from "../services/ventas.service.js";
import { query } from "../db/pool.js";
import { correos } from "../services/correo.service.js";
import { leerImagenBase64 } from "../utils/imagen.js";

/**
 * Items que manda un Cliente: el precio lo pone el catálogo, nunca la app
 * (si no, alguien podría pedir un perfume de $300.000 a $1).
 */
const sinPrecio = (items) =>
  Array.isArray(items) ? items.map(({ id_producto, cantidad }) => ({ id_producto, cantidad })) : items;

/** Guarda (o reemplaza) la foto del comprobante del pedido. */
async function guardarComprobantePedido(db, idPedido, comprobante) {
  const { bytes, tipo } = leerImagenBase64(comprobante);
  await db.query(
    `INSERT INTO pedido_comprobante (id_pedido, contenido, tipo_mime) VALUES ($1, $2, $3)
     ON CONFLICT (id_pedido) DO UPDATE SET contenido = EXCLUDED.contenido, tipo_mime = EXCLUDED.tipo_mime,
                                           subido_en = CURRENT_TIMESTAMP`,
    [idPedido, bytes, tipo]
  );
}

const faltaComprobante = () =>
  new ErrorHttp(400, "Si pagas por transferencia, adjunta la foto del comprobante.", {
    comprobante: "Obligatorio para pagar por transferencia."
  });

/**
 * Controlador de Pedidos.
 *
 * Un pedido es temporal: registra lo que el cliente pidió (por WhatsApp o en
 * el local) pero NO mueve stock. Mientras está "pendiente" se puede editar o
 * cancelar. Al "convertirlo" se vuelve una venta confirmada y ahí sí se
 * descuenta el stock y se genera la factura.
 */

/** Escribe el detalle y recalcula el total. Se usa al crear y al editar. */
async function guardarDetalle(db, idPedido, items) {
  await db.query("DELETE FROM detalle_pedido WHERE id_pedido = $1", [idPedido]);
  for (const item of items) {
    await db.query(
      "INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario) VALUES ($1, $2, $3, $4)",
      [idPedido, item.id_producto, item.cantidad, item.precio_unitario]
    );
  }
  const total = redondear(items.reduce((s, i) => s + i.cantidad * i.precio_unitario, 0));
  await db.query("UPDATE pedidos SET total = $2, actualizado_en = CURRENT_TIMESTAMP WHERE id_pedido = $1", [idPedido, total]);
}

/**
 * Cómo va a pagar el pedido. El Cliente escoge entre Wompi (en línea),
 * transferencia (reporta el pago con comprobante) o efectivo en el punto
 * físico; es obligatorio para él. El equipo puede dejarlo para después.
 */
const METODOS_CLIENTE = ["wompi", "transferencia", "efectivo"];
function validarMetodoPedido(req, metodo, { obligatorio }) {
  if (esCliente(req)) {
    if ((metodo === undefined || metodo === null || metodo === "") && !obligatorio) return null;
    if (!METODOS_CLIENTE.includes(metodo)) {
      throw new ErrorHttp(400, "Elige cómo vas a pagar: Wompi, transferencia o efectivo en el punto físico.", {
        metodo_pago: METODOS_CLIENTE.join(", ")
      });
    }
    return metodo;
  }
  return validarMetodoVenta(metodo, { obligatorio: false });
}

function validarCanal(canal) {
  if (canal !== undefined && !CANALES.includes(canal)) {
    throw new ErrorHttp(400, "Canal no válido.", { canal: CANALES.join(", ") });
  }
}

/**
 * Trae el pedido bloqueado y exige que siga pendiente. Si quien pide es un
 * Cliente, además tiene que ser suyo: si no, se responde 404 (no se le dice
 * que el pedido existe).
 */
async function pedidoPendiente(db, id, req) {
  const { rows } = await db.query("SELECT * FROM pedidos WHERE id_pedido = $1 FOR UPDATE", [id]);
  if (!rows[0] || (esCliente(req) && rows[0].id_cliente !== req.usuario.idCliente)) {
    throw new ErrorHttp(404, "No existe un pedido con ese id.");
  }
  if (rows[0].estado !== "pendiente") {
    throw new ErrorHttp(409, `El pedido ${rows[0].codigo} ya está ${rows[0].estado}; solo se modifican pedidos pendientes.`);
  }
  return rows[0];
}

/** GET /api/pedidos */
const listar = asyncHandler(async (req, res) => {
  // Un Cliente solo ve sus pedidos, mande el filtro que mande.
  const filtros = esCliente(req) ? { ...req.query, id_cliente: req.usuario.idCliente } : req.query;
  const { filas, total, pagina, porPagina } = await modelo.listar(filtros);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/pedidos/:id */
const obtener = asyncHandler(async (req, res) => {
  const pedido = await modelo.obtenerPorId(req.idNumerico);
  if (!pedido || (esCliente(req) && pedido.id_cliente !== req.usuario.idCliente)) {
    throw new ErrorHttp(404, "No existe un pedido con ese id.");
  }
  res.json({ ok: true, datos: pedido });
});

/**
 * POST /api/pedidos
 * { id_cliente, canal, items, metodo_pago, direccion_entrega?, notas?,
 *   comprobante?: { base64, tipo_mime }, referencia_pago? }
 *
 * Si un Cliente escoge transferencia, el comprobante es OBLIGATORIO.
 */
const crear = asyncHandler(async (req, res) => {
  // El Cliente pide para sí mismo y por la app; no escoge cliente, canal ni precios.
  const cuerpo = esCliente(req)
    ? { ...req.body, id_cliente: req.usuario.idCliente, canal: "app", items: sinPrecio(req.body.items) }
    : req.body;
  validarCanal(cuerpo.canal);
  const metodoPago = validarMetodoPedido(req, cuerpo.metodo_pago, { obligatorio: true });
  if (esCliente(req) && metodoPago === "transferencia" && !cuerpo.comprobante) throw faltaComprobante();
  const id = await transaccion(async (db) => {
    const cliente = await clienteActivo(db, cuerpo.id_cliente);
    // Se exige stock suficiente al tomar el pedido: prometerle al cliente un
    // producto que no hay es justo el problema que describe la ficha.
    const items = await revisarProductos(db, normalizarItems(cuerpo.items));
    const { rows } = await db.query(
      `INSERT INTO pedidos (id_cliente, canal, direccion_entrega, notas, id_usuario, metodo_pago, referencia_pago)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id_pedido`,
      [
        cliente.id_cliente,
        cuerpo.canal ?? "whatsapp",
        cuerpo.direccion_entrega?.trim() || null,
        cuerpo.notas?.trim() || null,
        req.usuario.id,
        metodoPago,
        String(cuerpo.referencia_pago ?? "").trim().slice(0, 100) || null
      ]
    );
    await guardarDetalle(db, rows[0].id_pedido, items);
    if (cuerpo.comprobante) await guardarComprobantePedido(db, rows[0].id_pedido, cuerpo.comprobante);
    return rows[0].id_pedido;
  });
  const pedido = await modelo.obtenerPorId(id);
  res.status(201).json({ ok: true, mensaje: `Pedido ${pedido.codigo} registrado.`, datos: pedido });
});

/** PUT /api/pedidos/:id — solo pendientes. items, si viene, reemplaza el detalle. */
const actualizar = asyncHandler(async (req, res) => {
  const cuerpo = esCliente(req)
    ? { ...req.body, id_cliente: undefined, canal: undefined, items: sinPrecio(req.body.items) }
    : req.body;
  validarCanal(cuerpo.canal);
  const metodoPago = validarMetodoPedido(req, cuerpo.metodo_pago, { obligatorio: false });
  await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico, req);
    if (cuerpo.comprobante) await guardarComprobantePedido(db, pedido.id_pedido, cuerpo.comprobante);
    // Si el cliente cambia a transferencia, el pedido tiene que quedar con comprobante.
    if (esCliente(req) && (metodoPago ?? pedido.metodo_pago) === "transferencia") {
      const { rows } = await db.query("SELECT 1 FROM pedido_comprobante WHERE id_pedido = $1", [pedido.id_pedido]);
      if (!rows[0]) throw faltaComprobante();
    }
    const idCliente = cuerpo.id_cliente ? (await clienteActivo(db, cuerpo.id_cliente)).id_cliente : pedido.id_cliente;
    await db.query(
      `UPDATE pedidos
          SET id_cliente = $2,
              canal = COALESCE($3, canal),
              direccion_entrega = CASE WHEN $4::BOOLEAN THEN $5 ELSE direccion_entrega END,
              notas = CASE WHEN $6::BOOLEAN THEN $7 ELSE notas END,
              metodo_pago = COALESCE($8, metodo_pago),
              referencia_pago = CASE WHEN $9::BOOLEAN THEN $10 ELSE referencia_pago END,
              actualizado_en = CURRENT_TIMESTAMP
        WHERE id_pedido = $1`,
      [
        pedido.id_pedido,
        idCliente,
        cuerpo.canal ?? null,
        cuerpo.direccion_entrega !== undefined,
        cuerpo.direccion_entrega?.trim() || null,
        cuerpo.notas !== undefined,
        cuerpo.notas?.trim() || null,
        metodoPago,
        cuerpo.referencia_pago !== undefined,
        String(cuerpo.referencia_pago ?? "").trim().slice(0, 100) || null
      ]
    );
    if (cuerpo.items !== undefined) {
      const items = await revisarProductos(db, normalizarItems(cuerpo.items));
      await guardarDetalle(db, pedido.id_pedido, items);
    }
  });
  const pedido = await modelo.obtenerPorId(req.idNumerico);
  res.json({ ok: true, mensaje: `Pedido ${pedido.codigo} actualizado.`, datos: pedido });
});

/** POST /api/pedidos/:id/cancelar */
const cancelar = asyncHandler(async (req, res) => {
  await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico, req);
    const nota = req.body?.motivo ? `Cancelado: ${String(req.body.motivo).trim()}` : null;
    await db.query(
      `UPDATE pedidos SET estado = 'cancelado', actualizado_en = CURRENT_TIMESTAMP,
              notas = CASE WHEN $2::TEXT IS NULL THEN notas ELSE LEFT(COALESCE(notas || ' | ', '') || $2, 250) END
        WHERE id_pedido = $1`,
      [pedido.id_pedido, nota]
    );
  });
  const pedido = await modelo.obtenerPorId(req.idNumerico);
  res.json({ ok: true, mensaje: `Pedido ${pedido.codigo} cancelado.`, datos: pedido });
});

/**
 * POST /api/pedidos/:id/convertir  { metodo_pago?, descuento?, pago_inicial?, notas? }
 * metodo_pago: si no viene, se usa el que escogió el cliente en el pedido.
 *
 * Todo en una transacción: si un producto se agotó, no queda ni la venta a
 * medias ni el pedido marcado como confirmado.
 */
const convertir = asyncHandler(async (req, res) => {
  const idVenta = await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico, req);
    const { rows: items } = await db.query(
      "SELECT id_producto, cantidad, precio_unitario FROM detalle_pedido WHERE id_pedido = $1",
      [pedido.id_pedido]
    );
    const venta = await registrarVenta(db, {
      id_cliente: pedido.id_cliente,
      canal: pedido.canal,
      metodo_pago: req.body?.metodo_pago ?? pedido.metodo_pago ?? req.body?.pago_inicial?.metodo,
      items,
      descuento: req.body?.descuento,
      notas: req.body?.notas ?? pedido.notas,
      pago_inicial: req.body?.pago_inicial,
      id_pedido: pedido.id_pedido,
      id_usuario: req.usuario.id
    });
    await db.query(
      "UPDATE pedidos SET estado = 'confirmado', id_venta = $2, actualizado_en = CURRENT_TIMESTAMP WHERE id_pedido = $1",
      [pedido.id_pedido, venta.id_venta]
    );

    // El cliente ya transfirió y mandó el comprobante con el pedido: pasa a
    // Pagos ▸ Por aprobar como un pago del cliente, por lo que quede debiendo.
    const { rows: comp } = await db.query("SELECT contenido, tipo_mime FROM pedido_comprobante WHERE id_pedido = $1", [
      pedido.id_pedido
    ]);
    if (comp[0]) {
      const saldo = await saldoVenta(db, venta.id_venta, { bloquear: false });
      if (saldo.saldo > 0) {
        const pago = await insertarPago(db, {
          id_venta: venta.id_venta,
          monto: saldo.saldo,
          metodo: "transferencia",
          referencia: pedido.referencia_pago,
          nota: `Comprobante enviado con el pedido ${pedido.codigo}`,
          id_usuario: pedido.id_usuario,
          estado: "pendiente"
        });
        await db.query("INSERT INTO pago_comprobante (id_pago, contenido, tipo_mime) VALUES ($1, $2, $3)", [
          pago.id_pago,
          comp[0].contenido,
          comp[0].tipo_mime
        ]);
      }
    }
    return venta.id_venta;
  });
  const venta = await ventas.obtenerPorId(idVenta);

  // Si el pedido lo hizo el cliente por la app, le avisamos que ya puede pagar.
  const { rows: u } = await query(
    `SELECT u.correo, u.nombre FROM usuarios u WHERE u.id_cliente = $1 AND u.estado`,
    [venta.id_cliente]
  );
  if (u[0] && venta.canal === "app") {
    await correos.pedidoConfirmado(u[0].correo, {
      nombre: u[0].nombre,
      pedido: venta.pedido_codigo,
      factura: venta.numero_factura,
      total: venta.total,
      metodo: venta.metodo_pago,
      conComprobante: venta.pagos?.some((p) => p.estado === "pendiente") ?? false
    });
  }

  res.status(201).json({
    ok: true,
    mensaje: `Pedido convertido en la venta ${venta.numero_factura}.`,
    datos: venta
  });
});

/** El pedido si quien pregunta puede verlo (el Cliente, solo los suyos). */
async function pedidoVisible(req) {
  const { rows } = await query("SELECT id_pedido, id_cliente, estado FROM pedidos WHERE id_pedido = $1", [req.idNumerico]);
  if (!rows[0] || (esCliente(req) && rows[0].id_cliente !== req.usuario.idCliente)) {
    throw new ErrorHttp(404, "No existe un pedido con ese id.");
  }
  return rows[0];
}

/** GET /api/pedidos/:id/comprobante — imagen privada (exige sesión). */
const verComprobante = asyncHandler(async (req, res) => {
  await pedidoVisible(req);
  const { rows } = await query("SELECT contenido, tipo_mime FROM pedido_comprobante WHERE id_pedido = $1", [req.idNumerico]);
  if (!rows[0]) throw new ErrorHttp(404, "Ese pedido no tiene comprobante.");
  res.set("Content-Type", rows[0].tipo_mime);
  res.set("Cache-Control", "private, max-age=3600");
  res.send(rows[0].contenido);
});

/** PUT /api/pedidos/:id/comprobante  { base64, tipo_mime } — solo mientras está pendiente. */
const subirComprobante = asyncHandler(async (req, res) => {
  const pedido = await pedidoVisible(req);
  if (pedido.estado !== "pendiente") throw new ErrorHttp(409, "El pedido ya no está pendiente; no se cambia el comprobante.");
  await transaccion((db) => guardarComprobantePedido(db, pedido.id_pedido, req.body));
  res.json({ ok: true, mensaje: "Comprobante guardado.", datos: { id_pedido: pedido.id_pedido } });
});

export default { listar, obtener, crear, actualizar, cancelar, convertir, verComprobante, subirComprobante };
