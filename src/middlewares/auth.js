import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { ErrorHttp } from "./errores.js";

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

export { ROLES, requiereSesion, permitir, rolesSiHaySesion, esCliente };
