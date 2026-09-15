import { Router } from "express";
import controlador from "../controllers/categorias.controller.js";
import { validarCuerpo, validarId } from "../middlewares/validar.js";
import * as esquemas from "../validaciones/esquemas.js";

/**
 * Rutas de Categorías.
 *
 * Se lee de izquierda a derecha: la petición pasa por los middlewares en
 * orden y solo llega al controlador si todos la dejan pasar.
 */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", validarCuerpo(esquemas.categoria), controlador.crear);
router.put("/:id", validarId, validarCuerpo(esquemas.categoria, { parcial: true }), controlador.actualizar);
router.delete("/:id", validarId, controlador.eliminar);

export default router;
