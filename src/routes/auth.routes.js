import { Router } from "express";
import controlador from "../controllers/auth.controller.js";
import { requiereSesion } from "../middlewares/auth.js";

/** Rutas de sesión de la app móvil. */
const router = Router();

router.post("/login", controlador.login);
router.get("/yo", requiereSesion, controlador.yo);
router.put("/password", requiereSesion, controlador.cambiarPassword);

export default router;
