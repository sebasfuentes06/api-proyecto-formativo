import { query } from "../db/pool.js";
import { asyncHandler } from "../middlewares/errores.js";

/**
 * GET /api/dashboard/resumen — los números que se ven al abrir la app:
 * cuánto se vendió hoy y en el mes, cuánto está por cobrar, pedidos por
 * atender, productos por agotarse y lo más vendido.
 *
 * El Administrador ve el negocio completo. El Vendedor ve solo lo que él
 * vendió (sus ventas, su cartera, sus más vendidos); los pedidos pendientes y
 * el stock bajo sí son de todos, porque los tiene que atender igual.
 */
const resumen = asyncHandler(async (req, res) => {
  const soloMio = req.usuario?.rol === "Vendedor";
  const valores = soloMio ? [req.usuario.id] : [];
  const deV = soloMio ? "AND v.id_usuario = $1" : "";

  const [ventas, cartera, pedidos, stock, top, solicitudes] = await Promise.all([
    query(
      `SELECT
         COALESCE(SUM(total) FILTER (WHERE fecha_local(fecha)::DATE = hoy_local()), 0) AS hoy,
         COUNT(*) FILTER (WHERE fecha_local(fecha)::DATE = hoy_local())::INT           AS ventas_hoy,
         COALESCE(SUM(total) FILTER (WHERE date_trunc('month', fecha_local(fecha)) = date_trunc('month', hoy_local())), 0) AS mes,
         COUNT(*) FILTER (WHERE date_trunc('month', fecha_local(fecha)) = date_trunc('month', hoy_local()))::INT           AS ventas_mes
       FROM ventas v WHERE estado = 'confirmada' ${deV}`,
      valores
    ),
    query(
      `SELECT COALESCE(SUM(s.saldo), 0) AS saldo, COUNT(*)::INT AS ventas
         FROM v_ventas_saldo s JOIN ventas v ON v.id_venta = s.id_venta
        WHERE v.estado = 'confirmada' AND s.saldo > 0 ${deV}`,
      valores
    ),
    query("SELECT COUNT(*)::INT AS pendientes FROM pedidos WHERE estado = 'pendiente'"),
    query("SELECT COUNT(*)::INT AS bajo FROM productos WHERE estado AND stock <= stock_minimo"),
    query(
      `SELECT p.id_producto, p.nombre, SUM(d.cantidad)::INT AS unidades
         FROM detalle_venta d JOIN ventas v ON v.id_venta = d.id_venta JOIN productos p ON p.id_producto = d.id_producto
        WHERE v.estado = 'confirmada' AND date_trunc('month', fecha_local(v.fecha)) = date_trunc('month', hoy_local()) ${deV}
        GROUP BY p.id_producto, p.nombre ORDER BY unidades DESC LIMIT 5`,
      valores
    ),
    // Solicitudes de registro esperando aprobación (solo le importan al Administrador).
    soloMio
      ? Promise.resolve({ rows: [{ n: 0 }] })
      : query("SELECT COUNT(*)::INT AS n FROM usuarios WHERE aprobacion = 'pendiente'")
  ]);
  res.json({
    ok: true,
    datos: {
      alcance: soloMio ? "mis_ventas" : "negocio",
      ventas_hoy: ventas.rows[0].hoy,
      cantidad_hoy: ventas.rows[0].ventas_hoy,
      ventas_mes: ventas.rows[0].mes,
      cantidad_mes: ventas.rows[0].ventas_mes,
      cartera: cartera.rows[0].saldo,
      ventas_con_saldo: cartera.rows[0].ventas,
      pedidos_pendientes: pedidos.rows[0].pendientes,
      stock_bajo: stock.rows[0].bajo,
      mas_vendidos: top.rows,
      solicitudes_pendientes: solicitudes.rows[0].n
    }
  });
});

export default { resumen };
