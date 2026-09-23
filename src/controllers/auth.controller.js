import { createHash, randomInt } from "node:crypto";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { env } from "../config/env.js";
import { query, transaccion } from "../db/pool.js";
import { correos, correoConfigurado, bandejaPrueba } from "../services/correo.service.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";

/**
 * Autenticación de la app móvil.
 *
 * Entran los tres roles del proyecto (Administrador, Vendedor, Cliente) si el
 * usuario está activo. Lo que cada uno puede hacer lo deciden las rutas.
 */

function firmar(usuario) {
  if (!env.jwtSecreto) throw new ErrorHttp(500, "Falta configurar JWT_SECRETO en el servidor.");
  return jwt.sign(
    { sub: usuario.id_usuario, nombre: usuario.nombre, rol: usuario.rol, id_cliente: usuario.id_cliente ?? null },
    env.jwtSecreto,
    { expiresIn: env.jwtDuracion }
  );
}

const publico = ({ id_usuario, nombre, correo, rol, id_cliente }) => ({ id_usuario, nombre, correo, rol, id_cliente: id_cliente ?? null });

/** POST /api/auth/login */
const login = asyncHandler(async (req, res) => {
  const correo = String(req.body.correo ?? "").trim().toLowerCase();
  const password = String(req.body.password ?? "");

  const { rows } = await query("SELECT * FROM usuarios WHERE correo = $1", [correo]);
  const usuario = rows[0];

  // El mismo mensaje para "no existe" y "clave mala": decir cuál de las dos
  // falló le confirma a un atacante qué correos están registrados.
  const claveOk = usuario ? await bcrypt.compare(password, usuario.password_hash) : false;
  if (!usuario || !claveOk) throw new ErrorHttp(401, "Correo o contraseña incorrectos.");
  if (usuario.aprobacion === "pendiente") {
    throw new ErrorHttp(403, "Tu registro está pendiente de aprobación. Te avisaremos por correo.");
  }
  if (usuario.aprobacion === "rechazado") {
    throw new ErrorHttp(403, "Tu solicitud de registro no fue aprobada. Escríbenos por WhatsApp si crees que es un error.");
  }
  if (!usuario.estado) throw new ErrorHttp(403, "Tu usuario está inactivo. Habla con la administradora.");

  await query("UPDATE usuarios SET ultimo_acceso = CURRENT_TIMESTAMP WHERE id_usuario = $1", [usuario.id_usuario]);

  res.json({ ok: true, mensaje: `Bienvenida, ${usuario.nombre}.`, datos: { token: firmar(usuario), usuario: publico(usuario) } });
});

/** GET /api/auth/yo — valida el token guardado al abrir la app. */
const yo = asyncHandler(async (req, res) => {
  const { rows } = await query("SELECT * FROM usuarios WHERE id_usuario = $1 AND estado", [req.usuario.id]);
  if (!rows[0]) throw new ErrorHttp(401, "Sesión no válida.");
  res.json({ ok: true, datos: publico(rows[0]) });
});

/** PUT /api/auth/password */
const cambiarPassword = asyncHandler(async (req, res) => {
  const actual = String(req.body.actual ?? "");
  const nueva = String(req.body.nueva ?? "");

  if (nueva.length < 8) throw new ErrorHttp(400, "La nueva contraseña debe tener al menos 8 caracteres.");

  const { rows } = await query("SELECT * FROM usuarios WHERE id_usuario = $1", [req.usuario.id]);
  if (!rows[0] || !(await bcrypt.compare(actual, rows[0].password_hash))) {
    throw new ErrorHttp(400, "La contraseña actual no es correcta.");
  }

  const hash = await bcrypt.hash(nueva, 10);
  await query("UPDATE usuarios SET password_hash = $2 WHERE id_usuario = $1", [req.usuario.id, hash]);
  res.json({ ok: true, mensaje: "Contraseña actualizada." });
});

// ---------------------------------------------------------------------------
// Registro (queda pendiente hasta que el Administrador lo apruebe)
// ---------------------------------------------------------------------------

const PATRON_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PATRON_TELEFONO = /^[+()\d\s-]{7,20}$/;

/**
 * POST /api/auth/registro
 * { nombre, correo, telefono, direccion?, ciudad?, documento?, password, acepta_datos }
 *
 * Crea la cuenta como Cliente PENDIENTE y su ficha de cliente (inactiva hasta
 * la aprobación). Si ya existe una ficha con ese correo y sin cuenta, se usa
 * esa: así no se duplica un cliente que ya compraba en la tienda.
 */
