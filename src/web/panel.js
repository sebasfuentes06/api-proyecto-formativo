import { plantilla, icono, SELLO } from "./estilos.js";

/**
 * Panel de administración.
 *
 * Una aplicación de una sola página que consume esta misma API: barra lateral
 * con módulos, un tablero con indicadores y las cuatro entidades con sus
 * operaciones completas.
 *
 * No tiene datos propios ni estado guardado: cada pantalla que se abre y cada
 * botón que se pulsa es una llamada HTTP contra la API. El indicador de la
 * esquina superior muestra la última, y el tablero guarda el historial.
 *
 * Está escrita en JavaScript sin librerías a propósito: así queda claro que el
 * trabajo lo hace la API, no un framework.
 */
function paginaPanel() {
  const cuerpo = `
<div class="disposicion">

  <aside class="lateral">
    <div class="lateral-cabeza">
      <div class="marca">${SELLO}<span><b>Essence Don Aire</b><small>Panel de gestión</small></span></div>
    </div>
    <nav id="menu">
      <div class="grupo">General</div>
      <a href="#/tablero" data-vista="tablero">${icono("tablero")} Tablero</a>
      <div class="grupo">Catálogo</div>
      <a href="#/productos" data-vista="productos">${icono("productos")} Productos <span class="cuenta" data-cuenta="productos">·</span></a>
      <a href="#/categorias" data-vista="categorias">${icono("categorias")} Categorías <span class="cuenta" data-cuenta="categorias">·</span></a>
      <div class="grupo">Contactos</div>
      <a href="#/proveedores" data-vista="proveedores">${icono("proveedores")} Proveedores <span class="cuenta" data-cuenta="proveedores">·</span></a>
      <a href="#/clientes" data-vista="clientes">${icono("clientes")} Clientes <span class="cuenta" data-cuenta="clientes">·</span></a>
      <div class="grupo">API</div>
      <a href="/docs">${icono("libro")} Documentación</a>
      <a href="/">${icono("refrescar")} Volver al inicio</a>
    </nav>
    <div class="lateral-pie">
      <span class="pastilla p-ok" id="estadoServicio">comprobando…</span>
    </div>
  </aside>

  <div class="trabajo">
    <header class="encabezado-trabajo">
      <div>
        <div class="miga" id="miga">Panel</div>
        <h1 id="tituloVista">Tablero</h1>
      </div>
      <div class="acciones-trabajo" id="accionesVista"></div>
    </header>
    <div class="lienzo">
      <div id="avisoGlobal"></div>
      <div id="vista"><div class="cargando">Cargando…</div></div>
    </div>
  </div>
</div>

<div id="modal"></div>`;

  // El script se arma aparte para poder incrustar los iconos que usa.
  const script = guionPanel();

  return plantilla({
    titulo: "Panel — Essence Don Aire",
    cuerpo,
    script,
    conBarra: false,
    conPie: false
  });
}

