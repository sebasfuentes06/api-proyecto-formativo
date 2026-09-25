import { ErrorHttp } from "../middlewares/errores.js";

/**
 * Validación de los datos de una persona (registro desde la app y ficha de
 * cliente creada por el equipo). Mismo orden y mismas reglas en los dos
 * formularios, como pide la ficha:
 *
 *   nombre completo*, tipo de documento*, documento*, celular* (solo números),
 *   municipio de Antioquia*, dirección, correo, contraseña (solo registro).
 */

const TIPOS_DOCUMENTO = {
  CC: "Cédula de ciudadanía",
  TI: "Tarjeta de identidad",
  CE: "Cédula de extranjería",
  PPT: "Permiso por protección temporal",
  PAS: "Pasaporte",
  NIT: "NIT"
};

const PATRON_CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Celular colombiano: 10 dígitos que empiezan por 3. Solo números.
const PATRON_CELULAR = /^3\d{9}$/;

function documentoValido(tipo, documento) {
  if (["CC", "TI"].includes(tipo)) return /^\d{5,11}$/.test(documento);
  if (tipo === "NIT") return /^\d{6,12}(-\d)?$/.test(documento);
  return /^[A-Za-z0-9]{4,15}$/.test(documento);
}

const texto = (v) => (v === undefined || v === null ? undefined : String(v).trim());

/**
 * Revisa y normaliza. Con `parcial` (editar) solo valida lo que llegó.
 * `correoObligatorio`: en el registro sí (es el usuario de la cuenta); en la
 * ficha de cliente no (muchos clientes de WhatsApp no lo dan).
 */
function validarPersona(b = {}, { parcial = false, correoObligatorio = false } = {}) {
  const d = {
    nombre: texto(b.nombre),
    tipo_documento: texto(b.tipo_documento)?.toUpperCase(),
    documento: texto(b.documento)?.replace(/[.\s]/g, ""),
    telefono: texto(b.telefono)?.replace(/[\s-]/g, ""),
    ciudad: texto(b.ciudad),
    direccion: texto(b.direccion),
    correo: texto(b.correo)?.toLowerCase()
  };
  const errores = {};
  const falta = (campo) => (parcial ? d[campo] === undefined ? false : !d[campo] : !d[campo]);
  const revisar = (campo) => !parcial || d[campo] !== undefined;

  if (falta("nombre")) errores.nombre = "El nombre completo es obligatorio.";
  else if (revisar("nombre") && (d.nombre.length < 3 || d.nombre.length > 100 || !/\s/.test(d.nombre))) {
    errores.nombre = "Escribe nombre y apellido (3 a 100 letras).";
  }

  if (falta("tipo_documento")) errores.tipo_documento = "Elige el tipo de documento.";
  else if (revisar("tipo_documento") && !TIPOS_DOCUMENTO[d.tipo_documento]) {
    errores.tipo_documento = `Usa uno de: ${Object.keys(TIPOS_DOCUMENTO).join(", ")}.`;
  }

  if (falta("documento")) errores.documento = "El número de documento es obligatorio.";
  else if (revisar("documento") && d.tipo_documento && !documentoValido(d.tipo_documento, d.documento)) {
    errores.documento = ["CC", "TI"].includes(d.tipo_documento)
      ? "Solo números, entre 5 y 11 dígitos."
      : "Documento no válido para ese tipo.";
  }

  if (falta("telefono")) errores.telefono = "El celular es obligatorio.";
  else if (revisar("telefono") && !PATRON_CELULAR.test(d.telefono)) {
    errores.telefono = "Solo números: 10 dígitos que empiecen por 3.";
  }

  if (falta("ciudad")) errores.ciudad = "Elige el municipio.";
  else if (revisar("ciudad") && d.ciudad.length > 100) errores.ciudad = "Máximo 100 caracteres.";

  if (d.direccion !== undefined && d.direccion.length > 150) errores.direccion = "Máximo 150 caracteres.";

  if (correoObligatorio && !parcial && !d.correo) errores.correo = "El correo es obligatorio.";
  else if (d.correo && (!PATRON_CORREO.test(d.correo) || d.correo.length > 100)) errores.correo = "Correo no válido.";

  return { datos: d, errores };
}

/** Igual que validarPersona pero lanza 400 si algo está mal. */
function exigirPersona(b, opciones) {
  const { datos, errores } = validarPersona(b, opciones);
  if (Object.keys(errores).length) throw new ErrorHttp(400, "Revisa los datos.", errores);
  return datos;
}

export { TIPOS_DOCUMENTO, PATRON_CORREO, PATRON_CELULAR, validarPersona, exigirPersona };
