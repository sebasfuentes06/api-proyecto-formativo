/**
 * Manejo de errores de toda la API, en un solo lugar.
 *
 * Sin esto habría un try/catch repetido en cada controlador, y cada uno
 * respondería a su manera. Así todos los errores salen con el mismo formato.
 */

/** Error con código HTTP, para lanzarlo desde cualquier capa. */
class ErrorHttp extends Error {
  constructor(estado, mensaje, detalles) {
    super(mensaje);
    this.estado = estado;
    this.detalles = detalles;
  }
}

/**
 * Envuelve un controlador async.
 *
 * Express 4 no atrapa los errores de una función async: si una promesa se
 * rechaza, la petición se queda colgada para siempre. Este envoltorio los
 * captura y se los pasa al manejador de abajo.
 */
const asyncHandler = (controlador) => (req, res, next) =>
  Promise.resolve(controlador(req, res, next)).catch(next);

/** Ruta que no existe. Va después de todas las rutas registradas. */
function noEncontrado(req, res) {
  res.status(404).json({
    ok: false,
    error: `La ruta ${req.method} ${req.originalUrl} no existe en esta API.`
  });
}

/**
 * Traduce los códigos de error de PostgreSQL a respuestas entendibles.
 * Sin esto, el cliente recibe cosas como
 * 'duplicate key value violates unique constraint "uq_clientes_correo"'.
 */
const ERRORES_POSTGRES = {
  "23505": { estado: 409, mensaje: "Ya existe un registro con ese valor. Revisa los campos que no se pueden repetir." },
  "23503": { estado: 409, mensaje: "La operación afecta registros relacionados. Revisa las referencias." },
  "23514": { estado: 400, mensaje: "Un valor no cumple las reglas de la base de datos (por ejemplo, un precio negativo)." },
  "22P02": { estado: 400, mensaje: "Un valor tiene un tipo equivocado (por ejemplo, texto donde se espera un número)." }
};

/**
 * Manejador final. Express lo reconoce como manejador de errores porque
 * recibe cuatro parámetros: (error, req, res, next).
 */
// eslint-disable-next-line no-unused-vars
function manejadorErrores(error, req, res, _next) {
  // Cuerpo JSON mal escrito (una coma de más, una comilla sin cerrar).
  // express.json() lanza un SyntaxError; sin este caso saldría como error
  // 500, culpando al servidor de algo que mandó mal el cliente.
  if (error instanceof SyntaxError && "body" in error) {
    return res.status(400).json({
      ok: false,
      error: "El cuerpo de la petición no es JSON válido. Revisa comas y comillas."
    });
  }

  const traducido = ERRORES_POSTGRES[error.code];
  if (traducido) {
    return res.status(traducido.estado).json({
      ok: false,
      error: traducido.mensaje,
      detalleTecnico: error.detail ?? error.message
    });
  }

  const estado = error.estado ?? 500;

  // Los errores del servidor se registran completos en la consola, pero al
  // cliente solo se le dice que algo falló: el detalle de un error interno
  // puede revelar la estructura de la base.
  if (estado >= 500) console.error("[error]", error);

  res.status(estado).json({
    ok: false,
    error: estado >= 500 ? "Error interno del servidor." : error.message,
    ...(error.detalles ? { detalles: error.detalles } : {})
  });
}

export { ErrorHttp, asyncHandler, noEncontrado, manejadorErrores };
