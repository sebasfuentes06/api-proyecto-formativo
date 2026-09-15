import modelo from "../models/clientes.model.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";

/** Controlador de Clientes. */

/** GET /api/clientes */
const listar = asyncHandler(async (req, res) => {
  const { filas, total, pagina, porPagina } = await modelo.listar(req.query);
  res.json(respuestaListado(filas, total, { pagina, porPagina }));
});

/** GET /api/clientes/:id */
const obtener = asyncHandler(async (req, res) => {
  const cliente = await modelo.obtenerPorId(req.idNumerico);
  if (!cliente) throw new ErrorHttp(404, "No existe un cliente con ese id.");
  res.json({ ok: true, datos: cliente });
});

/** POST /api/clientes */
const crear = asyncHandler(async (req, res) => {
  const cliente = await modelo.crear(req.body);
  res.status(201).json({ ok: true, mensaje: "Cliente creado.", datos: cliente });
});

/** PUT /api/clientes/:id */
const actualizar = asyncHandler(async (req, res) => {
  const cliente = await modelo.actualizar(req.idNumerico, req.body);
  if (!cliente) throw new ErrorHttp(404, "No existe un cliente con ese id.");
  res.json({ ok: true, mensaje: "Cliente actualizado.", datos: cliente });
});

/** DELETE /api/clientes/:id */
const eliminar = asyncHandler(async (req, res) => {
  const cliente = await modelo.eliminar(req.idNumerico);
  if (!cliente) throw new ErrorHttp(404, "No existe un cliente con ese id.");
  res.json({ ok: true, mensaje: "Cliente eliminado.", datos: cliente });
});

export default { listar, obtener, crear, actualizar, eliminar };
