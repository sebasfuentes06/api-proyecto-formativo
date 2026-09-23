import { query } from "../db/pool.js";
import { paginacion, orden, filtroEstado } from "../utils/consulta.js";

/** Modelo de Clientes: todo el SQL de esta entidad. */

const COLUMNAS_ORDENABLES = ["nombre", "correo", "ciudad", "fecha_registro", "id_cliente", "ultima_compra"];

/**
 * Lo que la app necesita ver en la lista sin abrir cada cliente: cuántas
 * compras lleva y cuánto debe (saldo de sus ventas confirmadas).
 */
const SELECT_BASE = `
  SELECT cl.*,
         COALESCE(cta.compras, 0)::INT AS compras,
         COALESCE(cta.saldo, 0)::NUMERIC(12,2) AS saldo_pendiente
    FROM clientes cl
    LEFT JOIN (
      SELECT v.id_cliente, COUNT(*) AS compras, SUM(s.saldo) AS saldo
        FROM ventas v JOIN v_ventas_saldo s ON s.id_venta = v.id_venta
       WHERE v.estado = 'confirmada'
       GROUP BY v.id_cliente
    ) cta ON cta.id_cliente = cl.id_cliente
`;

async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const { columna, direccion } = orden(filtros.sortBy, COLUMNAS_ORDENABLES, "nombre", filtros.sortDir);

  const condiciones = [];
  const valores = [];

  if (filtros.search?.trim()) {
    valores.push(`%${filtros.search.trim()}%`);
    condiciones.push(
      `(nombre ILIKE $${valores.length} OR correo ILIKE $${valores.length} OR telefono ILIKE $${valores.length} OR documento ILIKE $${valores.length})`
    );
  }

  if (filtros.ciudad?.trim()) {
    valores.push(filtros.ciudad.trim());
    condiciones.push(`ciudad = $${valores.length}`);
  }

  const estado = filtroEstado(filtros.status);
  if (estado !== null) {
    valores.push(estado);
    condiciones.push(`estado = $${valores.length}`);
  }

  // Con ?conSaldo=1 solo salen los que deben algo.
  if (["1", "true"].includes(String(filtros.conSaldo))) condiciones.push("saldo_pendiente > 0");

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const conteo = await query(`SELECT COUNT(*)::INT AS total FROM (${SELECT_BASE}) x ${where}`, valores);

  const { rows } = await query(
    `SELECT * FROM (${SELECT_BASE}) x
     ${where}
     ORDER BY ${columna} ${direccion} NULLS LAST
     LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

async function obtenerPorId(id) {
  const { rows } = await query(`SELECT * FROM (${SELECT_BASE}) x WHERE id_cliente = $1`, [id]);
  return rows[0] ?? null;
}

async function crear({ nombre, correo, telefono, direccion, ciudad, documento, notas, estado = true }) {
  const { rows } = await query(
    `INSERT INTO clientes (nombre, correo, telefono, direccion, ciudad, estado, documento, notas)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id_cliente`,
    [
      nombre.trim(),
      // El correo se guarda en minúsculas: si no, Laura@correo.com y
      // laura@correo.com pasarían como dos clientes distintos.
      // Opcional desde la app móvil: muchos clientes de WhatsApp no lo dan.
      correo?.trim().toLowerCase() || null,
      telefono?.trim() || null,
      direccion?.trim() || null,
      ciudad?.trim() || null,
      estado,
      documento?.trim() || null,
      notas?.trim() || null
    ]
  );
  return obtenerPorId(rows[0].id_cliente);
}

async function actualizar(id, { nombre, correo, telefono, direccion, ciudad, estado, documento, notas }) {
  const { rowCount } = await query(
    `UPDATE clientes
        SET nombre    = COALESCE($2, nombre),
            correo    = COALESCE($3, correo),
            telefono  = COALESCE($4, telefono),
            direccion = COALESCE($5, direccion),
            ciudad    = COALESCE($6, ciudad),
            estado    = COALESCE($7, estado),
            documento = COALESCE($8, documento),
            notas     = COALESCE($9, notas)
      WHERE id_cliente = $1`,
    [
      id,
      nombre?.trim() ?? null,
      correo?.trim().toLowerCase() ?? null,
      telefono?.trim() ?? null,
      direccion?.trim() ?? null,
      ciudad?.trim() ?? null,
      estado ?? null,
      documento?.trim() ?? null,
      notas?.trim() ?? null
    ]
  );
  return rowCount ? obtenerPorId(id) : null;
}

async function eliminar(id) {
  const { rows } = await query("DELETE FROM clientes WHERE id_cliente = $1 RETURNING *", [id]);
  return rows[0] ?? null;
}

export default { listar, obtenerPorId, crear, actualizar, eliminar };
