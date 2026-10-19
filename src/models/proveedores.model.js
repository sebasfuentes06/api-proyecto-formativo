import { query } from "../db/pool.js";
import { paginacion, orden, filtroEstado } from "../utils/consulta.js";

/** Modelo de Proveedores: todo el SQL de esta entidad. */

const COLUMNAS_ORDENABLES = ["nombre", "ciudad", "calificacion", "fecha_alta", "id_proveedor"];

async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const { columna, direccion } = orden(filtros.sortBy, COLUMNAS_ORDENABLES, "nombre", filtros.sortDir);

  const condiciones = [];
  const valores = [];

  if (filtros.search?.trim()) {
    valores.push(`%${filtros.search.trim()}%`);
    condiciones.push(
      `(nombre ILIKE $${valores.length} OR contacto ILIKE $${valores.length} OR email ILIKE $${valores.length})`
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

  const conteo = await query(`SELECT COUNT(*)::INT AS total FROM proveedores ${where}`, valores);

  const { rows } = await query(
    `SELECT p.*,
            (SELECT COUNT(*) FROM productos pr WHERE pr.id_proveedor = p.id_proveedor)::INT AS total_productos,
            (SELECT COUNT(*) FROM compras c WHERE c.id_proveedor = p.id_proveedor AND c.estado = 'vigente')::INT AS total_compras,
            (SELECT COALESCE(SUM(c.total), 0) FROM compras c WHERE c.id_proveedor = p.id_proveedor AND c.estado = 'vigente')::NUMERIC(12,2) AS total_comprado
       FROM proveedores p
       ${where}
      ORDER BY ${columna} ${direccion}
      LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

async function obtenerPorId(id) {
  const { rows } = await query(
    `SELECT p.*,
            (SELECT COUNT(*) FROM productos pr WHERE pr.id_proveedor = p.id_proveedor)::INT AS total_productos,
            (SELECT COUNT(*) FROM compras c WHERE c.id_proveedor = p.id_proveedor AND c.estado = 'vigente')::INT AS total_compras,
            (SELECT COALESCE(SUM(c.total), 0) FROM compras c WHERE c.id_proveedor = p.id_proveedor AND c.estado = 'vigente')::NUMERIC(12,2) AS total_comprado
       FROM proveedores p
      WHERE p.id_proveedor = $1`,
    [id]
  );
  return rows[0] ?? null;
}

async function crear({ nombre, contacto, email, telefono, ciudad, calificacion = 0, cantidad_resenas = 0, estado = true }) {
  const { rows } = await query(
    `INSERT INTO proveedores (nombre, contacto, email, telefono, ciudad, calificacion, estado, cantidad_resenas)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      nombre.trim(),
      contacto?.trim() || null,
      email?.trim().toLowerCase() || null,
      telefono?.trim() || null,
      ciudad?.trim() || null,
      Number(calificacion) || 0,
      estado,
      Number(cantidad_resenas) || 0
    ]
  );
  return rows[0];
}

async function actualizar(id, { nombre, contacto, email, telefono, ciudad, calificacion, cantidad_resenas, estado }) {
  const { rows } = await query(
    `UPDATE proveedores
        SET nombre       = COALESCE($2, nombre),
            contacto     = COALESCE($3, contacto),
            email        = COALESCE($4, email),
            telefono     = COALESCE($5, telefono),
            ciudad       = COALESCE($6, ciudad),
            calificacion = COALESCE($7, calificacion),
            estado       = COALESCE($8, estado),
            cantidad_resenas = COALESCE($9, cantidad_resenas)
      WHERE id_proveedor = $1
      RETURNING *`,
    [
      id,
      nombre?.trim() ?? null,
      contacto?.trim() ?? null,
      email?.trim().toLowerCase() ?? null,
      telefono?.trim() ?? null,
      ciudad?.trim() ?? null,
      calificacion ?? null,
      estado ?? null,
      cantidad_resenas ?? null
    ]
  );
  return rows[0] ?? null;
}

async function eliminar(id) {
  const { rows } = await query(
    "DELETE FROM proveedores WHERE id_proveedor = $1 RETURNING *",
    [id]
  );
  return rows[0] ?? null;
}

async function contarCompras(id) {
  const { rows } = await query("SELECT COUNT(*)::INT AS total FROM compras WHERE id_proveedor = $1", [id]);
  return rows[0].total;
}

async function contarProductos(id) {
  const { rows } = await query(
    "SELECT COUNT(*)::INT AS total FROM productos WHERE id_proveedor = $1",
    [id]
  );
  return rows[0].total;
}

export default { listar, obtenerPorId, crear, actualizar, eliminar, contarProductos, contarCompras };
