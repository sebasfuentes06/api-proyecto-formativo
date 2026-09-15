import "dotenv/config";

/**
 * Configuración de la aplicación.
 *
 * Todo lo que cambia entre tu equipo y el servidor (claves, host de la base,
 * puerto) sale de variables de entorno, nunca del código. Por eso el archivo
 * .env no se sube al repositorio: lleva la contraseña de la base de datos.
 */

/**
 * La conexión a PostgreSQL admite dos formas:
 *   1. DATABASE_URL: una sola cadena. Es lo que entregan los servicios en la
 *      nube (Neon, Supabase, Render) y lo que se configura al desplegar.
 *   2. PGHOST/PGUSER/...: variables sueltas, cómodas en local.
 */
const databaseUrl = process.env.DATABASE_URL ?? null;

/** ¿La base está en este mismo equipo? De eso depende si se usa SSL. */
function esLocal() {
  if (databaseUrl) return /@(localhost|127\.0\.0\.1)[:/]/.test(databaseUrl);
  return ["localhost", "127.0.0.1"].includes(process.env.PGHOST ?? "localhost");
}

/**
 * SSL: los PostgreSQL en la nube exigen conexión cifrada; el de tu equipo no
 * lo tiene configurado. Se decide solo, y se puede forzar con PGSSL.
 *
 * `rejectUnauthorized: false` porque esos servicios firman su certificado con
 * una autoridad que Node no trae en su lista; sin esto la conexión falla con
 * "self signed certificate in certificate chain".
 */
function resolverSsl() {
  const forzado = process.env.PGSSL;
  if (forzado !== undefined) {
    return ["1", "true", "require"].includes(String(forzado).toLowerCase())
      ? { rejectUnauthorized: false }
      : false;
  }
  return esLocal() ? false : { rejectUnauthorized: false };
}

const env = {
  port: Number(process.env.PORT ?? 3000),
  entorno: process.env.NODE_ENV ?? "development",
  // Vercel define esta variable en sus despliegues. Allá la API corre como
  // función y no hay que abrir ningún puerto.
  esServerless: Boolean(process.env.VERCEL),
  corsOrigins: (process.env.CORS_ORIGINS ?? "*")
    .split(",")
    .map((origen) => origen.trim())
    .filter(Boolean),
  db: {
    connectionString: databaseUrl,
    ssl: resolverSsl(),
    host: process.env.PGHOST ?? "localhost",
    port: Number(process.env.PGPORT ?? 5432),
    database: process.env.PGDATABASE ?? "essence_api",
    user: process.env.PGUSER ?? "postgres",
    password: process.env.PGPASSWORD ?? ""
  }
};

export { env };
