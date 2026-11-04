import { Router } from "express";
import controlador from "../controllers/pagos.controller.js";
import { validarId } from "../middlewares/validar.js";
import { permitir, exigirPermiso } from "../middlewares/auth.js";

/**
 * Rutas de Pagos y Abonos. La sesión se exige en routes/index.js.
 * El Cliente ve sus pagos, paga su saldo con Wompi o reporta una
 * transferencia con comprobante; el equipo registra abonos; el Administrador
 * aprueba o rechaza los reportes y anula pagos.
 */
const router = Router();

router.get("/", exigirPermiso("payments.view"), controlador.listar);
router.get("/pendientes", permitir("Administrador", "Vendedor"), exigirPermiso("payments.view"), controlador.pendientes);
router.get("/wompi", controlador.wompiEstado);
router.post("/wompi/links", exigirPermiso("payments.create", "payments.own"), controlador.wompiCrearLink);
router.post("/wompi/verificar", controlador.wompiVerificar);
router.get("/datos-pago", controlador.datosPago);
// Los tres roles registran: el equipo aplica el pago de una vez; el Cliente
// lo REPORTA y queda pendiente de aprobación (lo decide el controlador).
router.post("/", exigirPermiso("payments.create", "payments.own"), controlador.registrar);
router.post("/:id/aprobar", permitir("Administrador", "Vendedor"), exigirPermiso("payments.edit"), validarId, controlador.aprobar);
router.post("/:id/rechazar", permitir("Administrador", "Vendedor"), exigirPermiso("payments.edit"), validarId, controlador.rechazar);
router.get("/:id/comprobante", validarId, controlador.verComprobante);
router.put("/:id/comprobante", validarId, controlador.subirComprobante);
router.post("/:id/anular", permitir("Administrador", "Vendedor"), exigirPermiso("payments.delete"), validarId, controlador.anular);

export default router;
