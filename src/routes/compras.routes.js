import { Router } from "express";
import controlador from "../controllers/compras.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir } from "../middlewares/auth.js";

/**
 * Rutas de Compras a proveedores. La sesión se exige en routes/index.js.
 * Ver: Administrador y Vendedor. Registrar, abonar, cancelar y eliminar:
 * solo el Administrador.
 */
const router = Router();
const admin = permitir("Administrador");

router.get("/", controlador.listar);
router.get("/siguiente-folio", controlador.siguienteFolio);
router.get("/:id", validarId, controlador.obtener);
router.post("/", admin, controlador.crear);
router.post("/:id/pagos", admin, validarId, controlador.registrarPago);
router.delete("/:id/pagos/:idPago", admin, validarId, controlador.eliminarPago);
router.post("/:id/cancelar", admin, validarId, controlador.cancelar);
router.delete("/:id", admin, validarId, controlador.eliminar);

export default router;
