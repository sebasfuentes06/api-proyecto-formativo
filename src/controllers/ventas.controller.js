import modelo from "../models/ventas.model.js";
import { transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";
import { registrarVenta } from "../services/ventas.service.js";
import { esCliente } from "../middlewares/auth.js";

/** Controlador de Ventas. */

/** GET /api/ventas */
const listar = asyncHandler(async (req, res) => {
  // El Cliente solo ve sus compras.
  const filtros = esCliente(req) ? { ...req.query, id_cliente: req.usuario.idCliente } : req.query;
  const { filas, total, resumen, pagina, porPagina } = await modelo.listar(filtros);
  res.json({ ...respuestaListado(filas, total, { pagina, porPagina }), resumen });
});

/** GET /api/ventas/:id */
const obtener = asyncHandler(async (req, res) => {
  const venta = await modelo.obtenerPorId(req.idNumerico);
  if (!venta || (esCliente(req) && venta.id_cliente !== req.usuario.idCliente)) {
    throw new ErrorHttp(404, "No existe una venta con ese id.");
  }
  res.json({ ok: true, datos: venta });
});

/**
 * POST /api/ventas
 * { id_cliente, canal, items: [{ id_producto, cantidad, precio_unitario? }],
 *   descuento?, notas?, pago_inicial?: { monto, metodo, referencia? } }
 */
const crear = asyncHandler(async (req, res) => {
  const { id_venta } = await transaccion((db) =>
    registrarVenta(db, { ...req.body, id_pedido: null, id_usuario: req.usuario.id })
  );
  const venta = await modelo.obtenerPorId(id_venta);
  res.status(201).json({ ok: true, mensaje: `Venta ${venta.numero_factura} registrada.`, datos: venta });
});

/**
 * POST /api/ventas/:id/anular  { motivo }
 *
 * Una venta no se borra ni se edita: se anula. Anular devuelve el stock y
 * anula los pagos que tenía (el dinero se le devuelve al cliente). Queda el
 * registro con su motivo, que es lo que pide cualquier auditoría.
 */
const anular = asyncHandler(async (req, res) => {
  const motivo = String(req.body.motivo ?? "").trim();
  if (motivo.length < 3) throw new ErrorHttp(400, "Escribe el motivo de la anulación.", { motivo: "Obligatorio." });

  const resultado = await transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM ventas WHERE id_venta = $1 FOR UPDATE", [req.idNumerico]);
    const venta = rows[0];
    if (!venta) throw new ErrorHttp(404, "No existe una venta con ese id.");
    if (venta.estado === "anulada") throw new ErrorHttp(409, "Esta venta ya estaba anulada.");

    const { rows: items } = await db.query(
      "SELECT id_producto, cantidad FROM detalle_venta WHERE id_venta = $1 ORDER BY id_producto",
      [venta.id_venta]
    );
    for (const item of items) {
      await db.query("UPDATE productos SET stock = stock + $2 WHERE id_producto = $1", [item.id_producto, item.cantidad]);
    }

    const { rows: pagos } = await db.query(
      `UPDATE pagos SET estado = 'anulado', anulado_en = CURRENT_TIMESTAMP,
              nota = COALESCE(nota || ' | ', '') || 'Anulado con la venta'
        WHERE id_venta = $1 AND estado = 'aplicado'
        RETURNING monto`,
      [venta.id_venta]
    );
    await db.query("UPDATE wompi_links SET estado = 'anulado' WHERE id_venta = $1 AND estado = 'activo'", [venta.id_venta]);
    // Pagos que un cliente reportó y nadie había revisado: ya no aplican.
    await db.query(
      `UPDATE pagos SET estado = 'rechazado', revisado_en = CURRENT_TIMESTAMP, motivo_rechazo = 'La venta fue anulada'
        WHERE id_venta = $1 AND estado = 'pendiente'`,
      [venta.id_venta]
    );

    await db.query(
      `UPDATE ventas SET estado = 'anulada', motivo_anulacion = $2, anulada_en = CURRENT_TIMESTAMP WHERE id_venta = $1`,
      [venta.id_venta, motivo]
    );

    // Si la venta salió de un pedido, el pedido vuelve a quedar cancelado:
    // no tiene sentido que diga "confirmado" apuntando a una venta anulada.
    if (venta.id_pedido) {
      await db.query("UPDATE pedidos SET estado = 'cancelado', actualizado_en = CURRENT_TIMESTAMP WHERE id_pedido = $1", [
        venta.id_pedido
      ]);
    }

    return { reembolso: pagos.reduce((s, p) => s + Number(p.monto), 0), pagosAnulados: pagos.length };
  });

  const venta = await modelo.obtenerPorId(req.idNumerico);
  const extra = resultado.pagosAnulados
    ? ` Se anularon ${resultado.pagosAnulados} pago(s): devuelve $${resultado.reembolso.toLocaleString("es-CO")} al cliente.`
    : "";
  res.json({ ok: true, mensaje: `Venta ${venta.numero_factura} anulada. El stock fue devuelto.${extra}`, datos: venta });
});

export default { listar, obtener, crear, anular };
