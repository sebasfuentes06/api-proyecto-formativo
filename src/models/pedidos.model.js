import { query } from "../db/pool.js";
import { paginacion } from "../utils/consulta.js";

/** Consultas de lectura de Pedidos. */

async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const condiciones = [];
  const valores = [];
  const agregar = (sql, valor) => {
    valores.push(valor);
    condiciones.push(sql.replaceAll("?", `$${valores.length}`));
  };

  if (filtros.search?.trim()) agregar("(pe.codigo ILIKE ? OR c.nombre ILIKE ?)", `%${filtros.search.trim()}%`);
  if (["pendiente", "confirmado", "cancelado"].includes(filtros.estado)) agregar("pe.estado = ?", filtros.estado);
  if (["whatsapp", "punto_fisico"].includes(filtros.canal)) agregar("pe.canal = ?", filtros.canal);
  if (filtros.id_cliente) agregar("pe.id_cliente = ?", Number(filtros.id_cliente));

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const conteo = await query(
    `SELECT COUNT(*)::INT AS total FROM pedidos pe JOIN clientes c ON c.id_cliente = pe.id_cliente ${where}`,
    valores
  );
  const { rows } = await query(
    `SELECT pe.id_pedido, pe.codigo, pe.fecha, pe.canal, pe.estado, pe.total, pe.notas,
            pe.id_cliente, c.nombre AS cliente, c.telefono AS cliente_telefono,
            pe.id_venta, v.numero_factura,
            (SELECT COALESCE(SUM(cantidad), 0)::INT FROM detalle_pedido d WHERE d.id_pedido = pe.id_pedido) AS unidades
       FROM pedidos pe
       JOIN clientes c     ON c.id_cliente = pe.id_cliente
       LEFT JOIN ventas v  ON v.id_venta   = pe.id_venta
       ${where}
      ORDER BY (pe.estado = 'pendiente') DESC, pe.fecha DESC
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );
  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

/**
 * Pedido completo. Cada producto trae el stock ACTUAL, para que la app avise
 * antes de convertir si algo se agotó desde que se tomó el pedido.
 */
async function obtenerPorId(id) {
  const { rows } = await query(
    `SELECT pe.*, c.nombre AS cliente, c.telefono AS cliente_telefono, c.direccion AS cliente_direccion,
            v.numero_factura
       FROM pedidos pe
       JOIN clientes c    ON c.id_cliente = pe.id_cliente
       LEFT JOIN ventas v ON v.id_venta   = pe.id_venta
      WHERE pe.id_pedido = $1`,
    [id]
  );
  if (!rows[0]) return null;
  const { rows: items } = await query(
    `SELECT d.id_detalle, d.id_producto, p.sku, p.nombre, d.cantidad, d.precio_unitario, d.subtotal,
            p.stock AS stock_actual, p.estado AS producto_activo,
            (p.stock >= d.cantidad AND p.estado) AS disponible
       FROM detalle_pedido d JOIN productos p ON p.id_producto = d.id_producto
      WHERE d.id_pedido = $1 ORDER BY d.id_detalle`,
    [id]
  );
  return { ...rows[0], items };
}

export default { listar, obtenerPorId };
