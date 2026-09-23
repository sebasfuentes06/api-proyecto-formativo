import { Router } from "express";
import controlador from "../controllers/ventas.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir } from "../middlewares/auth.js";

/**
 * Rutas de Ventas. La sesión se exige en routes/index.js.
 * Ver: los tres roles (el Cliente, solo sus compras). Vender: Administrador y
 * Vendedor. Anular: solo Administrador.
 */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", permitir("Administrador", "Vendedor"), controlador.crear);
router.post("/:id/anular", permitir("Administrador"), validarId, controlador.anular);

export default router;