const registro = asyncHandler(async (req, res) => {
  const b = req.body ?? {};
  const datos = {
    nombre: String(b.nombre ?? "").trim(),
    correo: String(b.correo ?? "").trim().toLowerCase(),
    telefono: String(b.telefono ?? "").trim(),
    direccion: String(b.direccion ?? "").trim() || null,
    ciudad: String(b.ciudad ?? "").trim() || null,
    documento: String(b.documento ?? "").trim() || null,
    password: String(b.password ?? "")
  };
  const errores = {};
  if (datos.nombre.length < 3 || datos.nombre.length > 100) errores.nombre = "Escribe tu nombre completo.";
  if (!PATRON_CORREO.test(datos.correo) || datos.correo.length > 100) errores.correo = "Correo no válido.";
  if (!PATRON_TELEFONO.test(datos.telefono)) errores.telefono = "Teléfono no válido.";
  if (datos.password.length < 8) errores.password = "La contraseña debe tener al menos 8 caracteres.";
  if (b.acepta_datos !== true) errores.acepta_datos = "Debes aceptar el tratamiento de datos personales.";
  if (Object.keys(errores).length) throw new ErrorHttp(400, "Revisa los datos del registro.", errores);

  const usuario = await transaccion(async (db) => {
    const { rows: existe } = await db.query("SELECT aprobacion FROM usuarios WHERE correo = $1", [datos.correo]);
    if (existe[0]) {
      const msj =
        existe[0].aprobacion === "pendiente"
          ? "Ya hay una solicitud con ese correo esperando aprobación."
          : "Ya existe una cuenta con ese correo. Si olvidaste la contraseña, usa \"¿Olvidaste tu contraseña?\".";
      throw new ErrorHttp(409, msj);
    }

    // ¿Ya era cliente de la tienda (misma ficha, sin cuenta)?
    const { rows: ficha } = await db.query(
      `SELECT c.id_cliente FROM clientes c
        WHERE c.correo = $1 AND NOT EXISTS (SELECT 1 FROM usuarios u WHERE u.id_cliente = c.id_cliente)`,
      [datos.correo]
    );
    let idCliente = ficha[0]?.id_cliente;
    if (!idCliente) {
      const { rows } = await db.query(
        `INSERT INTO clientes (nombre, correo, telefono, direccion, ciudad, documento, estado, notas)
         VALUES ($1, $2, $3, $4, $5, $6, FALSE, 'Registrado desde la app (pendiente de aprobación)')
         RETURNING id_cliente`,
        [datos.nombre, datos.correo, datos.telefono, datos.direccion, datos.ciudad, datos.documento]
      );
      idCliente = rows[0].id_cliente;
    }

    const hash = await bcrypt.hash(datos.password, 10);
    const { rows } = await db.query(
      `INSERT INTO usuarios (nombre, correo, password_hash, rol, id_cliente, telefono, aprobacion, estado)
       VALUES ($1, $2, $3, 'Cliente', $4, $5, 'pendiente', FALSE)
       RETURNING id_usuario, nombre, correo, telefono`,
      [datos.nombre, datos.correo, hash, idCliente, datos.telefono]
    );
    return rows[0];
  });

  // Avisos por correo: al que se registró y a los administradores activos.
  await correos.registroRecibido(usuario.correo, usuario.nombre);
  const { rows: admins } = await query("SELECT correo FROM usuarios WHERE rol = 'Administrador' AND estado");
  for (const a of admins) await correos.nuevaSolicitud(a.correo, usuario);

  res.status(201).json({
    ok: true,
    mensaje: "¡Listo! Tu solicitud fue enviada. Te avisaremos por correo cuando la administradora la apruebe.",
    datos: { correo: usuario.correo }
  });
});

// ---------------------------------------------------------------------------
// Olvidé mi contraseña: código de 6 dígitos por correo
// ---------------------------------------------------------------------------

const MINUTOS_CODIGO = 15;
const MAX_INTENTOS = 5;
const ESPERA_REENVIO_SEG = 60;

/** Hash del código con la clave del servidor: sin ella, la tabla no sirve. */
const hashCodigo = (codigo) =>
  createHash("sha256").update(`${codigo}:${env.jwtSecreto ?? "sin-secreto"}`).digest("hex");

/**
 * POST /api/auth/olvide  { correo }
 *
 * Responde SIEMPRE lo mismo, exista o no el correo: si dijera "ese correo no
 * está registrado", cualquiera podría averiguar quién tiene cuenta.
 */
