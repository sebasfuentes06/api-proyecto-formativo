import pg from "pg";
import { env } from "../config/env.js";

/**
 * Pool de conexiones a PostgreSQL.
 *
 * Un "pool" es un grupo de conexiones abiertas que se reutilizan. Abrir una
 * conexión cuesta tiempo; si cada petición abriera la suya, la API sería
 * lenta y la base se quedaría sin cupo enseguida.
 *
 * Sobre el tamaño: al desplegar en Vercel la API corre como función y puede
 * haber varias instancias vivas a la vez. Si cada una abriera diez
 * conexiones, un PostgreSQL gratuito se queda sin cupo ("too many
 * connections"). Por eso allá se abren pocas.
 */
const opciones = {
  ssl: env.db.ssl,
  max: env.esServerless ? 2 : 10,
  idleTimeoutMillis: env.esServerless ? 10000 : 30000,
  connectionTimeoutMillis: 10000
};

const pool = env.db.connectionString
  ? new pg.Pool({ connectionString: env.db.connectionString, ...opciones })
  : new pg.Pool({
      host: env.db.host,
      port: env.db.port,
      database: env.db.database,
      user: env.db.user,
      password: env.db.password,
      ...opciones
    });

pool.on("error", (error) => {
  console.error("[db] error inesperado en el pool:", error.message);
});

/**
 * Ejecuta una consulta.
 *
 * Los valores SIEMPRE van aparte, como $1, $2, $3. Nunca se pegan dentro del
 * texto del SQL. Esa es la defensa contra inyección SQL: si alguien escribe
 * "'; DROP TABLE productos; --" en el buscador, PostgreSQL lo trata como
 * texto a buscar, no como una orden.
 */
const query = (texto, valores) => pool.query(texto, valores);

/**
 * Ejecuta varias consultas como una sola unidad: o se guardan todas o
 * ninguna. Es lo que evita, por ejemplo, que una venta quede registrada
 * pero el stock sin descontar porque algo falló a la mitad.
 *
 *     await transaccion(async (cliente) => {
 *       await cliente.query("UPDATE ...");
 *       await cliente.query("INSERT ...");
 *     });
 *
 * Todas las consultas de adentro deben usar `cliente`, no `query`: `query`
 * toma otra conexión del pool y quedaría por fuera de la transacción.
 */
async function transaccion(trabajo) {
  const cliente = await pool.connect();
  try {
    await cliente.query("BEGIN");
    const resultado = await trabajo(cliente);
    await cliente.query("COMMIT");
    return resultado;
  } catch (error) {
    await cliente.query("ROLLBACK").catch(() => {});
    throw error;
  } finally {
    cliente.release();
  }
}

export { pool, query, transaccion };
