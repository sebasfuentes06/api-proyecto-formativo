/**
 * Estilos de las páginas web de la API.
 *
 * Van incrustados en el HTML, no como archivo aparte: en un despliegue
 * serverless Express no sirve archivos estáticos, así que un .css enlazado
 * devolvería 404 y las páginas se verían sin formato.
 *
 * La paleta es la misma del panel de Essence Don Aire — oro sobre crema — para
 * que la API y el sistema se vean como el mismo producto.
 */
const ESTILOS = `
  :root {
    --oro: #C9A227;
    --oro-suave: #F5EDD5;
    --oro-oscuro: #9A7A1C;
    --fondo: #F8F5F0;
    --tarjeta: #FFFFFF;
    --texto: #2B2B2B;
    --texto-tenue: #6B6B6B;
    --borde: rgba(43,43,43,.10);
    --borde-fuerte: rgba(43,43,43,.18);
    --exito: #16A34A;
    --exito-fondo: #EAF7EF;
    --peligro: #DC2626;
    --peligro-fondo: #FDECEC;
    --aviso: #B45309;
    --aviso-fondo: #FEF3E2;
    --info: #1D4ED8;
    --info-fondo: #EAF0FD;
    --radio: 12px;
    --sombra: 0 1px 2px rgba(43,43,43,.05), 0 6px 20px rgba(43,43,43,.05);
    --lateral: 248px;
  }

  * { box-sizing: border-box; }

  body {
    margin: 0;
    background: var(--fondo);
    color: var(--texto);
    font: 15px/1.6 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
  }

  a { color: var(--oro-oscuro); }
  h1, h2, h3 { letter-spacing: -.015em; }

  .contenedor { max-width: 1120px; margin: 0 auto; padding: 0 24px; }

  /* =========================================================
     Barra superior — solo para la portada y la documentación
     ========================================================= */
  .barra { background: #fff; border-bottom: 1px solid var(--borde); }
  .barra .contenedor {
    display: flex; align-items: center; gap: 20px;
    min-height: 66px; flex-wrap: wrap;
  }
  .marca { display: flex; align-items: center; gap: 11px; margin-right: auto; }
  .marca .sello {
    width: 34px; height: 34px; border-radius: 9px; background: var(--oro);
    display: grid; place-items: center; color: #fff; flex: none;
  }
  .marca b { font-weight: 650; font-size: .98rem; display: block; line-height: 1.2; }
  .marca small { color: var(--texto-tenue); font-size: .76rem; }
  .barra nav { display: flex; gap: 4px; flex-wrap: wrap; }
  .barra nav a {
    color: var(--texto-tenue); text-decoration: none; font-size: .9rem;
    padding: 8px 14px; border-radius: 8px; transition: all .15s;
  }
  .barra nav a:hover { background: var(--fondo); color: var(--texto); }
  .barra nav a.activo { background: var(--oro); color: #fff; font-weight: 600; }

  /* =========================================================
     Bloques de contenido
     ========================================================= */
  .heroe { padding: 60px 0 40px; }
  .heroe h1 { font-size: clamp(1.9rem, 4.5vw, 2.7rem); line-height: 1.15; margin: 0 0 14px; }
  .heroe p.entrada {
    font-size: 1.06rem; color: var(--texto-tenue); max-width: 62ch; margin: 0 0 26px;
  }

  .seccion { padding: 32px 0; }
  .seccion h2 { font-size: 1.2rem; margin: 0 0 6px; }
  .seccion p.sub { color: var(--texto-tenue); margin: 0 0 20px; font-size: .94rem; }

  /* =========================================================
     Botones
     ========================================================= */
  .boton {
    display: inline-flex; align-items: center; justify-content: center; gap: 8px;
    padding: 10px 17px; border-radius: 9px; border: 1px solid transparent;
    font: inherit; font-size: .91rem; font-weight: 550;
    text-decoration: none; cursor: pointer; transition: all .15s; white-space: nowrap;
  }
  .boton-principal { background: var(--oro); color: #fff; }
  .boton-principal:hover { background: var(--oro-oscuro); }
  .boton-borde { background: #fff; color: var(--texto); border-color: var(--borde-fuerte); }
  .boton-borde:hover { border-color: var(--oro); color: var(--oro-oscuro); }
  .boton-suave { background: var(--fondo); color: var(--texto); }
  .boton-suave:hover { background: var(--oro-suave); }
  .boton-peligro { background: var(--peligro); color: #fff; }
  .boton-peligro:hover { filter: brightness(.92); }
  .boton:disabled { opacity: .45; cursor: not-allowed; }
  .boton-chico { padding: 6px 10px; font-size: .83rem; border-radius: 7px; }
  .icono-boton {
    width: 32px; height: 32px; padding: 0; border-radius: 8px;
    background: transparent; border: 1px solid transparent; cursor: pointer;
    display: inline-grid; place-items: center; color: var(--texto-tenue);
    transition: all .15s;
  }
  .icono-boton:hover { background: var(--fondo); color: var(--texto); }
  .icono-boton.peligro:hover { background: var(--peligro-fondo); color: var(--peligro); }

  /* =========================================================
     Tarjetas
     ========================================================= */
  .rejilla { display: grid; gap: 16px; }
  .rejilla-4 { grid-template-columns: repeat(auto-fit, minmax(212px, 1fr)); }
  .rejilla-2 { grid-template-columns: repeat(auto-fit, minmax(430px, 1fr)); }

  .tarjeta {
    background: var(--tarjeta); border: 1px solid var(--borde);
    border-radius: var(--radio); padding: 20px; box-shadow: var(--sombra);
  }
  .tarjeta h3 { margin: 0 0 6px; font-size: 1rem; }
  .tarjeta p { margin: 0; color: var(--texto-tenue); font-size: .89rem; }

  .indicador { display: flex; align-items: flex-start; gap: 14px; }
  .indicador .figura {
    width: 44px; height: 44px; border-radius: 11px; flex: none;
    display: grid; place-items: center;
  }
  /* display:block porque son <span>: inline ignora el salto de línea. */
  .indicador .numero { display: block; font-size: 1.8rem; font-weight: 650; line-height: 1.15; }
  /* Las cifras de dinero son largas y se salían de la tarjeta. */
  .indicador .numero.largo { font-size: 1.3rem; }
  .indicador > span:last-child { min-width: 0; }
  .indicador .etiqueta { display: block; font-size: .8rem; color: var(--texto-tenue); }
  .f-oro { background: var(--oro-suave); color: var(--oro-oscuro); }
  .f-exito { background: var(--exito-fondo); color: var(--exito); }
  .f-peligro { background: var(--peligro-fondo); color: var(--peligro); }
  .f-info { background: var(--info-fondo); color: var(--info); }

  /* =========================================================
     Tablas
     ========================================================= */
  .marco-tabla {
    background: var(--tarjeta); border: 1px solid var(--borde);
    border-radius: var(--radio); overflow: hidden; box-shadow: var(--sombra);
  }
  .desplazable { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: .9rem; }
  th {
    text-align: left; padding: 13px 16px; background: #FCFAF7;
    font-size: .73rem; text-transform: uppercase; letter-spacing: .06em;
    color: var(--texto-tenue); font-weight: 600; white-space: nowrap;
    border-bottom: 1px solid var(--borde);
  }
  td { padding: 13px 16px; border-bottom: 1px solid var(--borde); vertical-align: middle; }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:hover { background: #FDFCFA; }
  .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  td.firme, th.firme { white-space: nowrap; }
  .recortado {
    display: block; max-width: 32ch; overflow: hidden;
    text-overflow: ellipsis; white-space: nowrap;
  }
  .avatar {
    width: 34px; height: 34px; border-radius: 50%; flex: none;
    display: grid; place-items: center; font-size: .82rem; font-weight: 650;
    background: var(--oro-suave); color: var(--oro-oscuro);
  }

  /* =========================================================
     Pastillas
     ========================================================= */
  .pastilla {
    display: inline-block; padding: 3px 10px; border-radius: 99px;
    font-size: .74rem; font-weight: 600; white-space: nowrap;
  }
  .p-ok { background: var(--exito-fondo); color: var(--exito); }
  .p-no { background: #EFECE7; color: var(--texto-tenue); }
  .p-alerta { background: var(--peligro-fondo); color: var(--peligro); }
  .p-oro { background: var(--oro-suave); color: var(--oro-oscuro); }
  .p-aviso { background: var(--aviso-fondo); color: var(--aviso); }
  .p-info { background: var(--info-fondo); color: var(--info); }

  /* =========================================================
     Formularios
     ========================================================= */
  .campo { display: flex; flex-direction: column; gap: 6px; }
  .campo label { font-size: .84rem; font-weight: 550; }
  .campo .pista { font-size: .78rem; color: var(--texto-tenue); }
  input, select, textarea {
    font: inherit; font-size: .92rem; padding: 10px 12px;
    border: 1px solid var(--borde-fuerte); border-radius: 9px;
    background: #fff; color: var(--texto); width: 100%;
  }
  textarea { resize: vertical; min-height: 74px; }
  input:focus, select:focus, textarea:focus {
    outline: none; border-color: var(--oro);
    box-shadow: 0 0 0 3px rgba(201,162,39,.18);
  }
  input[type="checkbox"] { width: auto; }
  .error-campo { color: var(--peligro); font-size: .79rem; }
  .malo { border-color: var(--peligro) !important; }

  /* =========================================================
     Avisos
     ========================================================= */
  .aviso {
    padding: 12px 15px; border-radius: 9px; font-size: .89rem;
    border: 1px solid transparent; margin-bottom: 16px;
  }
  .aviso-error { background: var(--peligro-fondo); color: var(--peligro); border-color: #F6CFCF; }
  .aviso-ok { background: var(--exito-fondo); color: var(--exito); border-color: #C6EAD5; }

  /* =========================================================
     Modal
     ========================================================= */
  .fondo-modal {
    position: fixed; inset: 0; background: rgba(43,43,43,.5);
    display: flex; align-items: center; justify-content: center;
    padding: 20px; z-index: 50; animation: aparecer .12s ease-out;
  }
  @keyframes aparecer { from { opacity: 0 } to { opacity: 1 } }
  .modal {
    background: #fff; border-radius: 14px; width: 100%;
    max-width: 580px; max-height: calc(100vh - 40px); overflow-y: auto;
    box-shadow: 0 24px 70px rgba(43,43,43,.28);
  }
  .modal.chico { max-width: 430px; }
  .modal-cabeza {
    padding: 18px 22px; border-bottom: 1px solid var(--borde);
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
  }
  .modal-cabeza h3 { margin: 0; font-size: 1.05rem; }
  .modal-cuerpo { padding: 22px; display: grid; gap: 16px; }
  .modal-pie {
    padding: 16px 22px; border-top: 1px solid var(--borde);
    display: flex; justify-content: flex-end; gap: 10px;
  }
  .cerrar {
    background: none; border: none; font-size: 1.5rem; line-height: 1;
    color: var(--texto-tenue); cursor: pointer; padding: 0 4px; width: auto;
  }
  .cerrar:hover { color: var(--texto); }
  .pareja { display: grid; gap: 16px; grid-template-columns: 1fr 1fr; }
  .trio { display: grid; gap: 16px; grid-template-columns: repeat(3, 1fr); }

  /* =========================================================
     Panel: barra lateral + área de trabajo
     ========================================================= */
  .disposicion { display: flex; min-height: 100vh; }

  .lateral {
    width: var(--lateral); flex: none; background: #fff;
    border-right: 1px solid var(--borde); display: flex; flex-direction: column;
    position: sticky; top: 0; height: 100vh;
  }
  .lateral-cabeza { padding: 20px 18px; border-bottom: 1px solid var(--borde); }
  .lateral nav { padding: 14px 12px; flex: 1; overflow-y: auto; }
  .lateral .grupo {
    font-size: .68rem; text-transform: uppercase; letter-spacing: .09em;
    color: var(--texto-tenue); padding: 14px 12px 7px; font-weight: 650;
  }
  .lateral a {
    display: flex; align-items: center; gap: 11px;
    padding: 10px 12px; border-radius: 9px; margin-bottom: 2px;
    color: var(--texto); text-decoration: none; font-size: .91rem;
    transition: all .13s;
  }
  .lateral a:hover { background: var(--fondo); }
  .lateral a.activo { background: var(--oro); color: #fff; font-weight: 600; }
  .lateral a.activo svg { stroke: #fff; }
  .lateral a .cuenta {
    margin-left: auto; font-size: .76rem; color: var(--texto-tenue);
    background: var(--fondo); padding: 1px 8px; border-radius: 99px;
  }
  .lateral a.activo .cuenta { background: rgba(255,255,255,.22); color: #fff; }
  .lateral-pie { padding: 14px 18px; border-top: 1px solid var(--borde); font-size: .78rem; }

  .trabajo { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .encabezado-trabajo {
    background: #fff; border-bottom: 1px solid var(--borde);
    padding: 18px 28px; display: flex; align-items: center; gap: 16px; flex-wrap: wrap;
  }
  .encabezado-trabajo h1 { margin: 0; font-size: 1.4rem; }
  .encabezado-trabajo .miga { font-size: .8rem; color: var(--texto-tenue); }
  .acciones-trabajo { margin-left: auto; display: flex; gap: 10px; flex-wrap: wrap; }
  .lienzo { padding: 26px 28px 60px; }

  .filtros {
    display: grid; gap: 12px; margin-bottom: 18px;
    grid-template-columns: minmax(200px,1.7fr) repeat(auto-fit, minmax(140px,1fr));
  }

  .paginacion {
    display: flex; align-items: center; justify-content: space-between;
    gap: 12px; padding: 14px 16px; border-top: 1px solid var(--borde);
    flex-wrap: wrap; font-size: .87rem; color: var(--texto-tenue);
  }

  .vacio, .cargando { padding: 46px 20px; text-align: center; color: var(--texto-tenue); }

  /* Barras del tablero: sin librerías, solo CSS. */
  .barras { display: grid; gap: 11px; }
  .barras .linea { display: grid; grid-template-columns: 116px 1fr 40px; gap: 12px; align-items: center; }
  /* display:block en los dos: un <span> inline no admite alto ni ancho. */
  .barras .riel {
    display: block; background: var(--fondo); border-radius: 99px;
    height: 10px; overflow: hidden;
  }
  .barras .relleno { display: block; background: var(--oro); height: 100%; border-radius: 99px; }
  .barras .valor { text-align: right; font-size: .84rem; color: var(--texto-tenue); font-variant-numeric: tabular-nums; }

  /* =========================================================
     Varios
     ========================================================= */
  .fila { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .lista-limpia { list-style: none; padding: 0; margin: 0; }
  .lista-limpia li {
    padding: 11px 16px; border-bottom: 1px solid var(--borde);
    display: flex; align-items: center; gap: 12px; font-size: .88rem;
  }
  .lista-limpia li:last-child { border-bottom: none; }

  code, .mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: .86em; }
  code { background: #F1EDE6; padding: 2px 6px; border-radius: 5px; color: var(--oro-oscuro); }

  .metodo {
    display: inline-block; min-width: 56px; text-align: center;
    padding: 3px 8px; border-radius: 6px; font-size: .7rem;
    font-weight: 700; letter-spacing: .04em; flex: none;
  }
  .m-get { background: var(--info-fondo); color: var(--info); }
  .m-post { background: var(--exito-fondo); color: var(--exito); }
  .m-put { background: var(--aviso-fondo); color: var(--aviso); }
  .m-delete { background: var(--peligro-fondo); color: var(--peligro); }

  .pie {
    border-top: 1px solid var(--borde); margin-top: 48px;
    padding: 26px 0 40px; color: var(--texto-tenue); font-size: .86rem;
  }

  svg { stroke-width: 1.8; }

  @media (max-width: 860px) {
    .lateral {
      position: static; width: 100%; height: auto; flex-direction: row;
      overflow-x: auto; border-right: none; border-bottom: 1px solid var(--borde);
    }
    .lateral-cabeza, .lateral-pie, .lateral .grupo { display: none; }
    .lateral nav { display: flex; gap: 4px; padding: 10px; }
    .lateral a { margin: 0; white-space: nowrap; }
    .lateral a .cuenta { display: none; }
    .disposicion { flex-direction: column; }
    .lienzo, .encabezado-trabajo { padding-left: 18px; padding-right: 18px; }
    .pareja, .trio { grid-template-columns: 1fr; }
  }
`;

