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
  validarMetodoVenta
} from "../services/ventas.service.js";
import { query } from "../db/pool.js";
import { correos } from "../services/correo.service.js";

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

/** POST /api/pedidos  { id_cliente, canal, items, direccion_entrega?, notas? } */
const crear = asyncHandler(async (req, res) => {
  // El Cliente pide para sí mismo y por la app; no escoge cliente ni canal.
  const cuerpo = esCliente(req) ? { ...req.body, id_cliente: req.usuario.idCliente, canal: "app" } : req.body;
  validarCanal(cuerpo.canal);
  const metodoPago = validarMetodoPedido(req, cuerpo.metodo_pago, { obligatorio: true });
  const id = await transaccion(async (db) => {
    const cliente = await clienteActivo(db, cuerpo.id_cliente);
    // Se exige stock suficiente al tomar el pedido: prometerle al cliente un
    // producto que no hay es justo el problema que describe la ficha.
    const items = await revisarProductos(db, normalizarItems(cuerpo.items));
    const { rows } = await db.query(
      `INSERT INTO pedidos (id_cliente, canal, direccion_entrega, notas, id_usuario, metodo_pago)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id_pedido`,
      [
        cliente.id_cliente,
        cuerpo.canal ?? "whatsapp",
        cuerpo.direccion_entrega?.trim() || null,
        cuerpo.notas?.trim() || null,
        req.usuario.id,
        metodoPago
      ]
    );
    await guardarDetalle(db, rows[0].id_pedido, items);
    return rows[0].id_pedido;
  });
  const pedido = await modelo.obtenerPorId(id);
  res.status(201).json({ ok: true, mensaje: `Pedido ${pedido.codigo} registrado.`, datos: pedido });
});

/** PUT /api/pedidos/:id — solo pendientes. items, si viene, reemplaza el detalle. */
const actualizar = asyncHandler(async (req, res) => {
  const cuerpo = esCliente(req) ? { ...req.body, id_cliente: undefined, canal: undefined } : req.body;
  validarCanal(cuerpo.canal);
  const metodoPago = validarMetodoPedido(req, cuerpo.metodo_pago, { obligatorio: false });
  await transaccion(async (db) => {
    const pedido = await pedidoPendiente(db, req.idNumerico, req);
    const idCliente = cuerpo.id_cliente ? (await clienteActivo(db, cuerpo.id_cliente)).id_cliente : pedido.id_cliente;
    await db.query(
      `UPDATE pedidos
          SET id_cliente = $2,
              canal = COALESCE($3, canal),
              direccion_entrega = CASE WHEN $4::BOOLEAN THEN $5 ELSE direccion_entrega END,
              notas = CASE WHEN $6::BOOLEAN THEN $7 ELSE notas END,
              metodo_pago = COALESCE($8, metodo_pago),
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
        metodoPago
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
      metodo: venta.metodo_pago
    });
  }

  res.status(201).json({
    ok: true,
    mensaje: `Pedido convertido en la venta ${venta.numero_factura}.`,
    datos: venta
  });
});

export default { listar, obtener, crear, actualizar, cancelar, convertir };
