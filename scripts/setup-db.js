/**
 * Crea el esquema y carga los datos de ejemplo.
 *
 *     npm run db:setup      -> esquema + datos
 *     npm run db:seed       -> solo datos (no toca las tablas)
 *
 * Funciona igual contra el PostgreSQL de tu equipo y contra uno en la nube.
 * En la nube es la única forma cómoda: allá no hay pgAdmin para abrir el .sql
 * y darle "ejecutar".
 */
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";
import { env } from "../src/config/env.js";
import { pool, query } from "../src/db/pool.js";

const aqui = dirname(fileURLToPath(import.meta.url));
const CARPETA_SQL = resolve(aqui, "..", "database");

const soloDatos = process.argv.includes("--solo-datos");

/**
 * Crea la base de datos si todavía no existe.
 *
 * Para crearla hay que estar conectado a OTRA base: no se puede crear una
 * base desde adentro de sí misma. Por eso aquí se abre una conexión aparte
 * contra `postgres`, que es la base administrativa que trae toda instalación.
 *
 * Esto evita tener que abrir pgAdmin solo para hacer un CREATE DATABASE.
 */
async function crearBaseSiFalta() {
  // En los servicios en la nube la base ya viene creada y el usuario no tiene
  // permiso para crear otras, así que este paso se salta.
  if (env.db.connectionString) return;

  const nombre = env.db.database;
  const cliente = new pg.Client({
    host: env.db.host,
    port: env.db.port,
    user: env.db.user,
    password: env.db.password,
    database: "postgres",
    ssl: env.db.ssl
  });

  await cliente.connect();
  try {
    const { rows } = await cliente.query("SELECT 1 FROM pg_database WHERE datname = $1", [nombre]);
    if (rows.length) {
      console.log(`  la base "${nombre}" ya existe`);
      return;
    }
    // El nombre de una base no se puede mandar como parámetro ($1), hay que
    // pegarlo en el texto. Se pasa por una lista blanca de caracteres para
    // que nadie meta una orden dentro del nombre.
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(nombre)) {
      throw new Error(`El nombre de base "${nombre}" no es válido. Usa solo letras, números y guion bajo.`);
    }
    await cliente.query(`CREATE DATABASE ${nombre}`);
    console.log(`  base "${nombre}" creada`);
  } finally {
    await cliente.end();
  }
}

/** Muestra a qué base se va a escribir, sin exponer la contraseña. */
function describirDestino() {
  const url = process.env.DATABASE_URL;
  if (url) {
    try {
      const { hostname, pathname, username } = new URL(url);
      return `${username}@${hostname}${pathname}`;
    } catch {
      return "la base indicada en DATABASE_URL";
    }
  }
  return `${process.env.PGUSER ?? "postgres"}@${process.env.PGHOST ?? "localhost"}/${
    process.env.PGDATABASE ?? "essence_api"
  }`;
}

async function correrArchivo(nombre) {
  const sql = await readFile(resolve(CARPETA_SQL, nombre), "utf8");
  await query(sql);
  console.log(`  ${nombre} ejecutado`);
}

async function main() {
  console.log(`\nDestino: ${describirDestino()}\n`);

  if (!soloDatos) {
    await crearBaseSiFalta();
    await correrArchivo("esquema.sql");
  }
  await correrArchivo("datos_ejemplo.sql");

  const { rows } = await query(
    `SELECT (SELECT COUNT(*) FROM categorias)::INT  AS categorias,
            (SELECT COUNT(*) FROM proveedores)::INT AS proveedores,
            (SELECT COUNT(*) FROM clientes)::INT    AS clientes,
            (SELECT COUNT(*) FROM productos)::INT   AS productos`
  );
  const { categorias, proveedores, clientes, productos } = rows[0];

  console.log("\nContenido de la base:");
  console.log(`  categorías   ${categorias}`);
  console.log(`  proveedores  ${proveedores}`);
  console.log(`  clientes     ${clientes}`);
  console.log(`  productos    ${productos}`);
  console.log("\nListo. Levanta la API con:  npm run dev\n");
}

main()
  .catch((error) => {
    console.error("\nNo se pudo preparar la base de datos.");
    console.error(`Motivo: ${error.message}\n`);

    if (error.code === "ECONNREFUSED") {
      console.error("PostgreSQL no respondió. ¿Está encendido el servicio?");
    }
    if (error.code === "28P01") {
      console.error("Usuario o contraseña incorrectos. Revisa PGUSER y PGPASSWORD en el .env.");
    }
    if (error.code === "3D000") {
      console.error(
        "No existe la base administrativa 'postgres'. Revisa PGHOST y PGPORT: " +
          "quizá estás apuntando a un servidor equivocado."
      );
    }
    process.exitCode = 1;
  })
  .finally(() => pool.end());
