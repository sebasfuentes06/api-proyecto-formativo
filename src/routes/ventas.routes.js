import { Router } from "express";
import controlador from "../controllers/ventas.controller.js";
import { validarId } from "../middlewares/validar.js";

/** Rutas de Ventas. La sesión se exige en routes/index.js. */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", controlador.crear);
router.post("/:id/anular", validarId, controlador.anular);

export default router;
