import { Router } from "express";
import controlador from "../controllers/pagos.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir } from "../middlewares/auth.js";

/**
 * Rutas de Pagos y Abonos. La sesión se exige en routes/index.js.
 * El Cliente ve sus pagos y puede pagar su saldo con un link de Wompi; el
 * equipo registra abonos; solo el Administrador anula.
 */
const router = Router();

router.get("/", controlador.listar);
router.get("/pendientes", permitir("Administrador", "Vendedor"), controlador.pendientes);
router.get("/wompi", controlador.wompiEstado);
router.post("/wompi/links", controlador.wompiCrearLink);
router.post("/wompi/verificar", controlador.wompiVerificar);
router.post("/", permitir("Administrador", "Vendedor"), controlador.registrar);
router.post("/:id/anular", permitir("Administrador"), validarId, controlador.anular);

export default router;
