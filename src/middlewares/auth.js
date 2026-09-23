import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { ErrorHttp } from "./errores.js";

/**
 * Protege las rutas de la app móvil.
 *
 * La app manda el token que recibió en el login en cada petición:
 *     Authorization: Bearer eyJhbGciOi...
 *
 * Si el token falta, está vencido o fue alterado, la petición se corta aquí
 * con 401 y el controlador nunca se ejecuta. La app, al ver un 401, manda al
 * usuario de vuelta a la pantalla de login.
 */
function requiereSesion(req, _res, next) {
  const encabezado = req.headers.authorization ?? "";
  const [tipo, token] = encabezado.split(" ");

  if (tipo !== "Bearer" || !token) {
    return next(new ErrorHttp(401, "Inicia sesión para usar esta función."));
  }
  if (!env.jwtSecreto) {
    return next(new ErrorHttp(500, "Falta configurar JWT_SECRETO en el servidor."));
  }

  try {
    const datos = jwt.verify(token, env.jwtSecreto);
    req.usuario = { id: datos.sub, nombre: datos.nombre, rol: datos.rol };
    next();
  } catch (error) {
    const vencido = error.name === "TokenExpiredError";
    next(new ErrorHttp(401, vencido ? "Tu sesión venció. Vuelve a iniciar sesión." : "Sesión no válida."));
  }
}

export { requiereSesion };
