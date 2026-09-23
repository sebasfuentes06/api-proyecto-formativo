import { plantilla } from "./estilos.js";

/**
 * Portada de la API.
 *
 * Abrir la raíz en un navegador y encontrarse un JSON crudo no le dice nada a
 * quien llega por primera vez. Esta página explica qué es la API, qué recursos
 * expone y a dónde ir, y muestra cifras traídas en vivo de la base de datos:
 * si se ven, es la prueba de que todo está conectado.
 *
 * El JSON de siempre no desapareció: vive en /api, y es lo que recibe quien
 * consulte con curl o desde código.
 */

const RECURSOS = [
  {
    nombre: "Categorías",
    ruta: "categorias",
    descripcion: "Tipos de fragancia: floral, amaderado, cítrico, oriental.",
    clave: "categorias"
  },
  {
    nombre: "Proveedores",
    ruta: "proveedores",
    descripcion: "Empresas que surten los productos, con su contacto y calificación.",
    clave: "proveedores"
  },
  {
    nombre: "Clientes",
    ruta: "clientes",
    descripcion: "Personas registradas en la tienda.",
    clave: "clientes"
  },
  {
    nombre: "Productos",
    ruta: "productos",
    descripcion: "Las fragancias. Cada una pertenece a una categoría y a un proveedor.",
    clave: "productos"
  }
];

const OPERACIONES = [
  { metodo: "GET", ruta: "/api/{recurso}", que: "Listar, con búsqueda, filtros y paginación" },
  { metodo: "GET", ruta: "/api/{recurso}/{id}", que: "Obtener uno" },
  { metodo: "POST", ruta: "/api/{recurso}", que: "Crear" },
  { metodo: "PUT", ruta: "/api/{recurso}/{id}", que: "Actualizar" },
  { metodo: "DELETE", ruta: "/api/{recurso}/{id}", que: "Eliminar" }
];

