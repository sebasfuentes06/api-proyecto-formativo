/**
 * Migración de la APP MÓVIL sobre una base que YA existe (la de Neon).
 *
 *     npm run db:movil
 *
 * Corre database/movil.sql (que no borra nada: todo es IF NOT EXISTS) y crea
 * el usuario administrador si falta. Se puede correr las veces que sea.
 */
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pool, query } from "../src/db/pool.js";
import { asegurarAdministrador } from "../src/services/administrador.js";

const aqui = dirname(fileURLToPath(import.meta.url));

async function main() {
  const url = process.env.DATABASE_URL;
  const destino = url ? new URL(url).hostname : `${process.env.PGHOST ?? "localhost"}/${process.env.PGDATABASE ?? "essence_api"}`;
  console.log(`\nDestino: ${destino}\n`);

  const sql = await readFile(resolve(aqui, "..", "database", "movil.sql"), "utf8");
  await query(sql);
  console.log("  movil.sql aplicado (tablas de pedidos, ventas, pagos y usuarios)");

  const admin = await asegurarAdministrador();
  if (admin.creado) {
    console.log(`  administrador creado: ${admin.correo} / ${admin.clave}`);
    console.log("  -> cámbiale la contraseña desde la app (Perfil > Cambiar contraseña)");
  } else {
    console.log(`  administrador ${admin.correo} ya existía (no se modificó)`);
  }
  console.log("\nListo.\n");
}

main()
  .catch((error) => {
    console.error("\nNo se pudo aplicar la migración.");
    console.error(`Motivo: ${error.message}\n`);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
