import "dotenv/config";

/**
 * Configuración de la aplicación.
 *
 * Todo lo que cambia entre tu equipo y el servidor (claves, host de la base,
 * puerto) sale de variables de entorno, nunca del código. Por eso el archivo
 * .env no se sube al repositorio: lleva la contraseña de la base de datos.
 */

/**
 * La conexión a PostgreSQL admite dos formas:
 *   1. DATABASE_URL: una sola cadena. Es lo que entregan los servicios en la
 *      nube (Neon, Supabase, Render) y lo que se configura al desplegar.
 *   2. PGHOST/PGUSER/...: variables sueltas, cómodas en local.
 */
const databaseUrl = process.env.DATABASE_URL ?? null;

/** ¿La base está en este mismo equipo? De eso depende si se usa SSL. */
function esLocal() {
  if (databaseUrl) return /@(localhost|127\.0\.0\.1)[:/]/.test(databaseUrl);
  return ["localhost", "127.0.0.1"].includes(process.env.PGHOST ?? "localhost");
}

/**
 * SSL: los PostgreSQL en la nube exigen conexión cifrada; el de tu equipo no
 * lo tiene configurado. Se decide solo, y se puede forzar con PGSSL.
 *
 * `rejectUnauthorized: false` porque esos servicios firman su certificado con
 * una autoridad que Node no trae en su lista; sin esto la conexión falla con
 * "self signed certificate in certificate chain".
 */
function resolverSsl() {
  const forzado = process.env.PGSSL;
  if (forzado !== undefined) {
    return ["1", "true", "require"].includes(String(forzado).toLowerCase())
      ? { rejectUnauthorized: false }
      : false;
  }
  return esLocal() ? false : { rejectUnauthorized: false };
}

const env = {
  port: Number(process.env.PORT ?? 3000),
  entorno: process.env.NODE_ENV ?? "development",
  // Vercel define esta variable en sus despliegues. Allá la API corre como
  // función y no hay que abrir ningún puerto.
  esServerless: Boolean(process.env.VERCEL),
  corsOrigins: (process.env.CORS_ORIGINS ?? "*")
    .split(",")
    .map((origen) => origen.trim())
    .filter(Boolean),
  // Firma de los tokens de sesión de la app móvil. En Vercel es OBLIGATORIO
  // definirla (Settings > Environment Variables): si falta, el login responde
  // un error claro en vez de firmar con una clave conocida por todos.
  jwtSecreto: process.env.JWT_SECRETO ?? null,
  jwtDuracion: process.env.JWT_DURACION ?? "7d",
  /**
   * Wompi (pasarela de pagos colombiana). En modo "sandbox" no se mueve
   * dinero real: se paga con tarjetas y cuentas de prueba.
   * Las llaves salen de https://comercios.wompi.co > Desarrolladores.
   */
  wompi: {
    entorno: process.env.WOMPI_ENTORNO === "production" ? "production" : "sandbox",
    apiUrl:
      process.env.WOMPI_API_URL ??
      (process.env.WOMPI_ENTORNO === "production"
        ? "https://production.wompi.co/v1"
        : "https://sandbox.wompi.co/v1"),
    llavePublica: process.env.WOMPI_LLAVE_PUBLICA ?? null,
    llavePrivada: process.env.WOMPI_LLAVE_PRIVADA ?? null,
    secretoEventos: process.env.WOMPI_SECRETO_EVENTOS ?? null,
    checkoutUrl: process.env.WOMPI_CHECKOUT_URL ?? "https://checkout.wompi.co/l/"
  },
  /**
   * Correo saliente (códigos de recuperación y avisos de registro).
   * Funciona con cualquier SMTP. Con Gmail: smtp.gmail.com, puerto 465, tu
   * correo y una "contraseña de aplicación" de 16 letras (no tu clave normal).
   *
   * CORREO_MODO=prueba no envía nada: guarda el último correo en memoria para
   * las pruebas automáticas. Nunca se activa en Vercel.
   */
  correo: {
    host: process.env.CORREO_SMTP_HOST ?? null,
    puerto: Number(process.env.CORREO_SMTP_PUERTO ?? 465),
    usuario: process.env.CORREO_USUARIO ?? null,
    clave: process.env.CORREO_CLAVE ?? null,
    remitente: process.env.CORREO_REMITENTE ?? process.env.CORREO_USUARIO ?? null,
    modoPrueba: process.env.CORREO_MODO === "prueba" && !process.env.VERCEL
  },
  /**
   * Datos que la app le muestra al cliente para pagar. Se cambian en Vercel
   * sin publicar otra versión de la app.
   *   PAGO_TRANSFERENCIA_INFO  ej. "Nequi 300 123 4567 a nombre de Yésica ..."
   *   PUNTO_FISICO_DIRECCION   ej. "Cra 30 # 29-15, La Pintada (Antioquia)"
   */
  pagos: {
    transferencia: process.env.PAGO_TRANSFERENCIA_INFO?.trim() || null,
    puntoFisico: process.env.PUNTO_FISICO_DIRECCION?.trim() || "Punto físico en La Pintada, Antioquia"
  },
  db: {
    connectionString: databaseUrl,
    ssl: resolverSsl(),
    host: process.env.PGHOST ?? "localhost",
    port: Number(process.env.PGPORT ?? 5432),
    database: process.env.PGDATABASE ?? "essence_api",
    user: process.env.PGUSER ?? "postgres",
    password: process.env.PGPASSWORD ?? ""
  }
};

export { env };
