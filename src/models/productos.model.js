import { query } from "../db/pool.js";
import { paginacion, orden, filtroEstado } from "../utils/consulta.js";

/**
 * Modelo de Productos: todo el SQL de esta entidad.
 *
 * Es la única de las cuatro que tiene llaves foráneas, así que sus consultas
 * hacen JOIN para devolver el nombre de la categoría y del proveedor. Sin eso
 * el cliente recibiría `id_categoria: 3` y tendría que ir a preguntar qué es 3.
 */

const COLUMNAS_ORDENABLES = ["nombre", "sku", "precio", "stock", "fecha_creacion", "id_producto"];

/** Se repite en varias consultas, así que se escribe una sola vez. */
const SELECT_BASE = `
  SELECT p.id_producto, p.sku, p.nombre, p.descripcion,
         p.precio, p.stock, p.stock_minimo, p.estado, p.fecha_creacion,
         p.id_categoria, c.nombre AS categoria,
         p.id_proveedor, pr.nombre AS proveedor,
         (p.stock <= p.stock_minimo) AS stock_bajo,
         img.actualizada_en AS imagen_actualizada
    FROM productos p
    LEFT JOIN producto_imagen img ON img.id_producto = p.id_producto
    JOIN categorias  c  ON c.id_categoria  = p.id_categoria
    JOIN proveedores pr ON pr.id_proveedor = p.id_proveedor
`;

async function listar(filtros = {}) {
  const { pagina, porPagina, offset } = paginacion(filtros);
  const { columna, direccion } = orden(filtros.sortBy, COLUMNAS_ORDENABLES, "nombre", filtros.sortDir);

  const condiciones = [];
  const valores = [];

  if (filtros.search?.trim()) {
    valores.push(`%${filtros.search.trim()}%`);
    condiciones.push(
      `(p.nombre ILIKE $${valores.length} OR p.sku ILIKE $${valores.length} OR p.descripcion ILIKE $${valores.length})`
    );
  }

  if (filtros.categoria) {
    valores.push(Number(filtros.categoria));
    condiciones.push(`p.id_categoria = $${valores.length}`);
  }

  if (filtros.proveedor) {
    valores.push(Number(filtros.proveedor));
    condiciones.push(`p.id_proveedor = $${valores.length}`);
  }

  const estado = filtroEstado(filtros.status);
  if (estado !== null) {
    valores.push(estado);
    condiciones.push(`p.estado = $${valores.length}`);
  }

  // ?stockBajo=1 trae solo los que están en el mínimo o por debajo.
  if (["1", "true"].includes(String(filtros.stockBajo))) {
    condiciones.push("p.stock <= p.stock_minimo");
  }

  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const conteo = await query(
    `SELECT COUNT(*)::INT AS total FROM productos p ${where}`,
    valores
  );

  const { rows } = await query(
    // La columna lleva el prefijo p. porque el JOIN trae nombres repetidos
    // (productos.nombre y categorias.nombre): sin el prefijo, PostgreSQL
    // responde "column reference nombre is ambiguous".
    `${SELECT_BASE} ${where}
     ORDER BY p.${columna} ${direccion}
     LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );

  return { filas: rows, total: conteo.rows[0].total, pagina, porPagina };
}

async function obtenerPorId(id) {
  const { rows } = await query(`${SELECT_BASE} WHERE p.id_producto = $1`, [id]);
  return rows[0] ?? null;
}

async function crear(datos) {
  const { rows } = await query(
    `INSERT INTO productos
       (id_categoria, id_proveedor, sku, nombre, descripcion, precio, stock, stock_minimo, estado)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING id_producto`,
    [
      Number(datos.id_categoria),
      Number(datos.id_proveedor),
      datos.sku.trim().toUpperCase(),
      datos.nombre.trim(),
      datos.descripcion?.trim() || null,
      Number(datos.precio) || 0,
      Number(datos.stock) || 0,
      Number(datos.stock_minimo) || 0,
      datos.estado ?? true
    ]
  );
  // Se devuelve con el JOIN hecho, para que la respuesta del POST tenga la
  // misma forma que la del GET.
  return obtenerPorId(rows[0].id_producto);
}

async function actualizar(id, datos) {
  const { rowCount } = await query(
    `UPDATE productos
        SET id_categoria = COALESCE($2, id_categoria),
            id_proveedor = COALESCE($3, id_proveedor),
            sku          = COALESCE($4, sku),
            nombre       = COALESCE($5, nombre),
            descripcion  = COALESCE($6, descripcion),
            precio       = COALESCE($7, precio),
            stock        = COALESCE($8, stock),
            stock_minimo = COALESCE($9, stock_minimo),
            estado       = COALESCE($10, estado)
      WHERE id_producto = $1`,
    [
      id,
      datos.id_categoria ?? null,
      datos.id_proveedor ?? null,
      datos.sku?.trim().toUpperCase() ?? null,
      datos.nombre?.trim() ?? null,
      datos.descripcion?.trim() ?? null,
      datos.precio ?? null,
      datos.stock ?? null,
      datos.stock_minimo ?? null,
      datos.estado ?? null
    ]
  );
  return rowCount ? obtenerPorId(id) : null;
}

async function eliminar(id) {
  const { rows } = await query(
    "DELETE FROM productos WHERE id_producto = $1 RETURNING id_producto, nombre, sku",
    [id]
  );
  return rows[0] ?? null;
}

/** Comprueba que existan la categoría y el proveedor antes de insertar. */
async function referenciasValidas({ id_categoria, id_proveedor }) {
  const faltantes = {};

  if (id_categoria !== undefined && id_categoria !== null) {
    const { rows } = await query("SELECT 1 FROM categorias WHERE id_categoria = $1", [id_categoria]);
    if (!rows.length) faltantes.id_categoria = `No existe la categoría ${id_categoria}.`;
  }

  if (id_proveedor !== undefined && id_proveedor !== null) {
    const { rows } = await query("SELECT 1 FROM proveedores WHERE id_proveedor = $1", [id_proveedor]);
    if (!rows.length) faltantes.id_proveedor = `No existe el proveedor ${id_proveedor}.`;
  }

  return faltantes;
}

export default { listar, obtenerPorId, crear, actualizar, eliminar, referenciasValidas };
