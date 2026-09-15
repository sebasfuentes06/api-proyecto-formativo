import modelo from "../models/proveedores.model.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";

/** Controlador de Proveedores. */

/** GET /api/proveedores */
const listar = asyncHandler(async (req, res) => {
  const { filas, total, pagina, porPagina } = await modelo.listar(req.query);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/proveedores/:id */
const obtener = asyncHandler(async (req, res) => {
  const proveedor = await modelo.obtenerPorId(req.idNumerico);
  if (!proveedor) throw new ErrorHttp(404, "No existe un proveedor con ese id.");
  res.json({ ok: true, datos: proveedor });
});

/** POST /api/proveedores */
const crear = asyncHandler(async (req, res) => {
  const proveedor = await modelo.crear(req.body);
  res.status(201).json({ ok: true, mensaje: "Proveedor creado.", datos: proveedor });
});

/** PUT /api/proveedores/:id */
const actualizar = asyncHandler(async (req, res) => {
  const proveedor = await modelo.actualizar(req.idNumerico, req.body);
  if (!proveedor) throw new ErrorHttp(404, "No existe un proveedor con ese id.");
  res.json({ ok: true, mensaje: "Proveedor actualizado.", datos: proveedor });
});

/** DELETE /api/proveedores/:id */
const eliminar = asyncHandler(async (req, res) => {
  const id = req.idNumerico;

  const productos = await modelo.contarProductos(id);
  if (productos > 0) {
    throw new ErrorHttp(
      409,
      `No se puede eliminar: el proveedor surte ${productos} producto(s). ` +
        "Reasígnalos o desactiva el proveedor en lugar de borrarlo."
    );
  }

  const proveedor = await modelo.eliminar(id);
  if (!proveedor) throw new ErrorHttp(404, "No existe un proveedor con ese id.");
  res.json({ ok: true, mensaje: "Proveedor eliminado.", datos: proveedor });
});

export default { listar, obtener, crear, actualizar, eliminar };
