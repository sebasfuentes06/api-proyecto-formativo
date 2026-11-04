import { Router } from "express";
import controlador from "../controllers/usuarios.controller.js";
import { exigirPermiso } from "../middlewares/auth.js";
import { validarId } from "../middlewares/validar.js";

/** Rutas de Usuarios. Sesión y rol Administrador se exigen en routes/index.js. */
const router = Router();

router.get("/", exigirPermiso("users.view"), controlador.listar);
router.post("/", exigirPermiso("users.create"), controlador.crear);
router.put("/:id", exigirPermiso("users.edit"), validarId, controlador.actualizar);
router.put("/:id/password", exigirPermiso("users.edit"), validarId, controlador.restablecerPassword);
router.post("/:id/aprobar", exigirPermiso("users.edit"), validarId, controlador.aprobar);
router.post("/:id/rechazar", exigirPermiso("users.edit"), validarId, controlador.rechazar);

export default router;
