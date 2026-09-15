import app from "./app.js";
import { env } from "./config/env.js";
import { pool } from "./db/pool.js";

/**
 * Arranque de la API.
 *
 * En tu equipo abre un puerto y se queda escuchando. En un despliegue
 * serverless (Vercel) no: allá cada petición invoca la aplicación, y abrir un
 * puerto no sirve de nada. Por eso se exporta la app y el listen es
 * condicional. Es el mismo código en los dos lados.
 */
if (!env.esServerless) {
  const servidor = app.listen(env.port, () => {
    console.log("");
    console.log("  API Proyecto Formativo - Essence Don Aire");
    console.log(`  Escuchando en   http://localhost:${env.port}`);
    console.log(`  Estado          http://localhost:${env.port}/api/health`);
    console.log(`  Entorno         ${env.entorno}`);
    console.log("");
  });

  /**
   * Cierre ordenado. Al detener con Ctrl+C se avisa a PostgreSQL para que
   * libere las conexiones, en vez de dejarlas colgadas hasta que expiren.
   */
  for (const senal of ["SIGINT", "SIGTERM"]) {
    process.on(senal, () => {
      console.log("\nCerrando la API...");
      servidor.close(() => {
        pool.end().then(() => process.exit(0));
      });
    });
  }
}

export default app;
