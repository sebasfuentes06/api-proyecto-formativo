import nodemailer from "nodemailer";
import { env } from "../config/env.js";

/**
 * Envío de correos: código para restablecer la contraseña y avisos del
 * registro (solicitud recibida, nueva solicitud para el administrador,
 * cuenta aprobada o rechazada).
 *
 * Si el correo no está configurado, la API sigue funcionando: los avisos
 * simplemente no salen (queda registro en los logs). La recuperación de
 * contraseña sí lo necesita y responde un error claro.
 */

const { correo } = env;
const NEGOCIO = "Essence Don Aire";

/** Solo para las pruebas automáticas (CORREO_MODO=prueba). */
const bandejaPrueba = [];

/** Lo que escribe el usuario (nombre, motivo) no puede meter HTML en el correo. */
const esc = (t) =>
  String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

let transporte = null;
function obtenerTransporte() {
  if (transporte) return transporte;
  transporte = correo.modoPrueba
    ? nodemailer.createTransport({ jsonTransport: true })
    : nodemailer.createTransport({
        host: correo.host,
        port: correo.puerto,
        secure: correo.puerto === 465,
        auth: { user: correo.usuario, pass: correo.clave }
      });
  return transporte;
}

const configurado = () => correo.modoPrueba || Boolean(correo.host && correo.usuario && correo.clave);

/** Plantilla sencilla con los colores de la marca. */
function html(titulo, cuerpo) {
  return `<!doctype html><html><body style="margin:0;background:#f5eff3;font-family:Arial,sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px">
    <table width="480" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden">
      <tr><td style="background:#7a2e55;color:#fff;padding:18px 24px;font-size:20px;font-weight:bold">${NEGOCIO}</td></tr>
      <tr><td style="padding:24px;color:#2b2b2b;font-size:15px;line-height:1.5">
        <h2 style="margin:0 0 12px;font-size:18px">${titulo}</h2>${cuerpo}
      </td></tr>
      <tr><td style="padding:14px 24px;background:#faf6f8;color:#888;font-size:12px">
        La Pintada, Antioquia · Este es un mensaje automático, no lo respondas.
      </td></tr>
    </table>
  </td></tr></table></body></html>`;
}

async function enviar({ para, asunto, titulo, cuerpo, texto }) {
  if (!configurado()) {
    console.warn(`[correo] sin configurar: no se envió "${asunto}" a ${para}`);
    return { enviado: false };
  }
  const mensaje = {
    from: `${NEGOCIO} <${correo.remitente ?? "no-reply@essence.local"}>`,
    to: para,
    subject: asunto,
    text: texto,
    html: html(titulo, cuerpo)
  };
  await obtenerTransporte().sendMail(mensaje);
  if (correo.modoPrueba) {
    bandejaPrueba.push({ para, asunto, texto });
    if (bandejaPrueba.length > 50) bandejaPrueba.shift();
  }
  return { enviado: true };
}

/** Los avisos no deben tumbar la operación principal si el SMTP falla. */
async function enviarSinFallar(datos) {
  try {
    return await enviar(datos);
  } catch (error) {
    console.error(`[correo] no se pudo enviar "${datos.asunto}":`, error.message);
    return { enviado: false };
  }
}

const correos = {
  codigo: (para, nombre, codigo, minutos) =>
    enviar({
      para,
      asunto: `${codigo} es tu código para restablecer la contraseña`,
      titulo: "Restablecer contraseña",
      texto: `Hola ${nombre}. Tu código es ${codigo}. Vence en ${minutos} minutos. Si no lo pediste, ignora este correo.`,
      cuerpo: `<p>Hola ${esc(nombre)},</p><p>Usa este código en la app para crear una contraseña nueva:</p>
        <p style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#7a2e55;margin:16px 0">${codigo}</p>
        <p>Vence en <b>${minutos} minutos</b>. Si no lo pediste, ignora este correo: tu contraseña sigue igual.</p>`
    }),

  registroRecibido: (para, nombre) =>
    enviarSinFallar({
      para,
      asunto: "Recibimos tu registro",
      titulo: "¡Gracias por registrarte!",
      texto: `Hola ${nombre}. Recibimos tu solicitud. Te avisaremos por este medio cuando la administradora la apruebe.`,
      cuerpo: `<p>Hola ${esc(nombre)},</p><p>Recibimos tu solicitud de cuenta. La administradora la revisará y te
        avisaremos por este correo cuando esté aprobada para que puedas entrar a la app.</p>`
    }),

  nuevaSolicitud: (para, solicitante) =>
    enviarSinFallar({
      para,
      asunto: `Nueva solicitud de registro: ${solicitante.nombre}`,
      titulo: "Nueva solicitud de registro",
      texto: `${solicitante.nombre} (${solicitante.correo}, ${solicitante.telefono ?? "sin teléfono"}) pidió una cuenta. Apruébala en la app: avatar > Usuarios y roles > Pendientes.`,
      cuerpo: `<p><b>${esc(solicitante.nombre)}</b> pidió una cuenta en la app.</p>
        <p>Correo: ${esc(solicitante.correo)}<br>Teléfono: ${esc(solicitante.telefono ?? "—")}</p>
        <p>Para aprobarla o rechazarla: <b>avatar ▸ Usuarios y roles ▸ Pendientes</b>.</p>`
    }),

  aprobado: (para, nombre, rol) =>
    enviarSinFallar({
      para,
      asunto: "Tu cuenta fue aprobada",
      titulo: "¡Ya puedes entrar!",
      texto: `Hola ${nombre}. Tu cuenta fue aprobada con el rol ${rol}. Ya puedes iniciar sesión en la app con tu correo y contraseña.`,
      cuerpo: `<p>Hola ${esc(nombre)},</p><p>Tu cuenta fue aprobada con el rol <b>${esc(rol)}</b>. Ya puedes iniciar sesión
        en la app con tu correo y la contraseña que elegiste.</p>`
    }),

  rechazado: (para, nombre, motivo) =>
    enviarSinFallar({
      para,
      asunto: "Sobre tu solicitud de registro",
      titulo: "Solicitud no aprobada",
      texto: `Hola ${nombre}. Tu solicitud no fue aprobada. Motivo: ${motivo}. Si crees que es un error, escríbenos por WhatsApp.`,
      cuerpo: `<p>Hola ${esc(nombre)},</p><p>Tu solicitud de cuenta no fue aprobada.</p><p><b>Motivo:</b> ${esc(motivo)}</p>
        <p>Si crees que es un error, escríbenos por WhatsApp.</p>`
    })
};

export { correos, configurado as correoConfigurado, bandejaPrueba };
