import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { ErrorHttp } from "./errores.js";
import { query } from "../db/pool.js";
import { permisosEfectivos } from "../config/permisos.js";

/**
 * Sesión y roles de la app móvil.
 *
 * La app manda el token que recibió en el login en cada petición:
 *     Authorization: Bearer eyJhbGciOi...
 *
 * Roles (los mismos del proyecto principal):
 *   Administrador  todo
 *   Vendedor       atiende clientes, pedidos, ventas y abonos; no anula ni
 *                  administra catálogo ni usuarios
 *   Cliente        solo lo suyo: catálogo, sus pedidos, sus compras, su saldo
 */

const ROLES = ["Administrador", "Vendedor", "Cliente"];

function leerToken(req) {
  const [tipo, token] = (req.headers.authorization ?? "").split(" ");
  return tipo === "Bearer" && token ? token : null;
}

function verificar(token) {
  if (!env.jwtSecreto) throw new ErrorHttp(500, "Falta configurar JWT_SECRETO en el servidor.");
  try {
    const datos = jwt.verify(token, env.jwtSecreto);
    return { id: datos.sub, nombre: datos.nombre, rol: datos.rol, idCliente: datos.id_cliente ?? null };
  } catch (error) {
    const vencido = error.name === "TokenExpiredError";
    throw new ErrorHttp(401, vencido ? "Tu sesión venció. Vuelve a iniciar sesión." : "Sesión no válida.");
  }
}

/** Exige sesión. Si falta o no sirve, corta con 401. */
function requiereSesion(req, _res, next) {
  const token = leerToken(req);
  if (!token) return next(new ErrorHttp(401, "Inicia sesión para usar esta función."));
  try {
    req.usuario = verificar(token);
    next();
  } catch (error) {
    next(error);
  }
}

/**
 * Deja pasar solo a los roles indicados. Va después de requiereSesion:
 *     router.post("/:id/anular", permitir("Administrador"), controlador.anular)
 */
function permitir(...roles) {
  return (req, _res, next) => {
    if (!req.usuario) return next(new ErrorHttp(401, "Inicia sesión para usar esta función."));
    if (!roles.includes(req.usuario.rol)) {
      return next(new ErrorHttp(403, `Tu rol (${req.usuario.rol}) no tiene permiso para esta acción.`));
    }
    next();
  };
}

/**
 * Para el CRUD base (categorías, proveedores, clientes, productos).
 *
 * Esas rutas siguen abiertas sin token porque las usan el panel web y las
 * pruebas del proyecto formativo. Pero si la petición SÍ trae token (viene de
 * la app), se respetan los roles: un Vendedor no puede editar el catálogo
 * aunque la ruta esté abierta.
 */
function rolesSiHaySesion(...roles) {
  return (req, _res, next) => {
    const token = leerToken(req);
    if (!token) return next();
    try {
      req.usuario = verificar(token);
    } catch (error) {
      return next(error);
    }
    return permitir(...roles)(req, _res, next);
  };
}

const esCliente = (req) => req.usuario?.rol === "Cliente";

/**
 * Permisos por persona (ver config/permisos.js). Se leen de la base en cada
 * petición: si el Administrador le quita un permiso a alguien, aplica de
 * inmediato aunque su sesión siga abierta.
 */
async function permisosDe(req) {
  if (req.permisos) return req.permisos;
  const { rows } = await query("SELECT rol, permisos FROM usuarios WHERE id_usuario = $1", [req.usuario.id]);
  req.permisos = rows[0] ? permisosEfectivos(rows[0].rol, rows[0].permisos) : [];
  return req.permisos;
}

const NOMBRES = {
  products: "productos", categories: "categorías", suppliers: "proveedores", customers: "clientes",
  sales: "ventas", orders: "pedidos", payments: "pagos", purchases: "compras", users: "usuarios"
};
const ACCIONES = { view: "ver", create: "crear", edit: "editar", delete: "eliminar", cancel: "anular", convert: "convertir", toggle: "activar o desactivar" };

/** Exige uno de los permisos indicados (va después de requiereSesion). */
function exigirPermiso(...claves) {
  return async (req, _res, next) => {
    try {
      if (!req.usuario) return next(new ErrorHttp(401, "Inicia sesión para usar esta función."));
      if (req.usuario.rol === "Administrador") return next();
      const propios = await permisosDe(req);
      if (claves.some((c) => propios.includes(c))) return next();
      const [modulo, accion] = claves[0].split(".");
      next(new ErrorHttp(403, `No tienes permiso para ${ACCIONES[accion] ?? accion} ${NOMBRES[modulo] ?? modulo}. Pídeselo al administrador.`));
    } catch (error) {
      next(error);
    }
  };
}

/**
 * Para el CRUD base (rutas abiertas sin token): si la petición trae token,
 * se exige el permiso de la acción según el método HTTP.
 */
function permisoSiHaySesion(modulo, { toggle } = {}) {
  return (req, res, next) => {
    if (req.method === "GET") return next();
    const token = leerToken(req);
    if (!token) return next();
    try {
      req.usuario = verificar(token);
    } catch (error) {
      return next(error);
    }
    const accion = req.method === "POST" ? "create" : req.method === "DELETE" ? "delete" : "edit";
    // Cambiar solo el estado (activo/inactivo) cuenta como "editar" o, si el módulo lo tiene, como "activar".
    const soloEstado = req.method === "PUT" && req.body && Object.keys(req.body).length === 1 && "estado" in req.body;
    const claves = soloEstado && toggle ? [`${modulo}.toggle`, `${modulo}.edit`] : [`${modulo}.${accion}`];
    return exigirPermiso(...claves)(req, res, next);
  };
}

export { verificar as verificarToken };
export { ROLES, requiereSesion, permitir, rolesSiHaySesion, esCliente, exigirPermiso, permisoSiHaySesion, permisosDe };