/** Iconos de trazo, dibujados a mano para no depender de ninguna librería. */
const ICONOS = {
  tablero: '<path d="M3 3h7v7H3zM14 3h7v5h-7zM14 12h7v9h-7zM3 14h7v7H3z"/>',
  productos: '<path d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8"/>',
  categorias: '<path d="M3 5h8v6H3zM13 5h8v6h-8zM3 13h8v6H3zM13 13h8v6h-8z"/>',
  proveedores: '<path d="M3 9h13v8H3zM16 12h3l2 3v2h-5zM7 20a2 2 0 100-4 2 2 0 000 4zM18 20a2 2 0 100-4 2 2 0 000 4z"/>',
  clientes: '<path d="M17 21v-2a4 4 0 00-4-4H6a4 4 0 00-4 4v2M9.5 7a3.5 3.5 0 11-7 0 3.5 3.5 0 017 0zM22 21v-2a4 4 0 00-3-3.9M16 3.1a4 4 0 010 7.8"/>',
  libro: '<path d="M4 19.5A2.5 2.5 0 016.5 17H20M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/>',
  alerta: '<path d="M10.3 3.9L1.8 18a2 2 0 001.7 3h17a2 2 0 001.7-3L14.7 3.9a2 2 0 00-3.4 0zM12 9v4M12 17h.01"/>',
  editar: '<path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7M18.5 2.5a2.1 2.1 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/>',
  borrar: '<path d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/>',
  mas: '<path d="M12 5v14M5 12h14"/>',
  frasco: '<path d="M9 3h6v4l3 4v9a2 2 0 01-2 2H8a2 2 0 01-2-2v-9l3-4V3z"/>',
  dinero: '<path d="M12 1v22M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>',
  refrescar: '<path d="M21 2v6h-6M3 22v-6h6M3.5 9a9 9 0 0114.9-3.4L21 8M20.5 15a9 9 0 01-14.9 3.4L3 16"/>'
};

