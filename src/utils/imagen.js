import { ErrorHttp } from "../middlewares/errores.js";

/**
 * Lee una imagen que la app manda en base64 dentro del JSON
 * ({ base64, tipo_mime }). La usan la foto del producto y el comprobante de
 * pago. Se revisan los primeros bytes (la "firma" del archivo): así no se
 * guarda cualquier cosa solo porque dice ser image/jpeg.
 */
const TIPOS = ["image/jpeg", "image/png", "image/webp"];
const MAXIMO_BYTES = 1.5 * 1024 * 1024;

function tipoReal(b) {
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b.subarray(0, 4).toString("ascii") === "RIFF" && b.subarray(8, 12).toString("ascii") === "WEBP") return "image/webp";
  return null;
}

function leerImagenBase64(cuerpo = {}) {
  const texto = String(cuerpo.base64 ?? "").replace(/^data:[^;]+;base64,/, "");
  if (!texto) throw new ErrorHttp(400, "No llegó ninguna imagen.");
  const bytes = Buffer.from(texto, "base64");
  if (bytes.length === 0) throw new ErrorHttp(400, "La imagen está vacía o dañada.");
  if (bytes.length > MAXIMO_BYTES) throw new ErrorHttp(413, "La imagen pesa demasiado (máximo 1,5 MB).");
  const tipo = tipoReal(bytes);
  if (!tipo || !TIPOS.includes(tipo)) throw new ErrorHttp(400, "Formato no permitido. Usa JPG, PNG o WEBP.");
  return { bytes, tipo };
}

export { TIPOS, MAXIMO_BYTES, leerImagenBase64 };
