import { Router } from "express";
import controlador from "../controllers/pedidos.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir } from "../middlewares/auth.js";

/**
 * Rutas de Pedidos. La sesión se exige en routes/index.js.
 * Los tres roles pueden listar, crear, editar y cancelar (el Cliente, solo lo
 * suyo: lo filtra el controlador). Convertir en venta es del equipo.
 */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", controlador.crear);
router.put("/:id", validarId, controlador.actualizar);
router.post("/:id/cancelar", validarId, controlador.cancelar);
router.get("/:id/comprobante", validarId, controlador.verComprobante);
router.put("/:id/comprobante", validarId, controlador.subirComprobante);
router.post("/:id/convertir", permitir("Administrador", "Vendedor"), validarId, controlador.convertir);

export default router;