/** Devuelve el SVG de un icono. */
function icono(nombre, tamano) {
  const t = tamano || 18;
  return (
    '<svg width="' + t + '" height="' + t + '" viewBox="0 0 24 24" fill="none" ' +
    'stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">' +
    (ICONOS[nombre] || "") + "</svg>"
  );
}

const SELLO =
  '<span class="sello">' +
  '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
  'stroke-linecap="round" stroke-linejoin="round">' + ICONOS.frasco + "</svg></span>";

const FAVICON =
  "data:image/svg+xml," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
      '<rect width="32" height="32" rx="7" fill="#C9A227"/>' +
      '<path d="M13 7h6v3.4a7 7 0 1 1-6 0V7z" fill="#fff"/>' +
      '<rect x="13.5" y="4.5" width="5" height="3" rx="1" fill="#F5EDD5"/>' +
    "</svg>"
  );

/** Documento completo. `conBarra` agrega la navegación superior. */
function plantilla({ titulo, activo = "", cuerpo, script = "", conBarra = true, conPie = true }) {
  const enlace = (href, texto) =>
    `<a href="${href}"${activo === href ? ' class="activo"' : ""}>${texto}</a>`;

  const barra = conBarra
    ? `<header class="barra">
  <div class="contenedor">
    <div class="marca">${SELLO}<span><b>Essence Don Aire</b><small>API REST</small></span></div>
    <nav>
      ${enlace("/", "Inicio")}
      ${enlace("/panel", "Panel")}
      ${enlace("/docs", "Documentación")}
      ${enlace("/api/health", "Estado")}
    </nav>
  </div>
</header>`
    : "";

  const pie = conPie
    ? `<footer class="pie">
  <div class="contenedor">
    API REST del proyecto formativo · Node.js + Express + PostgreSQL ·
    Sebastián Fuentes Hernández, SENA — Análisis y Desarrollo de Software
  </div>
</footer>`
    : "";

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${titulo}</title>
<link rel="icon" href="${FAVICON}">
<style>${ESTILOS}</style>
</head>
<body>
${barra}
${cuerpo}
${pie}
${script ? `<script>${script}</script>` : ""}
</body>
</html>`;
}

export { ESTILOS, ICONOS, icono, plantilla, SELLO, FAVICON };
