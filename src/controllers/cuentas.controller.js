import { query } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";

/**
 * Historial de compras y estado de cuenta de un cliente.
 * Son la razón de ser del registro de clientes según la ficha: no volver a
 * pedir datos y saber qué ha comprado y cuánto debe.
 */

async function clienteOError(id) {
  const { rows } = await query("SELECT * FROM clientes WHERE id_cliente = $1", [id]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe un cliente con ese id.");
  return rows[0];
}

/** GET /api/clientes/:id/historial — compras con sus productos. */
const historial = asyncHandler(async (req, res) => {
  const cliente = await clienteOError(req.idNumerico);
  const { rows: ventas } = await query(
    `SELECT v.id_venta, v.numero_factura, v.fecha, v.canal, v.estado, v.total, s.pagado, s.saldo, s.estado_pago,
            COALESCE(json_agg(json_build_object('nombre', p.nombre, 'cantidad', d.cantidad) ORDER BY d.id_detalle)
                     FILTER (WHERE d.id_detalle IS NOT NULL), '[]') AS productos
       FROM ventas v
       JOIN v_ventas_saldo s ON s.id_venta = v.id_venta
       LEFT JOIN detalle_venta d ON d.id_venta = v.id_venta
       LEFT JOIN productos p     ON p.id_producto = d.id_producto
      WHERE v.id_cliente = $1
      GROUP BY v.id_venta, s.pagado, s.saldo, s.estado_pago
      ORDER BY v.fecha DESC`,
    [cliente.id_cliente]
  );
  const { rows: favoritos } = await query(
    `SELECT p.id_producto, p.nombre, SUM(d.cantidad)::INT AS unidades
       FROM detalle_venta d JOIN ventas v ON v.id_venta = d.id_venta JOIN productos p ON p.id_producto = d.id_producto
      WHERE v.id_cliente = $1 AND v.estado = 'confirmada'
      GROUP BY p.id_producto, p.nombre ORDER BY unidades DESC LIMIT 5`,
    [cliente.id_cliente]
  );
  const confirmadas = ventas.filter((v) => v.estado === "confirmada");
  res.json({
    ok: true,
    datos: {
      cliente,
      resumen: {
        compras: confirmadas.length,
        total_comprado: confirmadas.reduce((s, v) => s + Number(v.total), 0),
        ultima_compra: cliente.ultima_compra
      },
      favoritos,
      ventas
    }
  });
});

/** GET /api/clientes/:id/estado-cuenta — lo que debe y lo que ha pagado. */
const estadoCuenta = asyncHandler(async (req, res) => {
  const cliente = await clienteOError(req.idNumerico);
  const { rows: ventas } = await query(
    `SELECT v.id_venta, v.numero_factura, v.fecha, v.total, s.pagado, s.saldo, s.estado_pago,
            (hoy_local() - fecha_local(v.fecha)::DATE)::INT AS dias
       FROM ventas v JOIN v_ventas_saldo s ON s.id_venta = v.id_venta
      WHERE v.id_cliente = $1 AND v.estado = 'confirmada'
      ORDER BY v.fecha DESC`,
    [cliente.id_cliente]
  );
  const { rows: pagos } = await query(
    `SELECT p.id_pago, p.fecha, p.monto, p.metodo, p.referencia, p.estado, v.numero_factura, v.id_venta
       FROM pagos p JOIN ventas v ON v.id_venta = p.id_venta
      WHERE v.id_cliente = $1
      ORDER BY p.fecha DESC LIMIT 50`,
    [cliente.id_cliente]
  );
  const suma = (campo) => ventas.reduce((s, v) => s + Number(v[campo]), 0);
  res.json({
    ok: true,
    datos: {
      cliente,
      resumen: {
        total_facturado: suma("total"),
        total_pagado: suma("pagado"),
        saldo: suma("saldo"),
        ventas_con_saldo: ventas.filter((v) => Number(v.saldo) > 0).length
      },
      ventas,
      pagos
    }
  });
});

export default { historial, estadoCuenta };
