import modelo from "../models/categorias.model.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";

/**
 * Controlador de Categorías.
 *
 * Su trabajo es solo este: leer la petición, pedirle los datos al modelo y
 * armar la respuesta. No hay SQL aquí, y no hay lógica de HTTP en el modelo.
 */

/** GET /api/categorias */
const listar = asyncHandler(async (req, res) => {
  const { filas, total, pagina, porPagina } = await modelo.listar(req.query);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/categorias/:id */
const obtener = asyncHandler(async (req, res) => {
  const categoria = await modelo.obtenerPorId(req.idNumerico);
  if (!categoria) throw new ErrorHttp(404, "No existe una categoría con ese id.");
  res.json({ ok: true, datos: categoria });
});

/** POST /api/categorias */
const crear = asyncHandler(async (req, res) => {
  const categoria = await modelo.crear(req.body);
  // 201 = creado. Se devuelve el registro completo, con el id que asignó la
  // base, porque el cliente no lo conocía al enviar la petición.
  res.status(201).json({ ok: true, mensaje: "Categoría creada.", datos: categoria });
});

/** PUT /api/categorias/:id */
const actualizar = asyncHandler(async (req, res) => {
  const categoria = await modelo.actualizar(req.idNumerico, req.body);
  if (!categoria) throw new ErrorHttp(404, "No existe una categoría con ese id.");
  res.json({ ok: true, mensaje: "Categoría actualizada.", datos: categoria });
});

/** DELETE /api/categorias/:id */
const eliminar = asyncHandler(async (req, res) => {
  const id = req.idNumerico;

  // Se revisa antes de borrar para poder explicar el motivo. Si se dejara
  // fallar a la llave foránea, el mensaje sería un error de PostgreSQL que
  // no le dice nada a quien usa la API.
  const productos = await modelo.contarProductos(id);
  if (productos > 0) {
    throw new ErrorHttp(
      409,
      `No se puede eliminar: la categoría tiene ${productos} producto(s) asociado(s). ` +
        "Cámbialos de categoría o desactívala en lugar de borrarla."
    );
  }

  const categoria = await modelo.eliminar(id);
  if (!categoria) throw new ErrorHttp(404, "No existe una categoría con ese id.");
  res.json({ ok: true, mensaje: "Categoría eliminada.", datos: categoria });
});

export default { listar, obtener, crear, actualizar, eliminar };
