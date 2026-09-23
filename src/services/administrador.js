import bcrypt from "bcryptjs";
import { query } from "../db/pool.js";

/**
 * Crea el usuario administrador de la app móvil si todavía no existe.
 *
 * Los datos salen del .env (ADMIN_CORREO, ADMIN_PASSWORD, ADMIN_NOMBRE).
 * Si el usuario ya existe NO se toca: correr la migración dos veces no le
 * cambia la contraseña a nadie.
 */
async function asegurarAdministrador() {
  const correo = (process.env.ADMIN_CORREO ?? "admin@essence.com").trim().toLowerCase();
  const nombre = process.env.ADMIN_NOMBRE ?? "Yésica Restrepo";
  const clave = process.env.ADMIN_PASSWORD ?? "Essence2026*";

  const { rows } = await query("SELECT id_usuario FROM usuarios WHERE correo = $1", [correo]);
  if (rows.length) return { correo, creado: false };

  const hash = await bcrypt.hash(clave, 10);
  await query(
    "INSERT INTO usuarios (nombre, correo, password_hash, rol) VALUES ($1, $2, $3, 'Administrador')",
    [nombre, correo, hash]
  );
  return { correo, creado: true, clave };
}

export { asegurarAdministrador };
