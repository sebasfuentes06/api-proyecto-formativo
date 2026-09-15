import { ErrorHttp } from "./errores.js";

/**
 * Validación de los datos que llegan en el cuerpo de la petición.
 *
 * Está escrita a mano, sin librerías, por dos razones: se entiende leyéndola
 * de arriba abajo, y no agrega dependencias que haya que explicar.
 *
 * La regla de fondo: la base de datos ya tiene sus restricciones (NOT NULL,
 * CHECK, UNIQUE), pero esperar a que ellas fallen da mensajes horribles. Aquí
 * se revisa antes, para responder "el precio no puede ser negativo" en vez de
 * un error de PostgreSQL.
 */

const PATRON_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PATRON_TELEFONO = /^[+()\d\s-]{7,20}$/;

const estaVacio = (valor) =>
  valor === undefined || valor === null || String(valor).trim() === "";

/** Reglas sueltas. Cada una devuelve un mensaje de error, o null si pasa. */
const reglas = {
  requerido: (valor, campo) => (estaVacio(valor) ? `${campo} es obligatorio.` : null),

  texto: (valor, campo, { max }) =>
    !estaVacio(valor) && String(valor).trim().length > max
      ? `${campo} no puede pasar de ${max} caracteres.`
      : null,

  correo: (valor, campo) =>
    !estaVacio(valor) && !PATRON_CORREO.test(String(valor).trim())
      ? `${campo} no tiene un formato válido.`
      : null,

  telefono: (valor, campo) =>
    !estaVacio(valor) && !PATRON_TELEFONO.test(String(valor).trim())
      ? `${campo} solo admite números, espacios y los signos + ( ) -`
      : null,

  entero: (valor, campo, { min = 0 } = {}) => {
    if (estaVacio(valor)) return null;
    const numero = Number(valor);
    if (!Number.isInteger(numero)) return `${campo} debe ser un número entero.`;
    return numero < min ? `${campo} no puede ser menor que ${min}.` : null;
  },

  decimal: (valor, campo, { min = 0, max } = {}) => {
    if (estaVacio(valor)) return null;
    const numero = Number(valor);
    if (Number.isNaN(numero)) return `${campo} debe ser un número.`;
    if (numero < min) return `${campo} no puede ser menor que ${min}.`;
    if (max !== undefined && numero > max) return `${campo} no puede ser mayor que ${max}.`;
    return null;
  },

  booleano: (valor, campo) =>
    valor !== undefined && typeof valor !== "boolean"
      ? `${campo} debe ser verdadero o falso.`
      : null
};

/**
 * Recorre un esquema y devuelve un objeto con los errores por campo.
 *
 * Un esquema se ve así:
 *   { nombre: { etiqueta: "El nombre", requerido: true, texto: { max: 100 } } }
 */
function revisar(datos, esquema, { parcial = false } = {}) {
  const errores = {};

  for (const [campo, config] of Object.entries(esquema)) {
    const valor = datos[campo];
    const etiqueta = config.etiqueta ?? campo;

    // En una edición parcial (PATCH) solo se revisan los campos enviados.
    if (parcial && valor === undefined) continue;

    if (config.requerido) {
      const error = reglas.requerido(valor, etiqueta);
      if (error) {
        errores[campo] = error;
        continue;
      }
    }

    for (const [nombreRegla, opciones] of Object.entries(config)) {
      if (nombreRegla === "etiqueta" || nombreRegla === "requerido") continue;
      const regla = reglas[nombreRegla];
      if (!regla) continue;
      const error = regla(valor, etiqueta, opciones === true ? {} : opciones);
      if (error) {
        errores[campo] = error;
        break;
      }
    }
  }

  return errores;
}

/**
 * Middleware. Se pone antes del controlador en la definición de la ruta:
 *
 *     router.post("/", validarCuerpo(esquemaProducto), controlador.crear);
 *
 * Si algo falla, el controlador nunca se ejecuta.
 */
function validarCuerpo(esquema, opciones = {}) {
  return (req, _res, next) => {
    const errores = revisar(req.body ?? {}, esquema, opciones);
    if (Object.keys(errores).length > 0) {
      return next(new ErrorHttp(400, "Revisa los datos enviados.", errores));
    }
    next();
  };
}

/**
 * Valida que el :id de la URL sea un entero positivo.
 * Sin esto, pedir /api/productos/abc llega hasta la base y revienta allá.
 */
function validarId(req, _res, next) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1) {
    return next(new ErrorHttp(400, "El id debe ser un número entero positivo."));
  }
  req.idNumerico = id;
  next();
}

export { validarCuerpo, validarId, revisar };
