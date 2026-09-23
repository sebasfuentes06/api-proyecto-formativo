/**
 * Crea un usuario de prueba por rol, para mostrar la app en la sustentación.
 *
 *     npm run db:usuarios-demo
 *
 *   vendedor@essence.com / Vendedor2026*   (rol Vendedor)
 *   cliente@essence.com  / Cliente2026*    (rol Cliente, enlazado a una ficha)
 *
 * Si ya existen, no los toca (no les cambia la contraseña). La ficha del
 * cliente es Laura Restrepo Vélez de los datos de ejemplo o, si no está, el
 * primer cliente activo que no tenga usuario.
 */
import bcrypt from "bcryptjs";
import { pool, query } from "../src/db/pool.js";

async function crear({ nombre, correo, clave, rol, idCliente = null }) {
  const { rows } = await query("SELECT id_usuario FROM usuarios WHERE correo = $1", [correo]);
  if (rows[0]) return `  ${correo} ya existía (no se modificó)`;
  const hash = await bcrypt.hash(clave, 10);
  await query("INSERT INTO usuarios (nombre, correo, password_hash, rol, id_cliente) VALUES ($1, $2, $3, $4, $5)", [
    nombre, correo, hash, rol, idCliente
  ]);
  return `  ${rol.padEnd(9)} ${correo} / ${clave}`;
}

async function main() {
  console.log("");
  console.log(await crear({ nombre: "Carlos Vendedor", correo: "vendedor@essence.com", clave: "Vendedor2026*", rol: "Vendedor" }));

  const { rows } = await query(
    `SELECT c.id_cliente, c.nombre FROM clientes c
      WHERE c.estado AND NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id_cliente = c.id_cliente)
      ORDER BY (c.correo = 'laura.restrepo@correo.com') DESC, c.id_cliente
      LIMIT 1`
  );
  const { rows: ya } = await query("SELECT 1 FROM usuarios WHERE correo = 'cliente@essence.com'");
  if (!rows[0] && !ya[0]) {
    console.log("  No hay ninguna ficha de cliente libre para enlazar el usuario Cliente.");
  } else {
    console.log(await crear({
      nombre: rows[0]?.nombre ?? "Cliente", correo: "cliente@essence.com", clave: "Cliente2026*", rol: "Cliente", idCliente: rows[0]?.id_cliente
    }));
    if (rows[0] && !ya[0]) console.log(`            (enlazado a la ficha de ${rows[0].nombre})`);
  }
  console.log("\nListo.\n");
}

main()
  .catch((error) => {
    console.error(`\nNo se pudieron crear los usuarios: ${error.message}\n`);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