const olvide = asyncHandler(async (req, res) => {
  if (!correoConfigurado()) {
    throw new ErrorHttp(503, "El envío de correos no está configurado. Pide a la administradora que restablezca tu contraseña.");
  }
  const correo = String(req.body?.correo ?? "").trim().toLowerCase();
  if (!PATRON_CORREO.test(correo)) throw new ErrorHttp(400, "Escribe un correo válido.", { correo: "Formato." });

  const respuesta = {
    ok: true,
    mensaje: `Si ${correo} tiene una cuenta activa, te enviamos un código. Revisa también la carpeta de spam.`,
    datos: { minutos: MINUTOS_CODIGO, reenviar_en: ESPERA_REENVIO_SEG }
  };

  const { rows } = await query(
    "SELECT id_usuario, nombre, correo FROM usuarios WHERE correo = $1 AND estado AND aprobacion = 'aprobado'",
    [correo]
  );
  const usuario = rows[0];
  if (!usuario) return res.json(respuesta);

  // Freno al reenvío: un código por minuto.
  const { rows: reciente } = await query(
    `SELECT 1 FROM codigos_recuperacion
      WHERE id_usuario = $1 AND creado_en > CURRENT_TIMESTAMP - make_interval(secs => $2)`,
    [usuario.id_usuario, ESPERA_REENVIO_SEG]
  );
  if (reciente[0]) throw new ErrorHttp(429, `Espera un minuto antes de pedir otro código.`);

  const codigo = String(randomInt(0, 1_000_000)).padStart(6, "0");
  await transaccion(async (db) => {
    // El código nuevo invalida los anteriores.
    await db.query("UPDATE codigos_recuperacion SET usado_en = CURRENT_TIMESTAMP WHERE id_usuario = $1 AND usado_en IS NULL", [
      usuario.id_usuario
    ]);
    await db.query(
      `INSERT INTO codigos_recuperacion (id_usuario, codigo_hash, expira_en)
       VALUES ($1, $2, CURRENT_TIMESTAMP + make_interval(mins => $3))`,
      [usuario.id_usuario, hashCodigo(codigo), MINUTOS_CODIGO]
    );
  });

  try {
    await correos.codigo(usuario.correo, usuario.nombre, codigo, MINUTOS_CODIGO);
  } catch (error) {
    console.error("[correo] fallo al enviar el código:", error.message);
    throw new ErrorHttp(502, "No se pudo enviar el correo. Intenta de nuevo en unos minutos.");
  }
  res.json(respuesta);
});

/** POST /api/auth/restablecer  { correo, codigo, nueva } */
const restablecer = asyncHandler(async (req, res) => {
  const correo = String(req.body?.correo ?? "").trim().toLowerCase();
  const codigo = String(req.body?.codigo ?? "").trim();
  const nueva = String(req.body?.nueva ?? "");
  if (!/^\d{6}$/.test(codigo)) throw new ErrorHttp(400, "El código tiene 6 números.", { codigo: "6 dígitos." });
  if (nueva.length < 8) throw new ErrorHttp(400, "La contraseña nueva debe tener al menos 8 caracteres.", { nueva: "Mínimo 8." });

  const invalido = new ErrorHttp(400, "El código no es válido o ya venció. Pide uno nuevo.");

  await transaccion(async (db) => {
    const { rows } = await db.query(
      `SELECT c.* FROM codigos_recuperacion c
         JOIN usuarios u ON u.id_usuario = c.id_usuario
        WHERE u.correo = $1 AND u.estado AND c.usado_en IS NULL AND c.expira_en > CURRENT_TIMESTAMP
        ORDER BY c.creado_en DESC LIMIT 1
        FOR UPDATE OF c`,
      [correo]
    );
    const registro = rows[0];
    if (!registro) throw invalido;

    if (registro.codigo_hash !== hashCodigo(codigo)) {
      const intentos = registro.intentos + 1;
      // Tras 5 intentos fallidos el código se quema: adivinar 1 entre un
      // millón con 5 oportunidades no es un riesgo real.
      await db.query(
        `UPDATE codigos_recuperacion SET intentos = $2::INT, usado_en = CASE WHEN $2::INT >= $3::INT THEN CURRENT_TIMESTAMP END
          WHERE id_codigo = $1`,
        [registro.id_codigo, intentos, MAX_INTENTOS]
      );
      return { fallo: intentos >= MAX_INTENTOS ? "agotado" : MAX_INTENTOS - intentos };
    }

    const hash = await bcrypt.hash(nueva, 10);
    await db.query("UPDATE usuarios SET password_hash = $2 WHERE id_usuario = $1", [registro.id_usuario, hash]);
    await db.query("UPDATE codigos_recuperacion SET usado_en = CURRENT_TIMESTAMP WHERE id_codigo = $1", [registro.id_codigo]);
    return { fallo: null };
  }).then((r) => {
    if (r.fallo === "agotado") throw new ErrorHttp(400, "Demasiados intentos. Pide un código nuevo.");
    if (r.fallo !== null) throw new ErrorHttp(400, `Código incorrecto. Te quedan ${r.fallo} intento(s).`);
  });

  res.json({ ok: true, mensaje: "Contraseña actualizada. Ya puedes iniciar sesión." });
});

/**
 * GET /api/auth/prueba/ultimo-correo?para=  — SOLO con CORREO_MODO=prueba en
 * local. Permite a las pruebas automáticas leer el código enviado. En Vercel
 * esta ruta responde 404 siempre.
 */
const ultimoCorreoPrueba = (req, res) => {
  if (!env.correo.modoPrueba) return res.status(404).json({ ok: false, error: "No disponible." });
  const para = String(req.query.para ?? "").toLowerCase();
  const correo = [...bandejaPrueba].reverse().find((c) => c.para === para);
  res.json({ ok: true, datos: correo ?? null });
};

export default { login, yo, cambiarPassword, registro, olvide, restablecer, ultimoCorreoPrueba };
