import { plantilla } from "./estilos.js";

/**
 * Cliente de demostración.
 *
 * Una página que consume esta misma API desde el navegador y ejerce las cinco
 * operaciones sobre productos: listar con filtros, ver, crear, editar y
 * eliminar. Es la prueba de que la API sirve para algo, no solo de que
 * devuelve JSON.
 *
 * Está escrita en JavaScript sin librerías, a propósito: así se ve que lo que
 * hace el trabajo es la API, no un framework.
 *
 * El panel de la derecha registra cada petición con su método, su ruta y el
 * código que devolvió. Sirve para mostrar en una sustentación que cada clic
 * de la interfaz es una llamada HTTP de verdad.
 */
function paginaDemo() {
  const cuerpo = `
<main class="contenedor ancho">

  <section class="heroe" style="padding-bottom:26px">
    <h1>La API en uso</h1>
    <p class="entrada">
      Esta página no tiene datos propios: todo lo que ves lo pide a
      <code>/api/productos</code>. Buscar, filtrar, crear, editar y eliminar son
      llamadas HTTP reales contra la base de datos.
    </p>
  </section>

  <section class="seccion" style="padding-top:0">
    <div class="barra-filtros">
      <input id="buscar" type="search" placeholder="Buscar por nombre, SKU o descripción">
      <select id="categoria"><option value="">Todas las categorías</option></select>
      <select id="estado">
        <option value="all">Todos los estados</option>
        <option value="active">Solo activos</option>
        <option value="inactive">Solo inactivos</option>
      </select>
      <select id="orden">
        <option value="nombre|asc">Nombre (A-Z)</option>
        <option value="nombre|desc">Nombre (Z-A)</option>
        <option value="precio|asc">Precio (menor primero)</option>
        <option value="precio|desc">Precio (mayor primero)</option>
        <option value="stock|asc">Stock (menor primero)</option>
        <option value="fecha_creacion|desc">Más recientes</option>
      </select>
      <button id="nuevo" class="boton boton-principal">+ Nuevo producto</button>
    </div>

    <div class="fila" style="margin-bottom:16px">
      <label class="fila" style="gap:7px;font-size:.9rem;cursor:pointer">
        <input type="checkbox" id="stockBajo" style="width:auto;margin:0">
        Solo productos en stock bajo
      </label>
      <span id="resumen" style="margin-left:auto;color:var(--texto-tenue);font-size:.88rem"></span>
    </div>

    <div id="avisoLista"></div>

    <div class="marco-tabla">
      <div class="desplazable">
        <table>
          <thead>
            <tr>
              <th>SKU</th><th>Producto</th><th>Categoría</th><th>Proveedor</th>
              <th class="num">Precio</th><th class="num">Stock</th>
              <th>Estado</th><th></th>
            </tr>
          </thead>
          <tbody id="filas">
            <tr><td colspan="8" class="cargando">Cargando productos…</td></tr>
          </tbody>
        </table>
      </div>
      <div class="paginacion">
        <span id="textoPagina">—</span>
        <span class="fila" style="gap:8px">
          <button id="anterior" class="boton boton-borde boton-chico">Anterior</button>
          <button id="siguiente" class="boton boton-borde boton-chico">Siguiente</button>
        </span>
      </div>
    </div>
  </section>

  <section class="seccion" style="padding-top:26px">
    <h2>Peticiones</h2>
    <p class="sub">
      Cada acción de arriba es una llamada HTTP. Aquí queda registrada con su
      método, su ruta y el código que devolvió el servidor.
    </p>
    <div class="tarjeta" style="padding:0;overflow:hidden">
      <ul id="bitacora" class="lista-limpia" style="max-height:300px;overflow-y:auto">
        <li style="color:var(--texto-tenue);font-size:.86rem;padding:14px 18px">
          Sin peticiones todavía
        </li>
      </ul>
    </div>
  </section>

</main>

<div id="modal"></div>

`;

  const script = `
/* ------------------------------------------------------------------
   Estado de la pantalla
------------------------------------------------------------------ */
var estado = {
  pagina: 1,
  porPagina: 8,
  totalPaginas: 1,
  total: 0,
  categorias: [],
  proveedores: [],
  editando: null
};

var $ = function (id) { return document.getElementById(id); };

/* ------------------------------------------------------------------
   Llamadas a la API
   Todas pasan por aquí para que queden registradas en la bitácora.
------------------------------------------------------------------ */
function anotar(metodo, ruta, codigo, ok) {
  var lista = $("bitacora");
  if (lista.dataset.limpia !== "1") { lista.innerHTML = ""; lista.dataset.limpia = "1"; }

  var li = document.createElement("li");
  li.style.cssText = "padding:10px 18px;gap:12px";
  li.innerHTML =
    '<span class="metodo m-' + metodo.toLowerCase() + '">' + metodo + '</span>' +
    '<span class="mono" style="color:var(--texto-tenue);word-break:break-all;margin-right:auto">' +
      ruta + '</span>' +
    '<span class="pastilla ' + (ok ? "pastilla-ok" : "pastilla-alerta") + '">' + codigo + '</span>';
  lista.prepend(li);

  while (lista.children.length > 25) lista.removeChild(lista.lastChild);
}

async function api(metodo, ruta, cuerpo) {
  var opciones = { method: metodo, headers: {} };
  if (cuerpo !== undefined) {
    opciones.headers["Content-Type"] = "application/json";
    opciones.body = JSON.stringify(cuerpo);
  }

  var respuesta, datos = null;
  try {
    respuesta = await fetch(ruta, opciones);
  } catch (e) {
    anotar(metodo, ruta, "sin red", false);
    throw new Error("No se pudo conectar con la API.");
  }

  try { datos = await respuesta.json(); } catch (e) { datos = null; }
  anotar(metodo, ruta, respuesta.status, respuesta.ok);

  if (!respuesta.ok) {
    var error = new Error((datos && datos.error) || "Error " + respuesta.status);
    error.detalles = datos && datos.detalles;
    error.codigo = respuesta.status;
    throw error;
  }
  return datos;
}

/* ------------------------------------------------------------------
   Utilidades de presentación
------------------------------------------------------------------ */
var pesos = new Intl.NumberFormat("es-CO", {
  style: "currency", currency: "COP", maximumFractionDigits: 0
});

function limpiar(texto) {
  return String(texto === null || texto === undefined ? "" : texto)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function avisar(donde, mensaje, tipo) {
  $(donde).innerHTML = mensaje
    ? '<div class="aviso aviso-' + (tipo || "error") + '">' + limpiar(mensaje) + '</div>'
    : "";
}

/* ------------------------------------------------------------------
   Listado
------------------------------------------------------------------ */
function construirConsulta() {
  var partes = ["page=" + estado.pagina, "limit=" + estado.porPagina];
  var texto = $("buscar").value.trim();
  if (texto) partes.push("search=" + encodeURIComponent(texto));
  if ($("categoria").value) partes.push("categoria=" + $("categoria").value);
  if ($("estado").value !== "all") partes.push("status=" + $("estado").value);
  if ($("stockBajo").checked) partes.push("stockBajo=1");
  var orden = $("orden").value.split("|");
  partes.push("sortBy=" + orden[0], "sortDir=" + orden[1]);
  return "/api/productos?" + partes.join("&");
}

async function cargar() {
  avisar("avisoLista", "");
  try {
    var respuesta = await api("GET", construirConsulta());
    pintar(respuesta.datos);
    estado.totalPaginas = respuesta.paginacion.totalPaginas;
    estado.total = respuesta.paginacion.total;

    $("textoPagina").textContent =
      "Página " + respuesta.paginacion.pagina + " de " + respuesta.paginacion.totalPaginas +
      " · " + respuesta.paginacion.total + " producto(s)";
    $("resumen").textContent = respuesta.paginacion.total + " resultado(s)";
    $("anterior").disabled = respuesta.paginacion.pagina <= 1;
    $("siguiente").disabled = respuesta.paginacion.pagina >= respuesta.paginacion.totalPaginas;
  } catch (e) {
    avisar("avisoLista", e.message);
    $("filas").innerHTML = '<tr><td colspan="8" class="vacio">No se pudieron cargar los productos.</td></tr>';
  }
}

function pintar(productos) {
  if (!productos.length) {
    $("filas").innerHTML =
      '<tr><td colspan="8" class="vacio">Ningún producto coincide con los filtros.</td></tr>';
    return;
  }

  $("filas").innerHTML = productos.map(function (p) {
    var alerta = p.stock_bajo
      ? ' <span class="pastilla pastilla-alerta">bajo</span>' : "";
    return '<tr>' +
      '<td class="mono firme" style="color:var(--texto-tenue);font-size:.8rem">' +
        limpiar(p.sku) + '</td>' +
      '<td><strong>' + limpiar(p.nombre) + '</strong>' +
        (p.descripcion
          ? '<span class="recortado" style="font-size:.82rem;color:var(--texto-tenue)" title="' +
            limpiar(p.descripcion) + '">' + limpiar(p.descripcion) + '</span>'
          : "") +
      '</td>' +
      '<td class="firme"><span class="pastilla pastilla-suave">' + limpiar(p.categoria) + '</span></td>' +
      '<td style="font-size:.84rem;max-width:22ch">' + limpiar(p.proveedor) + '</td>' +
      '<td class="num">' + pesos.format(Number(p.precio)) + '</td>' +
      '<td class="num">' + p.stock + ' / ' + p.stock_minimo + alerta + '</td>' +
      '<td class="firme"><span class="pastilla ' + (p.estado ? "pastilla-ok" : "pastilla-no") + '">' +
        (p.estado ? "Activo" : "Inactivo") + '</span></td>' +
      '<td class="num" style="white-space:nowrap">' +
        '<button class="boton boton-borde boton-chico" data-editar="' + p.id_producto + '">Editar</button> ' +
        '<button class="boton boton-peligro boton-chico" data-borrar="' + p.id_producto +
          '" data-nombre="' + limpiar(p.nombre) + '">Eliminar</button>' +
      '</td>' +
    '</tr>';
  }).join("");
}

/* ------------------------------------------------------------------
   Formulario de crear / editar
------------------------------------------------------------------ */
function opciones(lista, campoId, campoNombre, elegido) {
  return lista.map(function (x) {
    var id = x[campoId];
    return '<option value="' + id + '"' + (String(id) === String(elegido) ? " selected" : "") +
      '>' + limpiar(x[campoNombre]) + '</option>';
  }).join("");
}

function abrirFormulario(producto) {
  estado.editando = producto || null;
  var p = producto || {};
  var esEdicion = Boolean(producto);

  $("modal").innerHTML =
    '<div class="fondo-modal" id="fondoModal">' +
      '<div class="modal">' +
        '<div class="modal-cabeza">' +
          '<h3>' + (esEdicion ? "Editar producto" : "Nuevo producto") + '</h3>' +
          '<button class="cerrar" id="cerrarModal">&times;</button>' +
        '</div>' +
        '<div class="modal-cuerpo">' +
          '<div id="avisoForm"></div>' +
          '<div class="campo"><label for="f_sku">SKU *</label>' +
            '<input id="f_sku" value="' + limpiar(p.sku) + '" placeholder="FLO-ROS-001">' +
            '<span class="error-campo" id="e_sku"></span></div>' +
          '<div class="campo"><label for="f_nombre">Nombre *</label>' +
            '<input id="f_nombre" value="' + limpiar(p.nombre) + '" placeholder="Rosa Eterna">' +
            '<span class="error-campo" id="e_nombre"></span></div>' +
          '<div class="campo"><label for="f_descripcion">Descripción</label>' +
            '<input id="f_descripcion" value="' + limpiar(p.descripcion) + '"></div>' +
          '<div class="campo"><label for="f_id_categoria">Categoría *</label>' +
            '<select id="f_id_categoria">' +
              opciones(estado.categorias, "id_categoria", "nombre", p.id_categoria) +
            '</select><span class="error-campo" id="e_id_categoria"></span></div>' +
          '<div class="campo"><label for="f_id_proveedor">Proveedor *</label>' +
            '<select id="f_id_proveedor">' +
              opciones(estado.proveedores, "id_proveedor", "nombre", p.id_proveedor) +
            '</select><span class="error-campo" id="e_id_proveedor"></span></div>' +
          '<div style="display:grid;gap:15px;grid-template-columns:repeat(3,1fr)">' +
            '<div class="campo"><label for="f_precio">Precio *</label>' +
              '<input id="f_precio" type="number" min="0" value="' +
                (p.precio !== undefined ? Number(p.precio) : "") + '">' +
              '<span class="error-campo" id="e_precio"></span></div>' +
            '<div class="campo"><label for="f_stock">Stock</label>' +
              '<input id="f_stock" type="number" min="0" value="' +
                (p.stock !== undefined ? p.stock : 0) + '"></div>' +
            '<div class="campo"><label for="f_stock_minimo">Stock mínimo</label>' +
              '<input id="f_stock_minimo" type="number" min="0" value="' +
                (p.stock_minimo !== undefined ? p.stock_minimo : 0) + '"></div>' +
          '</div>' +
          '<div class="campo"><label for="f_estado">Estado</label>' +
            '<select id="f_estado">' +
              '<option value="true"' + (p.estado === false ? "" : " selected") + '>Activo</option>' +
              '<option value="false"' + (p.estado === false ? " selected" : "") + '>Inactivo</option>' +
            '</select></div>' +
        '</div>' +
        '<div class="modal-pie">' +
          '<button class="boton boton-borde" id="cancelar">Cancelar</button>' +
          '<button class="boton boton-principal" id="guardar">' +
            (esEdicion ? "Guardar cambios" : "Crear producto") + '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  $("cerrarModal").onclick = cerrarModal;
  $("cancelar").onclick = cerrarModal;
  $("fondoModal").onclick = function (ev) { if (ev.target.id === "fondoModal") cerrarModal(); };
  $("guardar").onclick = guardar;
  $("f_sku").focus();
}

function cerrarModal() {
  $("modal").innerHTML = "";
  estado.editando = null;
}

function marcarErrores(detalles) {
  ["sku", "nombre", "id_categoria", "id_proveedor", "precio"].forEach(function (campo) {
    var span = $("e_" + campo), entrada = $("f_" + campo);
    if (!span) return;
    var mensaje = detalles && detalles[campo];
    span.textContent = mensaje || "";
    if (entrada) entrada.classList.toggle("malo", Boolean(mensaje));
  });
}

async function guardar() {
  marcarErrores(null);
  avisar("avisoForm", "");

  var cuerpo = {
    sku: $("f_sku").value.trim(),
    nombre: $("f_nombre").value.trim(),
    descripcion: $("f_descripcion").value.trim(),
    id_categoria: Number($("f_id_categoria").value),
    id_proveedor: Number($("f_id_proveedor").value),
    precio: Number($("f_precio").value),
    stock: Number($("f_stock").value),
    stock_minimo: Number($("f_stock_minimo").value),
    estado: $("f_estado").value === "true"
  };

  var boton = $("guardar");
  boton.disabled = true;
  boton.textContent = "Guardando…";

  try {
    if (estado.editando) {
      await api("PUT", "/api/productos/" + estado.editando.id_producto, cuerpo);
    } else {
      await api("POST", "/api/productos", cuerpo);
    }
    cerrarModal();
    await cargar();
  } catch (e) {
    avisar("avisoForm", e.message);
    marcarErrores(e.detalles);
    boton.disabled = false;
    boton.textContent = estado.editando ? "Guardar cambios" : "Crear producto";
  }
}

/* ------------------------------------------------------------------
   Eliminar
------------------------------------------------------------------ */
function confirmarBorrado(id, nombre) {
  $("modal").innerHTML =
    '<div class="fondo-modal" id="fondoModal">' +
      '<div class="modal" style="max-width:430px">' +
        '<div class="modal-cabeza"><h3>¿Eliminar este producto?</h3>' +
          '<button class="cerrar" id="cerrarModal">&times;</button></div>' +
        '<div class="modal-cuerpo">' +
          '<div id="avisoBorrar"></div>' +
          '<p style="margin:0">Se va a eliminar <strong>' + limpiar(nombre) +
            '</strong>. Esta acción no se puede deshacer.</p>' +
        '</div>' +
        '<div class="modal-pie">' +
          '<button class="boton boton-borde" id="cancelar">Cancelar</button>' +
          '<button class="boton boton-peligro" id="confirmar">Sí, eliminar</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  $("cerrarModal").onclick = cerrarModal;
  $("cancelar").onclick = cerrarModal;
  $("fondoModal").onclick = function (ev) { if (ev.target.id === "fondoModal") cerrarModal(); };

  $("confirmar").onclick = async function () {
    this.disabled = true;
    this.textContent = "Eliminando…";
    try {
      await api("DELETE", "/api/productos/" + id);
      cerrarModal();
      await cargar();
    } catch (e) {
      avisar("avisoBorrar", e.message);
      this.disabled = false;
      this.textContent = "Sí, eliminar";
    }
  };
}

/* ------------------------------------------------------------------
   Arranque
------------------------------------------------------------------ */
var esperar = null;
function recargarDesdeCero() {
  estado.pagina = 1;
  cargar();
}

$("buscar").addEventListener("input", function () {
  clearTimeout(esperar);
  esperar = setTimeout(recargarDesdeCero, 350);
});
["categoria", "estado", "orden"].forEach(function (id) {
  $(id).addEventListener("change", recargarDesdeCero);
});
$("stockBajo").addEventListener("change", recargarDesdeCero);

$("anterior").onclick = function () {
  if (estado.pagina > 1) { estado.pagina--; cargar(); }
};
$("siguiente").onclick = function () {
  if (estado.pagina < estado.totalPaginas) { estado.pagina++; cargar(); }
};

$("nuevo").onclick = function () { abrirFormulario(null); };

$("filas").addEventListener("click", function (ev) {
  var editar = ev.target.getAttribute("data-editar");
  var borrar = ev.target.getAttribute("data-borrar");
  if (editar) {
    api("GET", "/api/productos/" + editar)
      .then(function (r) { abrirFormulario(r.datos); })
      .catch(function (e) { avisar("avisoLista", e.message); });
  }
  if (borrar) confirmarBorrado(borrar, ev.target.getAttribute("data-nombre"));
});

document.addEventListener("keydown", function (ev) {
  if (ev.key === "Escape") cerrarModal();
});

/** Las listas de categorías y proveedores se cargan una sola vez. */
(async function iniciar() {
  try {
    var cats = await api("GET", "/api/categorias?limit=100&status=active");
    var provs = await api("GET", "/api/proveedores?limit=100&status=active");
    estado.categorias = cats.datos;
    estado.proveedores = provs.datos;

    $("categoria").innerHTML = '<option value="">Todas las categorías</option>' +
      cats.datos.map(function (c) {
        return '<option value="' + c.id_categoria + '">' + limpiar(c.nombre) + '</option>';
      }).join("");
  } catch (e) {
    avisar("avisoLista", "No se pudieron cargar las listas de apoyo: " + e.message);
  }
  cargar();
})();
`;

  return plantilla({
    titulo: "Demostración — API Essence Don Aire",
    activo: "/demo",
    cuerpo,
    script
  });
}

export { paginaDemo };
