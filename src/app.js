import express from "express";
import cors from "cors";
import morgan from "morgan";
import { env } from "./config/env.js";
import rutas from "./routes/index.js";
import { paginaDocumentacion } from "./docs/pagina.js";
import { paginaInicio } from "./web/inicio.js";
import { paginaPanel } from "./web/panel.js";
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
// El límite sube a 3 MB por las fotos de productos que manda la app móvil
// (van en base64 dentro del JSON). Vercel acepta hasta 4,5 MB por petición.
app.use(express.json({ limit: "3mb" }));

/**
 * 4. Las tres páginas HTML. Son la cara visible de la API, para personas.
 *
 * El HTML va incrustado en el código, no como archivos en una carpeta: en un
 * despliegue serverless Express no sirve archivos estáticos, así que un .css
 * o un .js enlazados devolverían 404 y las páginas se verían sin formato.
 *
 * El JSON de la portada no desapareció: vive en /api, que es lo que recibe
 * quien consulte con curl o desde código.
 */
app.get("/", (_req, res) => {
  res.type("html").send(paginaInicio());
});

app.get("/panel", (_req, res) => {
  res.type("html").send(paginaPanel());
});

app.get("/docs", (_req, res) => {
  res.type("html").send(paginaDocumentacion("/api/openapi.json"));
});

// 6. Las rutas de la API, todas bajo /api.
app.use("/api", rutas);

// 7. Cierre: primero el 404, después el manejador de errores.
//    Van al final a propósito: si estuvieran arriba, atraparían todo.
app.use(noEncontrado);
app.use(manejadorErrores);

export default app;
