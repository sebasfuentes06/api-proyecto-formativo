import { query } from "../db/pool.js";
import { paginacion, orden, filtroEstado } from "../utils/consulta.js";

/** Modelo de Clientes: todo el SQL de esta entidad. */

const COLUMNAS_ORDENABLES = ["nombre", "correo", "ciudad", "fecha_registro", "id_cliente"];

async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const { columna, direccion } = orden(filtros.sortBy, COLUMNAS_ORDENABLES, "nombre", filtros.sortDir);

  const condiciones = [];
  const valores = [];

  if (filtros.search?.trim()) {
    valores.push(`%${filtros.search.trim()}%`);
    condiciones.push(
      `(nombre ILIKE $${valores.length} OR correo ILIKE $${valores.length} OR telefono ILIKE $${valores.length})`
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

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const conteo = await query(`SELECT COUNT(*)::INT AS total FROM clientes ${where}`, valores);

  const { rows } = await query(
    `SELECT * FROM clientes
     ${where}
     ORDER BY ${columna} ${direccion}
     LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

async function obtenerPorId(id) {
  const { rows } = await query("SELECT * FROM clientes WHERE id_cliente = $1", [id]);
  return rows[0] ?? null;
}

async function crear({ nombre, correo, telefono, direccion, ciudad, estado = true }) {
  const { rows } = await query(
    `INSERT INTO clientes (nombre, correo, telefono, direccion, ciudad, estado)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING *`,
    [
      nombre.trim(),
      // El correo se guarda en minúsculas: si no, Laura@correo.com y
      // laura@correo.com pasarían como dos clientes distintos.
      correo.trim().toLowerCase(),
      telefono?.trim() || null,
      direccion?.trim() || null,
      ciudad?.trim() || null,
      estado
    ]
  );
  return rows[0];
}

async function actualizar(id, { nombre, correo, telefono, direccion, ciudad, estado }) {
  const { rows } = await query(
    `UPDATE clientes
        SET nombre    = COALESCE($2, nombre),
            correo    = COALESCE($3, correo),
            telefono  = COALESCE($4, telefono),
            direccion = COALESCE($5, direccion),
            ciudad    = COALESCE($6, ciudad),
            estado    = COALESCE($7, estado)
      WHERE id_cliente = $1
      RETURNING *`,
    [
      id,
      nombre?.trim() ?? null,
      correo?.trim().toLowerCase() ?? null,
      telefono?.trim() ?? null,
      direccion?.trim() ?? null,
      ciudad?.trim() ?? null,
      estado ?? null
    ]
  );
  return rows[0] ?? null;
}

async function eliminar(id) {
  const { rows } = await query("DELETE FROM clientes WHERE id_cliente = $1 RETURNING *", [id]);
  return rows[0] ?? null;
}

export default { listar, obtenerPorId, crear, actualizar, eliminar };
