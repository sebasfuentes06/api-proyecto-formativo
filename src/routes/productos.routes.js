import { Router } from "express";
import controlador from "../controllers/productos.controller.js";
import { validarCuerpo, validarId } from "../middlewares/validar.js";
import * as esquemas from "../validaciones/esquemas.js";

/** Rutas de Productos. */
const router = Router();

router.get("/", controlador.listar);
router.get("/:id", validarId, controlador.obtener);
router.post("/", validarCuerpo(esquemas.producto), controlador.crear);
router.put("/:id", validarId, validarCuerpo(esquemas.producto, { parcial: true }), controlador.actualizar);
router.delete("/:id", validarId, controlador.eliminar);

export default router;
