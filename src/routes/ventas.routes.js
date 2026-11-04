import { Router } from "express";
import controlador from "../controllers/ventas.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir, exigirPermiso } from "../middlewares/auth.js";

/**
 * Rutas de Ventas. La sesión se exige en routes/index.js.
 * Ver: los tres roles (el Cliente, solo sus compras). Vender: Administrador y
 * Vendedor. Anular: solo Administrador.
 */
const router = Router();

router.get("/", exigirPermiso("sales.view", "payments.own"), controlador.listar);
router.get("/:id", exigirPermiso("sales.view", "payments.own"), validarId, controlador.obtener);
router.post("/", permitir("Administrador", "Vendedor"), exigirPermiso("sales.create"), controlador.crear);
router.post("/:id/anular", permitir("Administrador", "Vendedor"), exigirPermiso("sales.cancel"), validarId, controlador.anular);

export default router;
