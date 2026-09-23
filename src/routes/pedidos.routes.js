import { Router } from "express";
import controlador from "../controllers/pedidos.controller.js";
import { validarId } from "../middlewares/validar.js";

/** Rutas de Pedidos. La sesión se exige en routes/index.js. */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", controlador.crear);
router.put("/:id", validarId, controlador.actualizar);
router.post("/:id/cancelar", validarId, controlador.cancelar);
router.post("/:id/convertir", validarId, controlador.convertir);

export default router;
