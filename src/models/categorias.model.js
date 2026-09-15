import { query } from "../db/pool.js";
import { paginacion, orden, filtroEstado } from "../utils/consulta.js";

/**
 * Modelo de Categorías: aquí vive todo el SQL de esta entidad.
 *
 * El controlador no escribe consultas y el modelo no sabe nada de HTTP.
 * Esa separación es la que permite cambiar la base de datos sin tocar los
 * controladores, y cambiar la API sin tocar el SQL.
 */

const COLUMNAS_ORDENABLES = ["nombre", "created_at", "id_categoria"];

/**
 * Listado con búsqueda, filtro por estado, orden y paginación.
 * `total_productos` se calcula con una subconsulta: no se guarda en la tabla
 * porque quedaría desactualizado apenas se cree o borre un producto.
 */
async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const { columna, direccion } = orden(filtros.sortBy, COLUMNAS_ORDENABLES, "nombre", filtros.sortDir);

  const condiciones = [];
  const valores = [];

  if (filtros.search?.trim()) {
    valores.push(`%${filtros.search.trim()}%`);
    condiciones.push(`(nombre ILIKE $${valores.length} OR descripcion ILIKE $${valores.length})`);
  }

  const estado = filtroEstado(filtros.status);
  if (estado !== null) {
    valores.push(estado);
    condiciones.push(`estado = $${valores.length}`);
  }

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const conteo = await query(`SELECT COUNT(*)::INT AS total FROM categorias ${where}`, valores);

  const { rows } = await query(
    `SELECT c.*,
            (SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria)::INT AS total_productos
       FROM categorias c
       ${where}
      ORDER BY ${columna} ${direccion}
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

async function obtenerPorId(id) {
  const { rows } = await query(
    `SELECT c.*,
            (SELECT COUNT(*) FROM productos p WHERE p.id_categoria = c.id_categoria)::INT AS total_productos
       FROM categorias c
      WHERE c.id_categoria = $1`,
    [id]
  );
  return rows[0] ?? null;
}

async function crear({ nombre, descripcion, estado = true }) {
  const { rows } = await query(
    `INSERT INTO categorias (nombre, descripcion, estado)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [nombre.trim(), descripcion?.trim() || null, estado]
  );
  return rows[0];
}

/**
 * Actualización. COALESCE deja pasar los campos que no vinieron:
 * si `descripcion` llega como null, se conserva la que ya estaba.
 * Así la misma consulta sirve para PUT (todo) y PATCH (una parte).
 */
async function actualizar(id, { nombre, descripcion, estado }) {
  const { rows } = await query(
    `UPDATE categorias
        SET nombre      = COALESCE($2, nombre),
            descripcion = COALESCE($3, descripcion),
            estado      = COALESCE($4, estado)
      WHERE id_categoria = $1
      RETURNING *`,
    [id, nombre?.trim() ?? null, descripcion?.trim() ?? null, estado ?? null]
  );
  return rows[0] ?? null;
}

async function eliminar(id) {
  const { rows } = await query(
    "DELETE FROM categorias WHERE id_categoria = $1 RETURNING *",
    [id]
  );
  return rows[0] ?? null;
}

/** ¿Hay productos que dependan de esta categoría? Se consulta antes de borrar. */
async function contarProductos(id) {
  const { rows } = await query(
    "SELECT COUNT(*)::INT AS total FROM productos WHERE id_categoria = $1",
    [id]
  );
  return rows[0].total;
}

export default { listar, obtenerPorId, crear, actualizar, eliminar, contarProductos };
