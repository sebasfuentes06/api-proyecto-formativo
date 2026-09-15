import express from "express";
import cors from "cors";
import morgan from "morgan";
import { env } from "./config/env.js";
import rutas from "./routes/index.js";
import { noEncontrado, manejadorErrores } from "./middlewares/errores.js";

/**
 * Construcción de la aplicación Express.
 *
 * Este archivo arma la app pero NO la arranca: de eso se encarga server.js.
 * Separarlo permite importar la app desde otro lado (por ejemplo, para
 * pruebas automáticas, o para que la plataforma de despliegue la invoque)
 * sin que se ponga a escuchar un puerto por su cuenta.
 *
 * El orden de los middlewares importa: Express los ejecuta de arriba abajo.
 */
const app = express();

// 1. CORS: permite que un navegador en otro dominio llame a esta API.
app.use(
  cors({
    origin: env.corsOrigins.includes("*") ? true : env.corsOrigins
  })
);

// 2. Registro de peticiones en la consola. Al sustentar se ve en vivo qué
//    está llegando: "POST /api/productos 201 45ms".
app.use(morgan(env.entorno === "production" ? "combined" : "dev"));

// 3. Lectura del cuerpo JSON. Sin esto, req.body llega vacío en los POST.
app.use(express.json());

// 4. Portada. Abrir la raíz en el navegador debe decir algo útil, no un 404.
app.get("/", (_req, res) => {
  res.json({
    nombre: "API Proyecto Formativo - Essence Don Aire",
    version: "1.0.0",
    descripcion: "API REST con operaciones CRUD sobre categorías, proveedores, clientes y productos.",
    estado: "/api/health",
    recursos: {
      categorias: "/api/categorias",
      proveedores: "/api/proveedores",
      clientes: "/api/clientes",
      productos: "/api/productos"
    }
  });
});

// 5. Las rutas de la API, todas bajo /api.
app.use("/api", rutas);

// 6. Cierre: primero el 404, después el manejador de errores.
//    Van al final a propósito: si estuvieran arriba, atraparían todo.
app.use(noEncontrado);
app.use(manejadorErrores);

export default app;
