import modelo from "../models/productos.model.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";

/**
 * Controlador de Productos.
 *
 * Es el único que valida referencias antes de escribir: un producto no puede
 * apuntar a una categoría o a un proveedor que no existan.
 */

/** GET /api/productos */
const listar = asyncHandler(async (req, res) => {
  const { filas, total, pagina, porPagina } = await modelo.listar(req.query);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/productos/:id */
const obtener = asyncHandler(async (req, res) => {
  const producto = await modelo.obtenerPorId(req.idNumerico);
  if (!producto) throw new ErrorHttp(404, "No existe un producto con ese id.");
  res.json({ ok: true, datos: producto });
});

/** POST /api/productos */
const crear = asyncHandler(async (req, res) => {
  // La llave foránea de PostgreSQL también lo impediría, pero su mensaje
  // ("violates foreign key constraint fk_productos_categorias") no le sirve
  // a quien está usando la API. Mejor revisarlo y decirlo con palabras.
  const faltantes = await modelo.referenciasValidas({
    id_categoria: Number(req.body.id_categoria),
    id_proveedor: Number(req.body.id_proveedor)
  });
  if (Object.keys(faltantes).length > 0) {
    throw new ErrorHttp(400, "Revisa la categoría y el proveedor.", faltantes);
  }

  const producto = await modelo.crear(req.body);
  res.status(201).json({ ok: true, mensaje: "Producto creado.", datos: producto });
});

/** PUT /api/productos/:id */
const actualizar = asyncHandler(async (req, res) => {
  const faltantes = await modelo.referenciasValidas({
    id_categoria: req.body.id_categoria ? Number(req.body.id_categoria) : null,
    id_proveedor: req.body.id_proveedor ? Number(req.body.id_proveedor) : null
  });
  if (Object.keys(faltantes).length > 0) {
    throw new ErrorHttp(400, "Revisa la categoría y el proveedor.", faltantes);
  }

  const producto = await modelo.actualizar(req.idNumerico, req.body);
  if (!producto) throw new ErrorHttp(404, "No existe un producto con ese id.");
  res.json({ ok: true, mensaje: "Producto actualizado.", datos: producto });
});

/** DELETE /api/productos/:id */
const eliminar = asyncHandler(async (req, res) => {
  const producto = await modelo.eliminar(req.idNumerico);
  if (!producto) throw new ErrorHttp(404, "No existe un producto con ese id.");
  res.json({ ok: true, mensaje: "Producto eliminado.", datos: producto });
});

export default { listar, obtener, crear, actualizar, eliminar };
