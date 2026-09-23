import bcrypt from "bcryptjs";
import { query, transaccion } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { ROLES } from "../middlewares/auth.js";
import { paginacion, respuestaListado } from "../utils/consulta.js";

/**
 * Gestión de usuarios de la app (solo Administrador).
 *
 * Reglas:
 *  - Roles válidos: Administrador, Vendedor, Cliente.
 *  - Un usuario Cliente siempre queda enlazado a una ficha de cliente, y una
 *    ficha tiene como máximo un usuario.
 *  - Nunca puede quedar el sistema sin un Administrador activo (si no, nadie
 *    podría volver a crear usuarios). Mismo resguardo que en el proyecto web.
 *  - Los usuarios no se borran (tienen ventas y pagos a su nombre): se
 *    desactivan.
 */

const PATRON_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const SELECT_BASE = `
  SELECT u.id_usuario, u.nombre, u.correo, u.rol, u.estado, u.id_cliente,
         u.ultimo_acceso, u.created_at, c.nombre AS cliente
    FROM usuarios u
    LEFT JOIN clientes c ON c.id_cliente = u.id_cliente
`;

async function obtener(id) {
  const { rows } = await query(`${SELECT_BASE} WHERE u.id_usuario = $1`, [id]);
  return rows[0] ?? null;
}

/** Revisa rol / cliente enlazado. Devuelve el id_cliente que se debe guardar. */
async function validarRolYCliente(db, { rol, id_cliente }, idUsuario = null) {
  if (!ROLES.includes(rol)) throw new ErrorHttp(400, "Rol no válido.", { rol: ROLES.join(", ") });
  if (rol !== "Cliente") return null;

  const idCliente = Number(id_cliente);
  if (!Number.isInteger(idCliente) || idCliente < 1) {
    throw new ErrorHttp(400, "Un usuario Cliente debe estar enlazado a una ficha de cliente.", { id_cliente: "Obligatorio." });
  }
  const { rows } = await db.query("SELECT id_cliente, nombre FROM clientes WHERE id_cliente = $1", [idCliente]);
  if (!rows[0]) throw new ErrorHttp(404, "No existe esa ficha de cliente.");
  const { rows: ocupado } = await db.query(
    "SELECT correo FROM usuarios WHERE id_cliente = $1 AND id_usuario IS DISTINCT FROM $2",
    [idCliente, idUsuario]
  );
  if (ocupado[0]) throw new ErrorHttp(409, `${rows[0].nombre} ya tiene acceso con el correo ${ocupado[0].correo}.`);
  return idCliente;
}

/** GET /api/usuarios?search=&rol=&status= */
const listar = asyncHandler(async (req, res) => {
  const { pagina, porPagina, offset } = paginacion(req.query);
  const condiciones = [];
  const valores = [];
  if (req.query.search?.trim()) {
    valores.push(`%${req.query.search.trim()}%`);
    condiciones.push(`(u.nombre ILIKE $${valores.length} OR u.correo ILIKE $${valores.length})`);
  }
  if (ROLES.includes(req.query.rol)) {
    valores.push(req.query.rol);
    condiciones.push(`u.rol = $${valores.length}`);
  }
  if (req.query.status === "active") condiciones.push("u.estado");
  if (req.query.status === "inactive") condiciones.push("NOT u.estado");
  const where = condiciones.length ? `WHERE ${condiciones.join(" AND ")}` : "";

  const { rows: t } = await query(`SELECT COUNT(*)::INT AS total FROM usuarios u ${where}`, valores);
  const { rows } = await query(
    `${SELECT_BASE} ${where}
     ORDER BY u.estado DESC, array_position(ARRAY['Administrador','Vendedor','Cliente']::VARCHAR[], u.rol), u.nombre
     LIMIT $${valores.length + 1} OFFSET $${valores.length + 2}`,
    [...valores, porPagina, offset]
  );
  res.json(respuestaListado(rows, t[0].total, { pagina, porPagina }));
});

