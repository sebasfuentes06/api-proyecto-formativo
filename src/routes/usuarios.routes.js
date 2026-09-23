import { Router } from "express";
import controlador from "../controllers/usuarios.controller.js";
import { validarId } from "../middlewares/validar.js";

/** Rutas de Usuarios. Sesión y rol Administrador se exigen en routes/index.js. */
const router = Router();

router.get("/", controlador.listar);
router.post("/", controlador.crear);
router.put("/:id", validarId, controlador.actualizar);
router.put("/:id/password", validarId, controlador.restablecerPassword);

export default router;
