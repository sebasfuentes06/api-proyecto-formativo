import { Router } from "express";
import controlador from "../controllers/compras.controller.js";
import { validarId } from "../middlewares/validar.js";
import { exigirPermiso } from "../middlewares/auth.js";

/**
 * Rutas de Compras a proveedores. La sesión se exige en routes/index.js.
 * Ver: Administrador y Vendedor. Registrar, abonar, cancelar y eliminar:
 * solo el Administrador.
 */
const router = Router();

router.get("/", exigirPermiso("purchases.view"), controlador.listar);
router.get("/siguiente-folio", exigirPermiso("purchases.view"), controlador.siguienteFolio);
router.get("/:id", exigirPermiso("purchases.view"), validarId, controlador.obtener);
router.post("/", exigirPermiso("purchases.create"), controlador.crear);
router.post("/:id/pagos", exigirPermiso("purchases.create", "purchases.edit"), validarId, controlador.registrarPago);
router.delete("/:id/pagos/:idPago", exigirPermiso("purchases.edit"), validarId, controlador.eliminarPago);
router.post("/:id/cancelar", exigirPermiso("purchases.edit"), validarId, controlador.cancelar);
router.delete("/:id", exigirPermiso("purchases.delete"), validarId, controlador.eliminar);

export default router;