/** POST /api/usuarios  { nombre, correo, password, rol, id_cliente? } */
const crear = asyncHandler(async (req, res) => {
  const nombre = String(req.body.nombre ?? "").trim();
  const correo = String(req.body.correo ?? "").trim().toLowerCase();
  const password = String(req.body.password ?? "");
  const errores = {};
  if (nombre.length < 3) errores.nombre = "Escribe el nombre.";
  if (!PATRON_CORREO.test(correo)) errores.correo = "Correo no válido.";
  if (password.length < 8) errores.password = "Mínimo 8 caracteres.";
  if (Object.keys(errores).length) throw new ErrorHttp(400, "Revisa los datos enviados.", errores);

  const id = await transaccion(async (db) => {
    const idCliente = await validarRolYCliente(db, req.body);
    const hash = await bcrypt.hash(password, 10);
    const { rows } = await db.query(
      `INSERT INTO usuarios (nombre, correo, password_hash, rol, id_cliente)
       VALUES ($1, $2, $3, $4, $5) RETURNING id_usuario`,
      [nombre, correo, hash, req.body.rol, idCliente]
    );
    return rows[0].id_usuario;
  });
  res.status(201).json({ ok: true, mensaje: "Usuario creado.", datos: await obtener(id) });
});

/** PUT /api/usuarios/:id  { nombre?, correo?, rol?, estado?, id_cliente? } */
const actualizar = asyncHandler(async (req, res) => {
  await transaccion(async (db) => {
    // Se bloquean todos los administradores: así dos personas no pueden
    // desactivarse "al mismo tiempo" y dejar el sistema sin ninguno.
    await db.query("SELECT id_usuario FROM usuarios WHERE rol = 'Administrador' FOR UPDATE");
    const { rows } = await db.query("SELECT * FROM usuarios WHERE id_usuario = $1 FOR UPDATE", [req.idNumerico]);
    const actual = rows[0];
    if (!actual) throw new ErrorHttp(404, "No existe ese usuario.");

    const nuevo = {
      nombre: req.body.nombre !== undefined ? String(req.body.nombre).trim() : actual.nombre,
      correo: req.body.correo !== undefined ? String(req.body.correo).trim().toLowerCase() : actual.correo,
      rol: req.body.rol ?? actual.rol,
      estado: req.body.estado ?? actual.estado,
      id_cliente: req.body.id_cliente !== undefined ? req.body.id_cliente : actual.id_cliente
    };
    if (nuevo.nombre.length < 3) throw new ErrorHttp(400, "Escribe el nombre.", { nombre: "Obligatorio." });
    if (!PATRON_CORREO.test(nuevo.correo)) throw new ErrorHttp(400, "Correo no válido.", { correo: "Formato." });
    if (typeof nuevo.estado !== "boolean") throw new ErrorHttp(400, "El estado debe ser verdadero o falso.");
    const idCliente = await validarRolYCliente(db, nuevo, actual.id_usuario);

    const dejaDeSerAdminActivo =
      actual.rol === "Administrador" && actual.estado && (nuevo.rol !== "Administrador" || !nuevo.estado);
    if (dejaDeSerAdminActivo) {
      const { rows: otros } = await db.query(
        "SELECT COUNT(*)::INT AS n FROM usuarios WHERE rol = 'Administrador' AND estado AND id_usuario <> $1",
        [actual.id_usuario]
      );
      if (otros[0].n === 0) {
        throw new ErrorHttp(409, "Es el único administrador activo. Crea o activa otro antes de cambiar este.");
      }
    }

    await db.query(
      `UPDATE usuarios SET nombre = $2, correo = $3, rol = $4, estado = $5, id_cliente = $6 WHERE id_usuario = $1`,
      [actual.id_usuario, nuevo.nombre, nuevo.correo, nuevo.rol, nuevo.estado, idCliente]
    );
  });
  res.json({ ok: true, mensaje: "Usuario actualizado.", datos: await obtener(req.idNumerico) });
});

/** PUT /api/usuarios/:id/password  { nueva } — la administradora restablece una clave olvidada. */
const restablecerPassword = asyncHandler(async (req, res) => {
  const nueva = String(req.body.nueva ?? "");
  if (nueva.length < 8) throw new ErrorHttp(400, "La contraseña debe tener al menos 8 caracteres.", { nueva: "Mínimo 8." });
  const hash = await bcrypt.hash(nueva, 10);
  const { rowCount } = await query("UPDATE usuarios SET password_hash = $2 WHERE id_usuario = $1", [req.idNumerico, hash]);
  if (!rowCount) throw new ErrorHttp(404, "No existe ese usuario.");
  res.json({ ok: true, mensaje: "Contraseña restablecida. Compártela con la persona por un medio privado." });
});

export default { listar, crear, actualizar, restablecerPassword };