function paginaInicio() {
  const tarjetasRecurso = RECURSOS.map(
    (r) => `
      <div class="tarjeta">
        <h3>${r.nombre}</h3>
        <p>${r.descripcion}</p>
        <p style="margin-top:12px">
          <code>/api/${r.ruta}</code>
        </p>
      </div>`
  ).join("");

  const filasOperacion = OPERACIONES.map(
    (o) => `
      <li>
        <span class="metodo m-${o.metodo.toLowerCase()}">${o.metodo}</span>
        <code style="margin-right:auto">${o.ruta}</code>
        <span style="color:var(--texto-tenue)">${o.que}</span>
      </li>`
  ).join("");

  const cuerpo = `
<main class="contenedor">

  <section class="heroe">
    <h1>API de gestión de fragancias</h1>
    <p class="entrada">
      Interfaz REST del sistema <strong>Essence Don Aire</strong>. Expone cuatro
      recursos con operaciones completas de creación, consulta, actualización y
      eliminación, sobre una base de datos PostgreSQL alojada en la nube.
    </p>
    <div class="fila">
      <a class="boton boton-principal" href="/docs">Documentación interactiva</a>
      <a class="boton boton-borde" href="/panel">Abrir el panel</a>
      <a class="boton boton-borde" href="/api">Respuesta en JSON</a>
    </div>
  </section>

  <section class="seccion">
    <h2>Datos en este momento</h2>
    <p class="sub">
      Traídos en vivo de la base de datos al cargar esta página. Si los ves, la
      conexión funciona.
    </p>
    <div id="cifras" class="rejilla rejilla-4">
      <div class="tarjeta dato"><div class="numero">—</div><div class="etiqueta">Cargando</div></div>
    </div>
  </section>

  <section class="seccion">
    <h2>Recursos</h2>
    <p class="sub">Cada uno responde a las mismas cinco operaciones.</p>
    <div class="rejilla rejilla-2">${tarjetasRecurso}</div>
  </section>

  <section class="seccion">
    <h2>Operaciones</h2>
    <p class="sub">
      Donde <code>{recurso}</code> es <code>categorias</code>,
      <code>proveedores</code>, <code>clientes</code> o <code>productos</code>.
      Veinte operaciones en total.
    </p>
    <div class="tarjeta">
      <ul class="lista-limpia">${filasOperacion}</ul>
    </div>
  </section>

  <section class="seccion">
    <h2>Cómo se consume</h2>
    <p class="sub">Sin llaves ni autenticación: es una API de demostración académica.</p>
    <div class="rejilla rejilla-2">
      <div class="tarjeta">
        <h3>Desde la terminal</h3>
        <pre class="mono" style="margin:12px 0 0;overflow-x:auto;background:#f7f4f0;padding:13px;border-radius:8px;font-size:.82rem"><code style="background:none;padding:0;color:inherit">curl <span id="urlCurl">.</span>/api/productos?stockBajo=1</code></pre>
      </div>
      <div class="tarjeta">
        <h3>Desde código</h3>
        <pre class="mono" style="margin:12px 0 0;overflow-x:auto;background:#f7f4f0;padding:13px;border-radius:8px;font-size:.82rem"><code style="background:none;padding:0;color:inherit">const r = await fetch(url + "/api/productos");
const { datos } = await r.json();</code></pre>
      </div>
    </div>
  </section>

  <section class="seccion">
    <h2>Cómo está construida</h2>
    <div class="rejilla rejilla-2">
      <div class="tarjeta">
        <h3>SQL parametrizado, sin ORM</h3>
        <p>
          Los valores nunca se concatenan dentro de la consulta: van aparte, como
          <code>$1</code>, <code>$2</code>. Las columnas de ordenamiento pasan por
          una lista blanca, porque esas no se pueden parametrizar.
        </p>
      </div>
      <div class="tarjeta">
        <h3>Separada en capas</h3>
        <p>
          Rutas, controladores y modelos son archivos distintos. El controlador no
          escribe SQL y el modelo no sabe qué es HTTP.
        </p>
      </div>
      <div class="tarjeta">
        <h3>Errores traducidos</h3>
        <p>
          Un correo repetido devuelve un mensaje entendible, no
          <span class="mono">duplicate key value violates unique constraint</span>.
        </p>
      </div>
      <div class="tarjeta">
        <h3>El trabajo lo hace PostgreSQL</h3>
        <p>
          Búsqueda, filtros, orden y paginación se resuelven en la consulta, no
          trayendo la tabla entera para descartar filas en JavaScript.
        </p>
      </div>
    </div>
  </section>

</main>`;

  const script = `
document.getElementById("urlCurl").textContent = location.origin;

/** Pide solo un registro de cada recurso: lo que interesa es el total. */
async function contar(ruta) {
  const r = await fetch("/api/" + ruta + "?limit=1");
  if (!r.ok) throw new Error(ruta);
  const cuerpo = await r.json();
  return cuerpo.paginacion.total;
}

const RECURSOS = ${JSON.stringify(RECURSOS.map((r) => ({ nombre: r.nombre, ruta: r.ruta })))};

(async () => {
  const caja = document.getElementById("cifras");
  try {
    const totales = await Promise.all(RECURSOS.map((r) => contar(r.ruta)));
    caja.innerHTML = RECURSOS.map((r, i) =>
      '<div class="tarjeta dato"><div class="numero">' + totales[i] +
      '</div><div class="etiqueta">' + r.nombre + '</div></div>'
    ).join("");
  } catch {
    caja.innerHTML =
      '<div class="aviso aviso-error" style="grid-column:1/-1;margin:0">' +
      'No se pudo consultar la base de datos. Revisa <a href="/api/health">el estado del servicio</a>.' +
      '</div>';
  }
})();
`;

  return plantilla({
    titulo: "API Essence Don Aire",
    activo: "/",
    cuerpo,
    script
  });
}

export { paginaInicio };
