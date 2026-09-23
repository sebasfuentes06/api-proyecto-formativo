import { Router } from "express";
import controlador from "../controllers/auth.controller.js";
import { requiereSesion } from "../middlewares/auth.js";

/** Rutas de sesión de la app móvil. Registro y recuperación son públicas. */
const router = Router();

router.post("/login", controlador.login);
router.post("/registro", controlador.registro);
router.post("/olvide", controlador.olvide);
router.post("/restablecer", controlador.restablecer);
router.get("/prueba/ultimo-correo", controlador.ultimoCorreoPrueba);
router.get("/yo", requiereSesion, controlador.yo);
router.put("/password", requiereSesion, controlador.cambiarPassword);

export default router;
