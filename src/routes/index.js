import { Router } from "express";
import { pool } from "../db/pool.js";
import { asyncHandler } from "../middlewares/errores.js";
import { construirEspecificacion } from "../docs/openapi.js";
import categorias from "./categorias.routes.js";
import proveedores from "./proveedores.routes.js";
import clientes from "./clientes.routes.js";
import productos from "./productos.routes.js";
import auth from "./auth.routes.js";
import pedidos from "./pedidos.routes.js";
import ventas from "./ventas.routes.js";
import pagos from "./pagos.routes.js";
import usuarios from "./usuarios.routes.js";
import { requiereSesion, permitir, rolesSiHaySesion } from "../middlewares/auth.js";
import { ErrorHttp } from "../middlewares/errores.js";
import { validarId } from "../middlewares/validar.js";
import cuentas from "../controllers/cuentas.controller.js";
import imagenes from "../controllers/imagenes.controller.js";
import dashboard from "../controllers/dashboard.controller.js";
import pagosControlador from "../controllers/pagos.controller.js";

/**
 * Punto donde se juntan todas las rutas de la API.
 *
 * Tener este archivo evita que app.js crezca: para agregar una entidad nueva
 * se crea su archivo de rutas y se registra aquí, en una línea.
 */
const router = Router();

/**
 * Índice de la API en JSON.
 *
 * Es lo que antes devolvía la raíz. Se movió aquí cuando la raíz pasó a ser
 * una página web: un programa que consulte la API espera JSON, y una persona
 * que abra el navegador espera algo que pueda leer. Cada uno tiene su sitio.
 */
router.get("/", (_req, res) => {
  res.json({
    nombre: "API Proyecto Formativo - Essence Don Aire",
    version: "1.0.0",
    descripcion: "API REST con operaciones CRUD sobre categorías, proveedores, clientes y productos.",
    documentacion: "/docs",
    especificacion: "/api/openapi.json",
    panel: "/panel",
    estado: "/api/health",
    recursos: {
      categorias: "/api/categorias",
      proveedores: "/api/proveedores",
      clientes: "/api/clientes",
      productos: "/api/productos"
    },
    appMovil: {
      nota: "Requieren sesión: Authorization: Bearer <token de /api/auth/login>",
      login: "POST /api/auth/login",
      pedidos: "/api/pedidos",
      ventas: "/api/ventas",
      pagos: "/api/pagos",
      carteraPendiente: "/api/pagos/pendientes",
      dashboard: "/api/dashboard/resumen",
      estadoDeCuenta: "/api/clientes/:id/estado-cuenta",
      historialDeCompras: "/api/clientes/:id/historial",
      usuarios: "/api/usuarios (solo Administrador)",
      webhookWompi: "POST /api/webhooks/wompi"
    }
  });
});

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

// --- Rutas de la app móvil ------------------------------------
// Van ANTES de los routers CRUD para que /clientes/:id/historial y
// /productos/:id/imagen no los atrape el router genérico de la entidad.
router.use("/auth", auth);

// La imagen se consulta sin sesión (se usa en <img> y al compartir por
// WhatsApp); subirla o borrarla sí exige sesión.
router.get("/productos/:id/imagen", validarId, imagenes.obtener);
router.put("/productos/:id/imagen", requiereSesion, permitir("Administrador"), validarId, imagenes.guardar);
router.delete("/productos/:id/imagen", requiereSesion, permitir("Administrador"), validarId, imagenes.eliminar);

router.get("/clientes/:id/historial", requiereSesion, validarId, cuentas.historial);
router.get("/clientes/:id/estado-cuenta", requiereSesion, validarId, cuentas.estadoCuenta);

router.use("/pedidos", requiereSesion, pedidos);
router.use("/ventas", requiereSesion, ventas);
router.use("/pagos", requiereSesion, pagos);
router.get("/dashboard/resumen", requiereSesion, permitir("Administrador", "Vendedor"), dashboard.resumen);
router.use("/usuarios", requiereSesion, permitir("Administrador"), usuarios);

// Lo llama Wompi: no lleva sesión, lleva firma (se verifica adentro).
router.post("/webhooks/wompi", pagosControlador.wompiWebhook);

// --- CRUD base del proyecto formativo ---------------------------
// Sin token siguen abiertas (panel web y pruebas del CRUD). Con token (la
// app), se aplican los roles:
//   catálogo (categorías, proveedores, productos): leen todos, escribe el Administrador
//   clientes: el equipo los ve, crea y edita; activar/desactivar y borrar es del Administrador
const escribeSolo = (...roles) => (req, res, next) =>
  req.method === "GET" ? next() : rolesSiHaySesion(...roles)(req, res, next);

function reglasClientes(req, res, next) {
  const metodo = req.method;
  const reglas = metodo === "DELETE" ? ["Administrador"] : ["Administrador", "Vendedor"];
  rolesSiHaySesion(...reglas)(req, res, (error) => {
    if (error) {
      // Un Cliente sí puede leer su propia ficha.
      const propia = metodo === "GET" && req.usuario?.rol === "Cliente" && req.path === `/${req.usuario.idCliente}`;
      return propia ? next() : next(error);
    }
    if (req.usuario?.rol === "Vendedor" && metodo !== "GET" && req.body?.estado !== undefined) {
      return next(new ErrorHttp(403, "Solo el Administrador puede activar o desactivar clientes."));
    }
    next();
  });
}

router.use("/categorias", escribeSolo("Administrador"), categorias);
router.use("/proveedores", escribeSolo("Administrador"), proveedores);
router.use("/clientes", reglasClientes, clientes);
router.use("/productos", escribeSolo("Administrador"), productos);

export default router;
