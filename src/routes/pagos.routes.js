import { Router } from "express";
import controlador from "../controllers/pagos.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir } from "../middlewares/auth.js";

/**
 * Rutas de Pagos y Abonos. La sesión se exige en routes/index.js.
 * El Cliente ve sus pagos, paga su saldo con Wompi o reporta una
 * transferencia con comprobante; el equipo registra abonos; el Administrador
 * aprueba o rechaza los reportes y anula pagos.
 */
const router = Router();

router.get("/", controlador.listar);
router.get("/pendientes", permitir("Administrador", "Vendedor"), controlador.pendientes);
router.get("/wompi", controlador.wompiEstado);
router.post("/wompi/links", controlador.wompiCrearLink);
router.post("/wompi/verificar", controlador.wompiVerificar);
router.get("/datos-pago", controlador.datosPago);
// Los tres roles registran: el equipo aplica el pago de una vez; el Cliente
// lo REPORTA y queda pendiente de aprobación (lo decide el controlador).
router.post("/", controlador.registrar);
router.post("/:id/aprobar", permitir("Administrador"), validarId, controlador.aprobar);
router.post("/:id/rechazar", permitir("Administrador"), validarId, controlador.rechazar);
router.get("/:id/comprobante", validarId, controlador.verComprobante);
router.put("/:id/comprobante", validarId, controlador.subirComprobante);
router.post("/:id/anular", permitir("Administrador"), validarId, controlador.anular);

export default router;