/** Todo el comportamiento del panel. */
function guionPanel() {
  const iconos = {
    editar: icono("editar", 16),
    borrar: icono("borrar", 16),
    mas: icono("mas", 17),
    alerta: icono("alerta", 20),
    productos: icono("productos", 20),
    categorias: icono("categorias", 20),
    proveedores: icono("proveedores", 20),
    clientes: icono("clientes", 20),
    dinero: icono("dinero", 20)
  };

  return `
var ICO = ${JSON.stringify(iconos)};
var $ = function (id) { return document.getElementById(id); };

var pesos = new Intl.NumberFormat("es-CO", { style: "currency", currency: "COP", maximumFractionDigits: 0 });
var miles = new Intl.NumberFormat("es-CO");

function limpiar(t) {
  return String(t === null || t === undefined ? "" : t)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
function iniciales(nombre) {
  return String(nombre || "?").trim().split(/\\s+/).slice(0, 2)
    .map(function (p) { return p[0]; }).join("").toUpperCase();
}
function fecha(v) {
  if (!v) return "—";
  var d = new Date(v);
  return isNaN(d) ? "—" : d.toLocaleDateString("es-CO", { day: "2-digit", month: "short", year: "numeric" });
}

/* ==================================================================
   Capa de acceso a la API
   Todas las llamadas pasan por aquí, para que queden registradas.
================================================================== */
var bitacora = [];

function registrar(metodo, ruta, codigo, ok) {
  bitacora.unshift({ metodo: metodo, ruta: ruta, codigo: codigo, ok: ok, hora: new Date() });
  if (bitacora.length > 40) bitacora.pop();
  var ultima = $("ultimaPeticion");
  if (ultima) ultima.outerHTML = pintarUltima();
  var lista = $("listaBitacora");
  if (lista) lista.innerHTML = pintarBitacora();
}

function pintarUltima() {
  if (!bitacora.length) return '<span id="ultimaPeticion"></span>';
  var u = bitacora[0];
  return '<span id="ultimaPeticion" class="fila" style="gap:8px;font-size:.8rem">' +
    '<span class="metodo m-' + u.metodo.toLowerCase() + '">' + u.metodo + '</span>' +
    '<span class="mono recortado" style="max-width:34ch;color:var(--texto-tenue)">' + limpiar(u.ruta) + '</span>' +
    '<span class="pastilla ' + (u.ok ? "p-ok" : "p-alerta") + '">' + u.codigo + '</span></span>';
}

function pintarBitacora() {
  if (!bitacora.length) {
    return '<li style="color:var(--texto-tenue)">Todavía no se ha hecho ninguna petición.</li>';
  }
  return bitacora.slice(0, 12).map(function (p) {
    return '<li>' +
      '<span class="metodo m-' + p.metodo.toLowerCase() + '">' + p.metodo + '</span>' +
      '<span class="mono" style="color:var(--texto-tenue);word-break:break-all;margin-right:auto">' +
        limpiar(p.ruta) + '</span>' +
      '<span class="pastilla ' + (p.ok ? "p-ok" : "p-alerta") + '">' + p.codigo + '</span>' +
    '</li>';
  }).join("");
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
    registrar(metodo, ruta, "sin red", false);
    throw new Error("No se pudo conectar con la API.");
  }
  try { datos = await respuesta.json(); } catch (e) { datos = null; }
  registrar(metodo, ruta, respuesta.status, respuesta.ok);

  if (!respuesta.ok) {
    var error = new Error((datos && datos.error) || "Error " + respuesta.status);
    error.detalles = datos && datos.detalles;
    error.codigo = respuesta.status;
    throw error;
  }
  return datos;
}

/* ==================================================================
   Definición de los módulos
   Las cuatro entidades comparten la misma pantalla; lo único que cambia
   son sus columnas, sus campos y sus filtros. Describirlas así evita
   escribir cuatro veces la misma tabla y el mismo formulario.
================================================================== */
var listas = { categorias: [], proveedores: [] };

var MODULOS = {
  productos: {
    titulo: "Productos", singular: "producto", genero: "el",
    ruta: "/api/productos", id: "id_producto",
    buscar: "Buscar por nombre, SKU o descripción",
    ordenes: [
      ["nombre|asc", "Nombre (A-Z)"], ["nombre|desc", "Nombre (Z-A)"],
      ["precio|desc", "Precio (mayor primero)"], ["precio|asc", "Precio (menor primero)"],
      ["stock|asc", "Stock (menor primero)"], ["fecha_creacion|desc", "Más recientes"]
    ],
    filtros: [
      { id: "categoria", parametro: "categoria", vacio: "Todas las categorías",
        opciones: function () {
          return listas.categorias.map(function (c) { return [c.id_categoria, c.nombre]; });
        } },
      { id: "proveedor", parametro: "proveedor", vacio: "Todos los proveedores",
        opciones: function () {
          return listas.proveedores.map(function (p) { return [p.id_proveedor, p.nombre]; });
        } }
    ],
    casillas: [{ id: "stockBajo", parametro: "stockBajo", etiqueta: "Solo stock bajo" }],
    columnas: [
      { titulo: "SKU", clase: "firme", celda: function (p) {
        return '<span class="mono" style="font-size:.8rem;color:var(--texto-tenue)">' + limpiar(p.sku) + '</span>';
      } },
      { titulo: "Producto", celda: function (p) {
        return '<strong>' + limpiar(p.nombre) + '</strong>' +
          (p.descripcion ? '<span class="recortado" style="font-size:.81rem;color:var(--texto-tenue)" title="' +
            limpiar(p.descripcion) + '">' + limpiar(p.descripcion) + '</span>' : "");
      } },
      { titulo: "Categoría", clase: "firme", celda: function (p) {
        return '<span class="pastilla p-oro">' + limpiar(p.categoria) + '</span>';
      } },
      { titulo: "Proveedor", celda: function (p) {
        return '<span style="font-size:.85rem">' + limpiar(p.proveedor) + '</span>';
      } },
      { titulo: "Precio", clase: "num", celda: function (p) { return pesos.format(Number(p.precio)); } },
      { titulo: "Stock", clase: "num", celda: function (p) {
        return p.stock + ' / ' + p.stock_minimo +
          (p.stock_bajo ? ' <span class="pastilla p-alerta">bajo</span>' : "");
      } },
      { titulo: "Estado", clase: "firme", celda: function (p) { return pastillaEstado(p.estado); } }
    ],
    campos: [
      { n: "sku", e: "SKU", req: true, pista: "Identificador visible. No se puede repetir." },
      { n: "nombre", e: "Nombre", req: true },
      { n: "descripcion", e: "Descripción", tipo: "textarea" },
      { n: "id_categoria", e: "Categoría", req: true, tipo: "select", mitad: true,
        opciones: function () {
          return listas.categorias.map(function (c) { return [c.id_categoria, c.nombre]; });
        } },
      { n: "id_proveedor", e: "Proveedor", req: true, tipo: "select", mitad: true,
        opciones: function () {
          return listas.proveedores.map(function (p) { return [p.id_proveedor, p.nombre]; });
        } },
      { n: "precio", e: "Precio", req: true, tipo: "number", tercio: true, defecto: 0 },
      { n: "stock", e: "Stock", tipo: "number", tercio: true, defecto: 0 },
      { n: "stock_minimo", e: "Stock mínimo", tipo: "number", tercio: true, defecto: 0 },
      { n: "estado", e: "Estado", tipo: "estado" }
    ]
  },

  categorias: {
    titulo: "Categorías", singular: "categoría", genero: "la",
    ruta: "/api/categorias", id: "id_categoria",
    buscar: "Buscar por nombre o descripción",
    ordenes: [["nombre|asc", "Nombre (A-Z)"], ["nombre|desc", "Nombre (Z-A)"], ["created_at|desc", "Más recientes"]],
    filtros: [], casillas: [],
    columnas: [
      { titulo: "Categoría", celda: function (c) {
        return '<div class="fila" style="gap:11px;flex-wrap:nowrap">' +
          '<span class="avatar">' + limpiar(iniciales(c.nombre)) + '</span>' +
          '<span><strong>' + limpiar(c.nombre) + '</strong>' +
          (c.descripcion ? '<span class="recortado" style="font-size:.81rem;color:var(--texto-tenue)">' +
            limpiar(c.descripcion) + '</span>' : "") + '</span></div>';
      } },
      { titulo: "Productos", clase: "num", celda: function (c) {
        return c.total_productos > 0
          ? '<span class="pastilla p-info">' + c.total_productos + '</span>'
          : '<span style="color:var(--texto-tenue)">0</span>';
      } },
      { titulo: "Creada", clase: "firme", celda: function (c) {
        return '<span style="color:var(--texto-tenue);font-size:.85rem">' + fecha(c.created_at) + '</span>';
      } },
      { titulo: "Estado", clase: "firme", celda: function (c) { return pastillaEstado(c.estado); } }
    ],
    campos: [
      { n: "nombre", e: "Nombre", req: true, pista: "No se puede repetir." },
      { n: "descripcion", e: "Descripción", tipo: "textarea" },
      { n: "estado", e: "Estado", tipo: "estado" }
    ]
  },

  proveedores: {
    titulo: "Proveedores", singular: "proveedor", genero: "el",
    ruta: "/api/proveedores", id: "id_proveedor",
    buscar: "Buscar por nombre, contacto o correo",
    ordenes: [
      ["nombre|asc", "Nombre (A-Z)"], ["calificacion|desc", "Mejor calificados"],
      ["ciudad|asc", "Ciudad"], ["fecha_alta|desc", "Más recientes"]
    ],
    filtros: [], casillas: [],
    columnas: [
      { titulo: "Proveedor", celda: function (p) {
        return '<div class="fila" style="gap:11px;flex-wrap:nowrap">' +
          '<span class="avatar">' + limpiar(iniciales(p.nombre)) + '</span>' +
          '<span><strong>' + limpiar(p.nombre) + '</strong>' +
          (p.contacto ? '<span style="display:block;font-size:.81rem;color:var(--texto-tenue)">' +
            limpiar(p.contacto) + '</span>' : "") + '</span></div>';
      } },
      { titulo: "Contacto", celda: function (p) {
        return '<span style="font-size:.85rem">' + limpiar(p.email || "—") + '</span>' +
          '<span style="display:block;font-size:.81rem;color:var(--texto-tenue)">' + limpiar(p.telefono || "") + '</span>';
      } },
      { titulo: "Ciudad", clase: "firme", celda: function (p) { return limpiar(p.ciudad || "—"); } },
      { titulo: "Calificación", clase: "num", celda: function (p) {
        var v = Number(p.calificacion);
        var clase = v >= 4.5 ? "p-ok" : v >= 3.5 ? "p-aviso" : "p-no";
        return '<span class="pastilla ' + clase + '">' + v.toFixed(1) + ' / 5</span>';
      } },
      { titulo: "Productos", clase: "num", celda: function (p) { return p.total_productos; } },
      { titulo: "Estado", clase: "firme", celda: function (p) { return pastillaEstado(p.estado); } }
    ],
    campos: [
      { n: "nombre", e: "Nombre o razón social", req: true },
      { n: "contacto", e: "Persona de contacto", mitad: true },
      { n: "ciudad", e: "Ciudad", mitad: true },
      { n: "email", e: "Correo", tipo: "email", mitad: true },
      { n: "telefono", e: "Teléfono", mitad: true },
      { n: "calificacion", e: "Calificación", tipo: "number", paso: "0.1", max: 5, defecto: 0,
        pista: "Entre 0 y 5." },
      { n: "estado", e: "Estado", tipo: "estado" }
    ]
  },

  clientes: {
    titulo: "Clientes", singular: "cliente", genero: "el",
    ruta: "/api/clientes", id: "id_cliente",
    buscar: "Buscar por nombre, correo o teléfono",
    ordenes: [
      ["nombre|asc", "Nombre (A-Z)"], ["ciudad|asc", "Ciudad"], ["fecha_registro|desc", "Más recientes"]
    ],
    filtros: [], casillas: [],
    columnas: [
      { titulo: "Cliente", celda: function (c) {
        return '<div class="fila" style="gap:11px;flex-wrap:nowrap">' +
          '<span class="avatar">' + limpiar(iniciales(c.nombre)) + '</span>' +
          '<span><strong>' + limpiar(c.nombre) + '</strong>' +
          '<span style="display:block;font-size:.81rem;color:var(--texto-tenue)">' +
            limpiar(c.correo) + '</span></span></div>';
      } },
      { titulo: "Teléfono", clase: "firme", celda: function (c) { return limpiar(c.telefono || "—"); } },
      { titulo: "Dirección", celda: function (c) {
        return '<span class="recortado" style="font-size:.85rem">' + limpiar(c.direccion || "—") + '</span>';
      } },
      { titulo: "Ciudad", clase: "firme", celda: function (c) { return limpiar(c.ciudad || "—"); } },
      { titulo: "Registro", clase: "firme", celda: function (c) {
        return '<span style="color:var(--texto-tenue);font-size:.85rem">' + fecha(c.fecha_registro) + '</span>';
      } },
      { titulo: "Estado", clase: "firme", celda: function (c) { return pastillaEstado(c.estado); } }
    ],
    campos: [
      { n: "nombre", e: "Nombre completo", req: true },
      { n: "correo", e: "Correo", tipo: "email", req: true, pista: "No se puede repetir." },
      { n: "telefono", e: "Teléfono", mitad: true },
      { n: "ciudad", e: "Ciudad", mitad: true },
      { n: "direccion", e: "Dirección" },
      { n: "estado", e: "Estado", tipo: "estado" }
    ]
  }
};

function pastillaEstado(activo) {
  return '<span class="pastilla ' + (activo ? "p-ok" : "p-no") + '">' +
    (activo ? "Activo" : "Inactivo") + '</span>';
}

/* ==================================================================
   Estado de la pantalla actual
================================================================== */
var vista = { clave: "tablero", pagina: 1, porPagina: 8, totalPaginas: 1, editando: null };

function avisarGlobal(mensaje, tipo) {
  $("avisoGlobal").innerHTML = mensaje
    ? '<div class="aviso aviso-' + (tipo || "error") + '">' + limpiar(mensaje) + '</div>' : "";
}

/* ==================================================================
   Tablero
================================================================== */
async function verTablero() {
  $("tituloVista").textContent = "Tablero";
  $("miga").textContent = "Panel";
  $("accionesVista").innerHTML = pintarUltima();

  $("vista").innerHTML = '<div class="cargando">Cargando indicadores…</div>';

  try {
    var res = await Promise.all([
      api("GET", "/api/productos?limit=100"),
      api("GET", "/api/categorias?limit=100"),
      api("GET", "/api/proveedores?limit=100"),
      api("GET", "/api/clientes?limit=1")
    ]);
    var productos = res[0], categorias = res[1], proveedores = res[2], clientes = res[3];

    listas.categorias = categorias.datos;
    listas.proveedores = proveedores.datos;
    actualizarCuentas({
      productos: productos.paginacion.total, categorias: categorias.paginacion.total,
      proveedores: proveedores.paginacion.total, clientes: clientes.paginacion.total
    });

    var bajos = productos.datos.filter(function (p) { return p.stock_bajo; });
    var inventario = productos.datos.reduce(function (s, p) { return s + Number(p.precio) * p.stock; }, 0);

    var porCategoria = categorias.datos
      .map(function (c) { return { nombre: c.nombre, total: c.total_productos }; })
      .sort(function (a, b) { return b.total - a.total; });
    var tope = Math.max.apply(null, porCategoria.map(function (c) { return c.total; }).concat([1]));

    $("vista").innerHTML =
      '<div class="rejilla rejilla-4" style="margin-bottom:22px">' +
        indicador(ICO.productos, "f-oro", productos.paginacion.total, "Productos") +
        indicador(ICO.alerta, bajos.length ? "f-peligro" : "f-exito", bajos.length, "En stock bajo") +
        indicador(ICO.clientes, "f-info", clientes.paginacion.total, "Clientes") +
        indicador(ICO.dinero, "f-exito", pesos.format(inventario), "Valor del inventario") +
      '</div>' +

      '<div class="rejilla rejilla-2" style="margin-bottom:22px">' +
        '<div class="tarjeta">' +
          '<h3>Productos por categoría</h3>' +
          '<p style="margin-bottom:16px">Calculado por la API con una subconsulta, no guardado en la tabla.</p>' +
          '<div class="barras">' +
            porCategoria.map(function (c) {
              return '<div class="linea">' +
                '<span style="font-size:.86rem">' + limpiar(c.nombre) + '</span>' +
                '<span class="riel"><span class="relleno" style="width:' +
                  Math.round((c.total / tope) * 100) + '%"></span></span>' +
                '<span class="valor">' + c.total + '</span></div>';
            }).join("") +
          '</div>' +
        '</div>' +

        '<div class="tarjeta" style="padding:0">' +
          '<div style="padding:20px 20px 12px">' +
            '<h3>Stock bajo</h3>' +
            '<p>Productos con existencias iguales o por debajo de su mínimo.</p>' +
          '</div>' +
          (bajos.length
            ? '<ul class="lista-limpia">' + bajos.map(function (p) {
                return '<li><span class="avatar">' + limpiar(iniciales(p.nombre)) + '</span>' +
                  '<span style="margin-right:auto"><strong>' + limpiar(p.nombre) + '</strong>' +
                  '<span style="display:block;font-size:.8rem;color:var(--texto-tenue)">' +
                    limpiar(p.categoria) + '</span></span>' +
                  '<span class="pastilla p-alerta">' + p.stock + ' / ' + p.stock_minimo + '</span></li>';
              }).join("") + '</ul>'
            : '<div class="vacio">Ningún producto está por debajo del mínimo.</div>') +
        '</div>' +
      '</div>' +

      '<div class="tarjeta" style="padding:0">' +
        '<div style="padding:20px 20px 12px">' +
          '<h3>Actividad de la API</h3>' +
          '<p>Cada pantalla y cada botón de este panel es una llamada HTTP. Aquí están las últimas.</p>' +
        '</div>' +
        '<ul class="lista-limpia" id="listaBitacora">' + pintarBitacora() + '</ul>' +
      '</div>';
  } catch (e) {
    avisarGlobal(e.message);
    $("vista").innerHTML = '<div class="vacio">No se pudo cargar el tablero.</div>';
  }
}

function indicador(ico, clase, valor, etiqueta) {
  var esNumero = typeof valor === "number";
  var texto = esNumero ? miles.format(valor) : valor;
  return '<div class="tarjeta"><div class="indicador">' +
    '<span class="figura ' + clase + '">' + ico + '</span>' +
    '<span><span class="numero' + (texto.length > 9 ? " largo" : "") + '">' + texto + '</span>' +
    '<span class="etiqueta">' + etiqueta + '</span></span></div></div>';
}

function actualizarCuentas(totales) {
  Object.keys(totales).forEach(function (k) {
    var n = document.querySelector('[data-cuenta="' + k + '"]');
    if (n) n.textContent = totales[k];
  });
}

/* ==================================================================
   Pantalla de una entidad
================================================================== */
function verModulo(clave) {
  var m = MODULOS[clave];
  vista.clave = clave;
  vista.pagina = 1;

  $("tituloVista").textContent = m.titulo;
  $("miga").textContent = "Panel · " + m.titulo;
  $("accionesVista").innerHTML =
    pintarUltima() +
    '<button class="boton boton-principal" id="nuevo">' + ICO.mas + ' Nuev' +
      (m.genero === "la" ? "a " : "o ") + m.singular + '</button>';
  $("nuevo").onclick = function () { abrirFormulario(null); };

  var filtros =
    '<input id="buscar" type="search" placeholder="' + m.buscar + '">' +
    m.filtros.map(function (f) {
      return '<select id="' + f.id + '"><option value="">' + f.vacio + '</option>' +
        f.opciones().map(function (o) {
          return '<option value="' + o[0] + '">' + limpiar(o[1]) + '</option>';
        }).join("") + '</select>';
    }).join("") +
    '<select id="estado">' +
      '<option value="all">Todos los estados</option>' +
      '<option value="active">Solo activos</option>' +
      '<option value="inactive">Solo inactivos</option>' +
    '</select>' +
    '<select id="orden">' + m.ordenes.map(function (o) {
      return '<option value="' + o[0] + '">' + o[1] + '</option>';
    }).join("") + '</select>';

  var casillas = m.casillas.map(function (c) {
    return '<label class="fila" style="gap:7px;font-size:.89rem;cursor:pointer">' +
      '<input type="checkbox" id="' + c.id + '" style="margin:0"> ' + c.etiqueta + '</label>';
  }).join("");

  $("vista").innerHTML =
    '<div class="filtros">' + filtros + '</div>' +
    (casillas
      ? '<div class="fila" style="margin-bottom:16px">' + casillas +
        '<span id="resumen" style="margin-left:auto;color:var(--texto-tenue);font-size:.87rem"></span></div>'
      : '<div class="fila" style="margin-bottom:16px"><span id="resumen" style="margin-left:auto;color:var(--texto-tenue);font-size:.87rem"></span></div>') +
    '<div class="marco-tabla">' +
      '<div class="desplazable"><table><thead><tr>' +
        m.columnas.map(function (c) {
          return '<th class="' + (c.clase || "") + '">' + c.titulo + '</th>';
        }).join("") + '<th class="firme"></th>' +
      '</tr></thead><tbody id="filas">' +
        '<tr><td colspan="' + (m.columnas.length + 1) + '" class="cargando">Cargando…</td></tr>' +
      '</tbody></table></div>' +
      '<div class="paginacion">' +
        '<span id="textoPagina">—</span>' +
        '<span class="fila" style="gap:8px">' +
          '<button id="anterior" class="boton boton-borde boton-chico">Anterior</button>' +
          '<button id="siguiente" class="boton boton-borde boton-chico">Siguiente</button>' +
        '</span>' +
      '</div>' +
    '</div>';

  var espera = null;
  $("buscar").addEventListener("input", function () {
    clearTimeout(espera);
    espera = setTimeout(function () { vista.pagina = 1; cargarLista(); }, 320);
  });
  ["estado", "orden"].concat(m.filtros.map(function (f) { return f.id; }))
    .concat(m.casillas.map(function (c) { return c.id; }))
    .forEach(function (id) {
      var el = $(id);
      if (el) el.addEventListener("change", function () { vista.pagina = 1; cargarLista(); });
    });
  $("anterior").onclick = function () { if (vista.pagina > 1) { vista.pagina--; cargarLista(); } };
  $("siguiente").onclick = function () {
    if (vista.pagina < vista.totalPaginas) { vista.pagina++; cargarLista(); }
  };
  $("filas").addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-accion]");
    if (!b) return;
    if (b.dataset.accion === "editar") {
      api("GET", m.ruta + "/" + b.dataset.id)
        .then(function (r) { abrirFormulario(r.datos); })
        .catch(function (e) { avisarGlobal(e.message); });
    } else {
      confirmarBorrado(b.dataset.id, b.dataset.nombre);
    }
  });

  cargarLista();
}

function consultaActual() {
  var m = MODULOS[vista.clave];
  var partes = ["page=" + vista.pagina, "limit=" + vista.porPagina];
  var texto = $("buscar").value.trim();
  if (texto) partes.push("search=" + encodeURIComponent(texto));
  if ($("estado").value !== "all") partes.push("status=" + $("estado").value);
  m.filtros.forEach(function (f) {
    if ($(f.id) && $(f.id).value) partes.push(f.parametro + "=" + $(f.id).value);
  });
  m.casillas.forEach(function (c) {
    if ($(c.id) && $(c.id).checked) partes.push(c.parametro + "=1");
  });
  var orden = $("orden").value.split("|");
  partes.push("sortBy=" + orden[0], "sortDir=" + orden[1]);
  return m.ruta + "?" + partes.join("&");
}

async function cargarLista() {
  var m = MODULOS[vista.clave];
  avisarGlobal("");
  try {
    var r = await api("GET", consultaActual());
    $("accionesVista").querySelector("#ultimaPeticion") || null;

    if (!r.datos.length) {
      $("filas").innerHTML = '<tr><td colspan="' + (m.columnas.length + 1) +
        '" class="vacio">Ningún registro coincide con los filtros.</td></tr>';
    } else {
      $("filas").innerHTML = r.datos.map(function (fila) {
        var id = fila[m.id];
        var nombre = fila.nombre || "";
        return '<tr>' + m.columnas.map(function (c) {
          return '<td class="' + (c.clase || "") + '">' + c.celda(fila) + '</td>';
        }).join("") +
        '<td class="firme num">' +
          '<button class="icono-boton" title="Editar" data-accion="editar" data-id="' + id + '">' +
            ICO.editar + '</button>' +
          '<button class="icono-boton peligro" title="Eliminar" data-accion="borrar" data-id="' + id +
            '" data-nombre="' + limpiar(nombre) + '">' + ICO.borrar + '</button>' +
        '</td></tr>';
      }).join("");
    }

    vista.totalPaginas = r.paginacion.totalPaginas;
    $("textoPagina").textContent = "Página " + r.paginacion.pagina + " de " +
      r.paginacion.totalPaginas + " · " + r.paginacion.total + " registro(s)";
    $("resumen").textContent = r.paginacion.total + " resultado(s)";
    $("anterior").disabled = r.paginacion.pagina <= 1;
    $("siguiente").disabled = r.paginacion.pagina >= r.paginacion.totalPaginas;

    var cuenta = document.querySelector('[data-cuenta="' + vista.clave + '"]');
    if (cuenta) cuenta.textContent = r.paginacion.total;
  } catch (e) {
    avisarGlobal(e.message);
    $("filas").innerHTML = '<tr><td colspan="' + (m.columnas.length + 1) +
      '" class="vacio">No se pudieron cargar los datos.</td></tr>';
  }
}

/* ==================================================================
   Formulario
================================================================== */
function abrirFormulario(registro) {
  var m = MODULOS[vista.clave];
  vista.editando = registro || null;
  var r = registro || {};
  var edita = Boolean(registro);

  var campos = m.campos.map(function (c) {
    var valor = r[c.n];
    if (valor === undefined || valor === null) valor = c.defecto !== undefined ? c.defecto : "";
    var contenido;

    if (c.tipo === "estado") {
      contenido = '<select id="f_' + c.n + '">' +
        '<option value="true"' + (r.estado === false ? "" : " selected") + '>Activo</option>' +
        '<option value="false"' + (r.estado === false ? " selected" : "") + '>Inactivo</option></select>';
    } else if (c.tipo === "select") {
      contenido = '<select id="f_' + c.n + '">' + c.opciones().map(function (o) {
        return '<option value="' + o[0] + '"' +
          (String(o[0]) === String(valor) ? " selected" : "") + '>' + limpiar(o[1]) + '</option>';
      }).join("") + '</select>';
    } else if (c.tipo === "textarea") {
      contenido = '<textarea id="f_' + c.n + '">' + limpiar(valor) + '</textarea>';
    } else {
      contenido = '<input id="f_' + c.n + '" type="' + (c.tipo || "text") + '"' +
        (c.tipo === "number" ? ' min="0"' : "") +
        (c.paso ? ' step="' + c.paso + '"' : "") +
        (c.max ? ' max="' + c.max + '"' : "") +
        ' value="' + limpiar(valor) + '">';
    }

    return '<div class="campo"' + (c.mitad ? ' data-mitad="1"' : c.tercio ? ' data-tercio="1"' : "") + '>' +
      '<label for="f_' + c.n + '">' + c.e + (c.req ? ' *' : "") + '</label>' + contenido +
      (c.pista ? '<span class="pista">' + c.pista + '</span>' : "") +
      '<span class="error-campo" id="e_' + c.n + '"></span></div>';
  });

  // Los campos marcados como mitad o tercio se agrupan en su propia fila.
  var cuerpoForm = "", buffer = [], modo = null;
  m.campos.forEach(function (c, i) {
    var tipoFila = c.mitad ? "pareja" : c.tercio ? "trio" : null;
    if (tipoFila !== modo || (modo === "pareja" && buffer.length === 2) || (modo === "trio" && buffer.length === 3)) {
      if (buffer.length) cuerpoForm += modo ? '<div class="' + modo + '">' + buffer.join("") + '</div>' : buffer.join("");
      buffer = []; modo = tipoFila;
    }
    buffer.push(campos[i]);
  });
  if (buffer.length) cuerpoForm += modo ? '<div class="' + modo + '">' + buffer.join("") + '</div>' : buffer.join("");

  $("modal").innerHTML =
    '<div class="fondo-modal" id="fondoModal"><div class="modal">' +
      '<div class="modal-cabeza"><h3>' +
        (edita ? "Editar " : "Nuev" + (m.genero === "la" ? "a " : "o ")) + m.singular +
      '</h3><button class="cerrar" id="cerrarModal">&times;</button></div>' +
      '<div class="modal-cuerpo"><div id="avisoForm"></div>' + cuerpoForm + '</div>' +
      '<div class="modal-pie">' +
        '<button class="boton boton-suave" id="cancelar">Cancelar</button>' +
        '<button class="boton boton-principal" id="guardar">' +
          (edita ? "Guardar cambios" : "Crear") + '</button>' +
      '</div>' +
    '</div></div>';

  $("cerrarModal").onclick = cerrarModal;
  $("cancelar").onclick = cerrarModal;
  $("fondoModal").onclick = function (ev) { if (ev.target.id === "fondoModal") cerrarModal(); };
  $("guardar").onclick = guardar;
  var primero = $("f_" + m.campos[0].n);
  if (primero) primero.focus();
}

function cerrarModal() { $("modal").innerHTML = ""; vista.editando = null; }

function marcarErrores(detalles) {
  MODULOS[vista.clave].campos.forEach(function (c) {
    var span = $("e_" + c.n), entrada = $("f_" + c.n);
    if (!span) return;
    var mensaje = detalles && detalles[c.n];
    span.textContent = mensaje || "";
    if (entrada) entrada.classList.toggle("malo", Boolean(mensaje));
  });
}

async function guardar() {
  var m = MODULOS[vista.clave];
  marcarErrores(null);
  $("avisoForm").innerHTML = "";

  var cuerpo = {};
  m.campos.forEach(function (c) {
    var el = $("f_" + c.n);
    if (!el) return;
    if (c.tipo === "estado") cuerpo[c.n] = el.value === "true";
    else if (c.tipo === "number" || c.tipo === "select") cuerpo[c.n] = Number(el.value);
    else cuerpo[c.n] = el.value.trim();
  });

  var boton = $("guardar");
  boton.disabled = true;
  boton.textContent = "Guardando…";

  try {
    if (vista.editando) await api("PUT", m.ruta + "/" + vista.editando[m.id], cuerpo);
    else await api("POST", m.ruta, cuerpo);
    cerrarModal();
    await cargarLista();
  } catch (e) {
    $("avisoForm").innerHTML = '<div class="aviso aviso-error">' + limpiar(e.message) + '</div>';
    marcarErrores(e.detalles);
    boton.disabled = false;
    boton.textContent = vista.editando ? "Guardar cambios" : "Crear";
  }
}

/* ==================================================================
   Eliminar
================================================================== */
function confirmarBorrado(id, nombre) {
  var m = MODULOS[vista.clave];
  $("modal").innerHTML =
    '<div class="fondo-modal" id="fondoModal"><div class="modal chico">' +
      '<div class="modal-cabeza"><h3>¿Eliminar ' + m.genero + ' ' + m.singular + '?</h3>' +
        '<button class="cerrar" id="cerrarModal">&times;</button></div>' +
      '<div class="modal-cuerpo"><div id="avisoBorrar"></div>' +
        '<p style="margin:0">Se va a eliminar <strong>' + limpiar(nombre) +
        '</strong>. Esta acción no se puede deshacer.</p></div>' +
      '<div class="modal-pie">' +
        '<button class="boton boton-suave" id="cancelar">Cancelar</button>' +
        '<button class="boton boton-peligro" id="confirmar">Sí, eliminar</button>' +
      '</div></div></div>';

  $("cerrarModal").onclick = cerrarModal;
  $("cancelar").onclick = cerrarModal;
  $("fondoModal").onclick = function (ev) { if (ev.target.id === "fondoModal") cerrarModal(); };
  $("confirmar").onclick = async function () {
    this.disabled = true;
    this.textContent = "Eliminando…";
    try {
      await api("DELETE", m.ruta + "/" + id);
      cerrarModal();
      await cargarLista();
    } catch (e) {
      $("avisoBorrar").innerHTML = '<div class="aviso aviso-error">' + limpiar(e.message) + '</div>';
      this.disabled = false;
      this.textContent = "Sí, eliminar";
    }
  };
}

/* ==================================================================
   Navegación
================================================================== */
function navegar() {
  var clave = (location.hash || "#/tablero").replace("#/", "");
  if (clave !== "tablero" && !MODULOS[clave]) clave = "tablero";

  Array.prototype.forEach.call(document.querySelectorAll("#menu a"), function (a) {
    a.classList.toggle("activo", a.dataset.vista === clave);
  });

  avisarGlobal("");
  cerrarModal();
  if (clave === "tablero") verTablero();
  else verModulo(clave);
}

window.addEventListener("hashchange", navegar);
document.addEventListener("keydown", function (ev) { if (ev.key === "Escape") cerrarModal(); });

/* Las listas de apoyo se cargan una sola vez, antes de la primera pantalla. */
(async function iniciar() {
  try {
    var salud = await api("GET", "/api/health");
    $("estadoServicio").textContent = "Base de datos conectada";
  } catch (e) {
    $("estadoServicio").className = "pastilla p-alerta";
    $("estadoServicio").textContent = "Sin conexión a la base";
  }
  try {
    var c = await api("GET", "/api/categorias?limit=100&status=active");
    var p = await api("GET", "/api/proveedores?limit=100&status=active");
    listas.categorias = c.datos;
    listas.proveedores = p.datos;
  } catch (e) {
    avisarGlobal("No se pudieron cargar las listas de categorías y proveedores: " + e.message);
  }
  navegar();
})();
`;
}

export { paginaPanel };
