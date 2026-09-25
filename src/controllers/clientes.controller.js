import modelo from "../models/clientes.model.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { respuestaListado } from "../utils/consulta.js";
import { exigirPersona } from "../validaciones/persona.js";

/**
 * Desde la app (con sesión) la ficha exige los mismos datos del registro:
 * nombre, tipo y número de documento, celular y municipio. Sin sesión (panel
 * web del CRUD base) se mantienen las reglas originales del proyecto.
 */
function datosCliente(req, { parcial = false } = {}) {
  if (!req.usuario) return req.body;
  const d = exigirPersona(req.body, { parcial });
  // "" se guarda como NULL (el correo es UNIQUE: dos "" chocarían).
  const limpio = Object.fromEntries(Object.entries(d).filter(([, v]) => v !== undefined).map(([k, v]) => [k, v || null]));
  return { ...req.body, ...limpio };
}

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
  const cliente = await modelo.crear(datosCliente(req));
  res.status(201).json({ ok: true, mensaje: "Cliente creado.", datos: cliente });
});

/** PUT /api/clientes/:id */
const actualizar = asyncHandler(async (req, res) => {
  const cliente = await modelo.actualizar(req.idNumerico, datosCliente(req, { parcial: true }));
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
