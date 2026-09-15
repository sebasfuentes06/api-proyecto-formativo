/**
 * Página de documentación interactiva (Swagger UI).
 *
 * Swagger UI se carga desde un CDN en vez de instalarlo como dependencia.
 * La razón no es ahorrar un `npm install`: en un despliegue serverless como
 * Vercel, Express NO sirve archivos estáticos desde node_modules, así que la
 * librería `swagger-ui-express` cargaría la página sin estilos ni JavaScript
 * y se vería rota. Trayendo la interfaz del CDN y sirviendo únicamente la
 * especificación desde la API, funciona igual en local y desplegada.
 */

const VERSION_SWAGGER = "5.32.15";
const CDN = `https://cdn.jsdelivr.net/npm/swagger-ui-dist@${VERSION_SWAGGER}`;

/** Devuelve el HTML de la página. `rutaSpec` es de dónde saca el JSON. */
function paginaDocumentacion(rutaSpec = "/api/openapi.json") {
  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>API Proyecto Formativo — Documentación</title>
  <link rel="stylesheet" href="${CDN}/swagger-ui.css">
  <style>
    body { margin: 0; background: #fafafa; }
    .topbar { display: none; }
    .swagger-ui .info { margin: 32px 0; }
    .swagger-ui .info .title { font-size: 2rem; }
    .encabezado {
      background: #1a1a2e;
      color: #fff;
      padding: 20px 24px;
      font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
    }
    .encabezado h1 { margin: 0 0 4px; font-size: 1.15rem; font-weight: 600; }
    .encabezado p { margin: 0; font-size: .875rem; opacity: .75; }
    .encabezado a { color: #9ad; }
    .cargando {
      padding: 48px 24px;
      font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="encabezado">
    <h1>API Proyecto Formativo — Essence Don Aire</h1>
    <p>
      Node.js + Express + PostgreSQL ·
      <a href="${rutaSpec}">especificación OpenAPI</a> ·
      <a href="/api/health">estado del servicio</a>
    </p>
  </div>

  <div id="swagger-ui"><p class="cargando">Cargando la documentación…</p></div>

  <script src="${CDN}/swagger-ui-bundle.js" crossorigin></script>
  <script src="${CDN}/swagger-ui-standalone-preset.js" crossorigin></script>
  <script>
    window.addEventListener("load", function () {
      if (typeof SwaggerUIBundle === "undefined") {
        document.getElementById("swagger-ui").innerHTML =
          '<p class="cargando">No se pudo cargar Swagger UI desde el CDN. ' +
          'Revisa tu conexión, o abre <a href="${rutaSpec}">la especificación</a> directamente.</p>';
        return;
      }
      SwaggerUIBundle({
        url: "${rutaSpec}",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
        layout: "BaseLayout",
        docExpansion: "list",
        defaultModelsExpandDepth: -1,
        tryItOutEnabled: true,
        persistAuthorization: true
      });
    });
  </script>
</body>
</html>`;
}

export { paginaDocumentacion };
