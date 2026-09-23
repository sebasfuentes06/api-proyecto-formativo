import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { query } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";

/**
 * Autenticación de la app móvil.
 *
 * Entran los tres roles del proyecto (Administrador, Vendedor, Cliente) si el
 * usuario está activo. Lo que cada uno puede hacer lo deciden las rutas.
 */

function firmar(usuario) {
  if (!env.jwtSecreto) throw new ErrorHttp(500, "Falta configurar JWT_SECRETO en el servidor.");
  return jwt.sign(
    { sub: usuario.id_usuario, nombre: usuario.nombre, rol: usuario.rol, id_cliente: usuario.id_cliente ?? null },
    env.jwtSecreto,
    { expiresIn: env.jwtDuracion }
  );
}

const publico = ({ id_usuario, nombre, correo, rol, id_cliente }) => ({ id_usuario, nombre, correo, rol, id_cliente: id_cliente ?? null });

/** POST /api/auth/login */
const login = asyncHandler(async (req, res) => {
  const correo = String(req.body.correo ?? "").trim().toLowerCase();
  const password = String(req.body.password ?? "");

  const { rows } = await query("SELECT * FROM usuarios WHERE correo = $1", [correo]);
  const usuario = rows[0];

  // El mismo mensaje para "no existe" y "clave mala": decir cuál de las dos
  // falló le confirma a un atacante qué correos están registrados.
  const claveOk = usuario ? await bcrypt.compare(password, usuario.password_hash) : false;
  if (!usuario || !claveOk) throw new ErrorHttp(401, "Correo o contraseña incorrectos.");
  if (!usuario.estado) throw new ErrorHttp(403, "Tu usuario está inactivo. Habla con la administradora.");

  await query("UPDATE usuarios SET ultimo_acceso = CURRENT_TIMESTAMP WHERE id_usuario = $1", [usuario.id_usuario]);

  res.json({ ok: true, mensaje: `Bienvenida, ${usuario.nombre}.`, datos: { token: firmar(usuario), usuario: publico(usuario) } });
});

/** GET /api/auth/yo — valida el token guardado al abrir la app. */
const yo = asyncHandler(async (req, res) => {
  const { rows } = await query("SELECT * FROM usuarios WHERE id_usuario = $1 AND estado", [req.usuario.id]);
  if (!rows[0]) throw new ErrorHttp(401, "Sesión no válida.");
  res.json({ ok: true, datos: publico(rows[0]) });
});

/** PUT /api/auth/password */
const cambiarPassword = asyncHandler(async (req, res) => {
  const actual = String(req.body.actual ?? "");
  const nueva = String(req.body.nueva ?? "");

  if (nueva.length < 8) throw new ErrorHttp(400, "La nueva contraseña debe tener al menos 8 caracteres.");

  const { rows } = await query("SELECT * FROM usuarios WHERE id_usuario = $1", [req.usuario.id]);
  if (!rows[0] || !(await bcrypt.compare(actual, rows[0].password_hash))) {
    throw new ErrorHttp(400, "La contraseña actual no es correcta.");
  }

  const hash = await bcrypt.hash(nueva, 10);
  await query("UPDATE usuarios SET password_hash = $2 WHERE id_usuario = $1", [req.usuario.id, hash]);
  res.json({ ok: true, mensaje: "Contraseña actualizada." });
});

export default { login, yo, cambiarPassword };
