import { createHash, timingSafeEqual } from "node:crypto";
import { env } from "../config/env.js";
import { transaccion } from "../db/pool.js";
import { ErrorHttp } from "../middlewares/errores.js";

/**
 * Integración con Wompi (pasarela de pagos de Bancolombia).
 *
 * Flujo de un abono con Wompi:
 *   1. La app pide un LINK DE PAGO para una venta y un monto.
 *   2. La API lo crea en Wompi y lo guarda en wompi_links.
 *   3. La app se lo manda al cliente por WhatsApp.
 *   4. El cliente paga (tarjeta, PSE, Nequi, Bancolombia...).
 *   5. Wompi avisa a POST /api/webhooks/wompi con el evento firmado.
 *   6. La API verifica la firma y registra el abono. El saldo baja solo.
 *
 * Si el webhook no llega (por ejemplo, aún no se configuró la URL de eventos
 * en el panel de Wompi), la app tiene un botón "Verificar pago" que consulta
 * la transacción directamente con su id. Los dos caminos terminan en
 * aplicarTransaccion(), así que el abono nunca queda duplicado.
 */

const { wompi } = env;

function exigirConfiguracion() {
  if (!wompi.llavePrivada) {
    throw new ErrorHttp(
      503,
      "Wompi no está configurado: falta WOMPI_LLAVE_PRIVADA en el servidor. Mientras tanto registra el abono manualmente."
    );
  }
}

async function llamarWompi(ruta, { method = "GET", body, privada = false } = {}) {
  let respuesta;
  try {
    respuesta = await fetch(`${wompi.apiUrl}${ruta}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(privada ? { Authorization: `Bearer ${wompi.llavePrivada}` } : {})
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(15000)
    });
  } catch (error) {
    throw new ErrorHttp(502, `No se pudo conectar con Wompi (${error.message}).`);
  }

  const datos = await respuesta.json().catch(() => ({}));
  if (!respuesta.ok) {
    // Wompi devuelve { error: { type, reason | messages } }
    const detalle = datos?.error?.reason ?? JSON.stringify(datos?.error?.messages ?? datos?.error ?? {});
    throw new ErrorHttp(502, `Wompi rechazó la solicitud: ${detalle}`);
  }
  return datos.data;
}

/** Crea un link de pago de un solo uso por el monto indicado. */
async function crearLink({ venta, cliente, monto }) {
  exigirConfiguracion();
  const expira = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000); // 3 días
  const link = await llamarWompi("/payment_links", {
    method: "POST",
    privada: true,
    body: {
      name: `Essence Don Aire - ${venta.numero_factura}`,
      description: `Abono a la factura ${venta.numero_factura} de ${cliente}`.slice(0, 250),
      single_use: true,
      collect_shipping: false,
      currency: "COP",
      amount_in_cents: Math.round(monto * 100),
      expires_at: expira.toISOString(),
      sku: `V${venta.id_venta}`
    }
  });
  return { id: link.id, url: `${wompi.checkoutUrl}${link.id}`, expira };
}

/** Consulta una transacción (endpoint público de Wompi, sin llave privada). */
async function consultarTransaccion(id) {
  return llamarWompi(`/transactions/${encodeURIComponent(id)}`);
}

/**
 * Verifica la firma de un evento.
 *
 * Wompi concatena los valores de `signature.properties` (en orden), el
 * `timestamp` y el secreto de eventos, y saca el SHA-256. Si alguien manda
 * un evento falso sin conocer el secreto, el checksum no coincide.
 */
function firmaValida(evento) {
  if (!wompi.secretoEventos) return false;
  const propiedades = evento?.signature?.properties;
  const recibido = String(evento?.signature?.checksum ?? "");
  if (!Array.isArray(propiedades) || !recibido) return false;

  const valores = propiedades
    .map((ruta) => ruta.split(".").reduce((obj, clave) => obj?.[clave], evento.data))
    .join("");
  const calculado = createHash("sha256")
    .update(`${valores}${evento.timestamp}${wompi.secretoEventos}`)
    .digest("hex")
    .toUpperCase();

  const a = Buffer.from(calculado);
  const b = Buffer.from(recibido.toUpperCase());
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * Registra el abono de una transacción aprobada. Idempotente: si ya se
 * registró (Wompi reintenta el webhook, o se verificó a mano antes), no hace
 * nada.
 *
 * Devuelve { resultado, id_pago?, id_venta? } donde resultado es
 * registrado | ya_registrado | no_aprobada | link_desconocido | venta_anulada
 */
async function aplicarTransaccion(tx) {
  if (!tx?.payment_link_id) return { resultado: "link_desconocido" };

  return transaccion(async (db) => {
    const { rows } = await db.query("SELECT * FROM wompi_links WHERE id_link = $1 FOR UPDATE", [tx.payment_link_id]);
    const link = rows[0];
    if (!link) return { resultado: "link_desconocido" };

    if (tx.status !== "APPROVED") {
      // Un rechazo no gasta el link: el cliente puede intentar de nuevo.
      return { resultado: "no_aprobada", estado: tx.status, id_venta: link.id_venta };
    }

    const { rows: previo } = await db.query("SELECT id_pago FROM pagos WHERE wompi_transaccion_id = $1", [tx.id]);
    if (previo[0]) return { resultado: "ya_registrado", id_pago: previo[0].id_pago, id_venta: link.id_venta };

    const { rows: v } = await db.query("SELECT estado FROM ventas WHERE id_venta = $1 FOR UPDATE", [link.id_venta]);
    if (v[0]?.estado === "anulada") {
      // El dinero entró pero la venta ya no existe: se deja constancia en el
      // link para devolverlo, en vez de aplicarlo a una venta anulada.
      await db.query("UPDATE wompi_links SET estado = 'anulado' WHERE id_link = $1", [link.id_link]);
      return { resultado: "venta_anulada", id_venta: link.id_venta };
    }

    // El monto es el que Wompi cobró de verdad, no el que se pidió.
    const monto = Number(tx.amount_in_cents) / 100;
    const { rows: pago } = await db.query(
      `INSERT INTO pagos (id_venta, monto, metodo, referencia, nota, wompi_transaccion_id)
       VALUES ($1, $2, 'wompi', $3, $4, $5)
       ON CONFLICT (wompi_transaccion_id) DO NOTHING
       RETURNING id_pago`,
      [
        link.id_venta,
        monto,
        tx.id,
        `Wompi ${tx.payment_method_type ?? ""} - link ${link.id_link}`.trim(),
        tx.id
      ]
    );
    if (!pago[0]) return { resultado: "ya_registrado", id_venta: link.id_venta };

    await db.query("UPDATE wompi_links SET estado = 'pagado', id_pago = $2 WHERE id_link = $1", [link.id_link, pago[0].id_pago]);
    return { resultado: "registrado", id_pago: pago[0].id_pago, id_venta: link.id_venta };
  });
}

function estadoConfiguracion() {
  return {
    entorno: wompi.entorno,
    links: Boolean(wompi.llavePrivada),
    webhook: Boolean(wompi.secretoEventos)
  };
}

export { crearLink, consultarTransaccion, firmaValida, aplicarTransaccion, estadoConfiguracion };
