import modelo from "../models/pedidos.model.js";
import ventas from "../models/ventas.model.js";
import { transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";
import {
  CANALES,
  redondear,
  normalizarItems,
  clienteActivo,
  revisarProductos,
  registrarVenta
} from "../services/ventas.service.js";

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

function validarCanal(canal) {
  if (canal !== undefined && !CANALES.includes(canal)) {
    throw new ErrorHttp(400, "Canal no válido.", { canal: "whatsapp o punto_fisico" });
  }
}

/** Trae el pedido bloqueado y exige que siga pendiente. */
async function pedidoPendiente(db, id) {
  const { rows } = await db.query("SELECT * FROM pedidos WHERE id_pedido = $1 FOR UPDATE", [id]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe un pedido con ese id.");
  if (rows[0].estado !== "pendiente") {
    throw new ErrorHttp(409, `El pedido ${rows[0].codigo} ya está ${rows[0].estado}; solo se modifican pedidos pendientes.`);
  }
  return rows[0];
}

/** GET /api/pedidos */
const listar = asyncHandler(async (req, res) => {
  const { filas, total, pagina, porPagina } = await modelo.listar(req.query);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/pedidos/:id */
const obtener = asyncHandler(async (req, res) => {
  const pedido = await modelo.obtenerPorId(req.idNumerico);
  if (!pedido) throw new ErrorHttp(404, "No existe un pedido con ese id.");
  res.json({ ok: true, datos: pedido });
});

/** POST /api/pedidos  { id_cliente, canal, items, direccion_entrega?, notas? } */
const crear = asyncHandler(async (req, res) => {
  validarCanal(req.body.canal);
  const id = await transaccion(async (db) => {
    const cliente = await clienteActivo(db, req.body.id_cliente);
    // Se exige stock suficiente al tomar el pedido: prometerle al cliente un
    // producto que no hay es justo el problema que describe la ficha.
    const items = await revisarProductos(db, normalizarItems(req.body.items));
    const { rows } = await db.query(
      `INSERT INTO pedidos (id_cliente, canal, direccion_entrega, notas, id_usuario)
       VALUES ($1, $2, $3, $4, $5) RETURNING id_pedido`,
      [cliente.id_cliente, req.body.canal ?? "whatsapp", req.body.direccion_entrega?.trim() || null, req.body.notas?.trim() || null, req.usuario.id]
    );
    await guardarDetalle(db, rows[0].id_pedido, items);
    return rows[0].id_pedido;
  });
  const pedido = await modelo.obtenerPorId(id);
  res.status(201).json({ ok: true, mensaje: `Pedido ${pedido.codigo} registrado.`, datos: pedido });
});

/** PUT /api/pedidos/:id — solo pendientes. items, si viene, reemplaza el detalle. */
const actualizar = asyncHandler(async (req, res) => {
  validarCanal(req.body.canal);
  await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico);
    const idCliente = req.body.id_cliente ? (await clienteActivo(db, req.body.id_cliente)).id_cliente : pedido.id_cliente;
    await db.query(
      `UPDATE pedidos
          SET id_cliente = $2,
              canal = COALESCE($3, canal),
              direccion_entrega = CASE WHEN $4::BOOLEAN THEN $5 ELSE direccion_entrega END,
              notas = CASE WHEN $6::BOOLEAN THEN $7 ELSE notas END,
              actualizado_en = CURRENT_TIMESTAMP
        WHERE id_pedido = $1`,
      [
        pedido.id_pedido,
        idCliente,
        req.body.canal ?? null,
        req.body.direccion_entrega !== undefined,
        req.body.direccion_entrega?.trim() || null,
        req.body.notas !== undefined,
        req.body.notas?.trim() || null
      ]
    );
    if (req.body.items !== undefined) {
      const items = await revisarProductos(db, normalizarItems(req.body.items));
      await guardarDetalle(db, pedido.id_pedido, items);
    }
  });
  const pedido = await modelo.obtenerPorId(req.idNumerico);
  res.json({ ok: true, mensaje: `Pedido ${pedido.codigo} actualizado.`, datos: pedido });
});

/** POST /api/pedidos/:id/cancelar */
const cancelar = asyncHandler(async (req, res) => {
  await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico);
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
 * POST /api/pedidos/:id/convertir  { descuento?, pago_inicial?, notas? }
 *
 * Todo en una transacción: si un producto se agotó, no queda ni la venta a
 * medias ni el pedido marcado como confirmado.
 */
const convertir = asyncHandler(async (req, res) => {
  const idVenta = await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico);
    const { rows: items } = await db.query(
      "SELECT id_producto, cantidad, precio_unitario FROM detalle_pedido WHERE id_pedido = $1",
      [pedido.id_pedido]
    );
    const venta = await registrarVenta(db, {
      id_cliente: pedido.id_cliente,
      canal: pedido.canal,
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
    return venta.id_venta;
  });
  const venta = await ventas.obtenerPorId(idVenta);
  res.status(201).json({
    ok: true,
    mensaje: `Pedido convertido en la venta ${venta.numero_factura}.`,
    datos: venta
  });
});

export default { listar, obtener, crear, actualizar, cancelar, convertir };
