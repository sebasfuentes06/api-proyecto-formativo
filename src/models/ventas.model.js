import { query } from "../db/pool.js";
import { paginacion } from "../utils/consulta.js";

/**
 * Consultas de lectura de Ventas. Las escrituras (registrar, anular) viven en
 * el controlador porque necesitan transacción; ver services/ventas.service.js.
 */

const SELECT_LISTA = `
  SELECT v.id_venta, v.numero_factura, v.fecha, v.canal, v.estado, v.metodo_pago,
         v.subtotal, v.descuento, v.total,
         s.pagado, s.saldo, s.estado_pago,
         v.id_cliente, c.nombre AS cliente, c.telefono AS cliente_telefono,
         v.id_pedido,
         (SELECT COALESCE(SUM(cantidad), 0)::INT FROM detalle_venta d WHERE d.id_venta = v.id_venta) AS unidades
    FROM ventas v
    JOIN clientes c       ON c.id_cliente = v.id_cliente
    JOIN v_ventas_saldo s ON s.id_venta   = v.id_venta
`;

/**
 * Filtros: search (factura o cliente), id_cliente, estado, estado_pago
 * (pendiente|parcial|pagada|con_saldo), desde, hasta (YYYY-MM-DD).
 */
async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const condiciones = [];
  const valores = [];
  const agregar = (sql, valor) => {
    valores.push(valor);
    condiciones.push(sql.replaceAll("?", `$${valores.length}`));
  };

  if (filtros.search?.trim()) agregar("(v.numero_factura ILIKE ? OR c.nombre ILIKE ?)", `%${filtros.search.trim()}%`);
  if (filtros.id_cliente) agregar("v.id_cliente = ?", Number(filtros.id_cliente));
  if (["confirmada", "anulada"].includes(filtros.estado)) agregar("v.estado = ?", filtros.estado);
  if (filtros.estado_pago === "con_saldo") condiciones.push("s.saldo > 0 AND v.estado = 'confirmada'");
  else if (["pendiente", "parcial", "pagada"].includes(filtros.estado_pago)) agregar("s.estado_pago = ?", filtros.estado_pago);
  if (filtros.desde) agregar("fecha_local(v.fecha) >= ?::DATE", filtros.desde);
  if (filtros.hasta) agregar("fecha_local(v.fecha) < (?::DATE + 1)", filtros.hasta);

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const { rows: totales } = await query(
    `SELECT COUNT(*)::INT AS total,
            COALESCE(SUM(v.total) FILTER (WHERE v.estado = 'confirmada'), 0) AS suma_total,
            COALESCE(SUM(s.saldo) FILTER (WHERE v.estado = 'confirmada'), 0) AS suma_saldo
       FROM ventas v
       JOIN clientes c       ON c.id_cliente = v.id_cliente
       JOIN v_ventas_saldo s ON s.id_venta   = v.id_venta
       ${where}`,
    valores
  );

  const { rows } = await query(
    `${SELECT_LISTA} ${where}
     ORDER BY v.fecha DESC, v.id_venta DESC
     LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return {
    filas: rows,
    total: totales[0].total,
    resumen: { total_vendido: totales[0].suma_total, saldo_pendiente: totales[0].suma_saldo },
    pagina,
    porPagina
  };
}

/** Venta completa: encabezado, cliente, productos, pagos y links de Wompi. */
async function obtenerPorId(id) {
  const { rows } = await query(
    `SELECT v.*, s.pagado, s.saldo, s.estado_pago,
            c.nombre AS cliente, c.telefono AS cliente_telefono, c.correo AS cliente_correo,
            c.direccion AS cliente_direccion, c.ciudad AS cliente_ciudad, c.documento AS cliente_documento,
            pe.codigo AS pedido_codigo,
            u.nombre AS vendedor
       FROM ventas v
       JOIN clientes c       ON c.id_cliente = v.id_cliente
       JOIN v_ventas_saldo s ON s.id_venta   = v.id_venta
       LEFT JOIN pedidos  pe ON pe.id_pedido = v.id_pedido
       LEFT JOIN usuarios u  ON u.id_usuario = v.id_usuario
      WHERE v.id_venta = $1`,
    [id]
  );
  if (!rows[0]) return null;

  const [items, pagos, links] = await Promise.all([
    query(
      `SELECT d.id_detalle, d.id_producto, p.sku, p.nombre, d.cantidad, d.precio_unitario, d.subtotal
         FROM detalle_venta d JOIN productos p ON p.id_producto = d.id_producto
        WHERE d.id_venta = $1 ORDER BY d.id_detalle`,
      [id]
    ),
    query(
      `SELECT p.*, EXISTS (SELECT 1 FROM pago_comprobante pc WHERE pc.id_pago = p.id_pago) AS tiene_comprobante
         FROM pagos p WHERE p.id_venta = $1 ORDER BY p.fecha, p.id_pago`,
      [id]
    ),
    query("SELECT * FROM wompi_links WHERE id_venta = $1 ORDER BY creado_en DESC", [id])
  ]);

  return { ...rows[0], items: items.rows, pagos: pagos.rows, wompi_links: links.rows };
}

export default { listar, obtenerPorId };
