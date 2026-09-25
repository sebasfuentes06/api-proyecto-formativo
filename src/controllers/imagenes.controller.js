import { query } from "../db/pool.js";
import { ErrorHttp, asyncHandler } from "../middlewares/errores.js";
import { leerImagenBase64 } from "../utils/imagen.js";

/**
 * Fotos de los productos (catálogo de la app).
 *
 * La app manda la imagen ya comprimida, en base64 dentro del JSON. Se guarda
 * en PostgreSQL como bytes (BYTEA) y se sirve como imagen normal, así que la
 * misma URL sirve para mostrarla en la app o mandarla por WhatsApp.
 */

/** GET /api/productos/:id/imagen — público, para que funcione en un <img>. */
const obtener = asyncHandler(async (req, res) => {
  const { rows } = await query("SELECT contenido, tipo_mime, actualizada_en FROM producto_imagen WHERE id_producto = $1", [
    req.idNumerico
  ]);
  if (!rows[0]) throw new ErrorHttp(404, "Ese producto no tiene imagen.");
  res.set("Content-Type", rows[0].tipo_mime);
  // La app pide la imagen con ?v=<fecha de actualización>: si cambia la
  // foto, cambia la URL y no se queda mostrando la vieja.
  res.set("Cache-Control", "public, max-age=86400");
  res.send(rows[0].contenido);
});

/** PUT /api/productos/:id/imagen  { base64, tipo_mime } */
const guardar = asyncHandler(async (req, res) => {
  const { bytes, tipo } = leerImagenBase64(req.body);

  const { rows: p } = await query("SELECT 1 FROM productos WHERE id_producto = $1", [req.idNumerico]);
  if (!p[0]) throw new ErrorHttp(404, "No existe un producto con ese id.");

  const { rows } = await query(
    `INSERT INTO producto_imagen (id_producto, contenido, tipo_mime)
     VALUES ($1, $2, $3)
     ON CONFLICT (id_producto) DO UPDATE
        SET contenido = EXCLUDED.contenido, tipo_mime = EXCLUDED.tipo_mime, actualizada_en = CURRENT_TIMESTAMP
     RETURNING actualizada_en`,
    [req.idNumerico, bytes, tipo]
  );
  res.json({ ok: true, mensaje: "Imagen guardada.", datos: { id_producto: req.idNumerico, bytes: bytes.length, actualizada_en: rows[0].actualizada_en } });
});

/** DELETE /api/productos/:id/imagen */
const eliminar = asyncHandler(async (req, res) => {
  const { rowCount } = await query("DELETE FROM producto_imagen WHERE id_producto = $1", [req.idNumerico]);
  if (!rowCount) throw new ErrorHttp(404, "Ese producto no tenía imagen.");
  res.json({ ok: true, mensaje: "Imagen eliminada." });
});

export default { obtener, guardar, eliminar };
