import { Router } from "express";
import controlador from "../controllers/pagos.controller.js";
import { validarId } from "../middlewares/validar.js";

/** Rutas de Pagos y Abonos. La sesión se exige en routes/index.js. */
const router = Router();

router.get("/", controlador.listar);
router.get("/pendientes", controlador.pendientes);
router.get("/wompi", controlador.wompiEstado);
router.post("/wompi/links", controlador.wompiCrearLink);
router.post("/wompi/verificar", controlador.wompiVerificar);
router.post("/", controlador.registrar);
router.post("/:id/anular", validarId, controlador.anular);

export default router;
