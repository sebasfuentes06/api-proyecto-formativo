import { Router } from "express";
import { pool } from "../db/pool.js";
import { asyncHandler } from "../middlewares/errores.js";
import { construirEspecificacion } from "../docs/openapi.js";
import categorias from "./categorias.routes.js";
import proveedores from "./proveedores.routes.js";
import clientes from "./clientes.routes.js";
import productos from "./productos.routes.js";

/**
 * Punto donde se juntan todas las rutas de la API.
 *
 * Tener este archivo evita que app.js crezca: para agregar una entidad nueva
 * se crea su archivo de rutas y se registra aquí, en una línea.
 */
const router = Router();

/**
 * Estado de la API y de la base de datos.
 * Es la primera URL que hay que abrir cuando algo no funciona: dice si el
 * problema es la API o la conexión a PostgreSQL.
 */
router.get(
  "/health",
  asyncHandler(async (_req, res) => {
    try {
      const inicio = Date.now();
      await pool.query("SELECT 1");
      res.json({
        ok: true,
        api: "en línea",
        baseDeDatos: "conectada",
        tiempoRespuestaMs: Date.now() - inicio
      });
    } catch (error) {
      res.status(503).json({ ok: false, api: "en línea", baseDeDatos: "sin conexión", error: error.message });
    }
  })
);

/**
 * Especificación OpenAPI en JSON.
 *
 * La URL del servidor se arma con los datos de la petición, no con una
 * constante: así el botón "Try it out" apunta al sitio correcto tanto en
 * localhost como en el despliegue, sin tener que configurar nada.
 */
router.get("/openapi.json", (req, res) => {
  const protocolo = req.headers["x-forwarded-proto"] ?? req.protocol;
  res.json(construirEspecificacion({ url: `${protocolo}://${req.get("host")}` }));
});

router.use("/categorias", categorias);
router.use("/proveedores", proveedores);
router.use("/clientes", clientes);
router.use("/productos", productos);

export default router;
