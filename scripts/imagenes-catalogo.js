/**
 * Pone foto a los productos que no tienen, consumiendo la API pública de
 * Wikimedia Commons (fotos de licencia libre, no pide llave).
 *
 *     npm run db:imagenes            solo los productos SIN foto
 *     npm run db:imagenes -- --todos también reemplaza las que ya tienen
 *
 * Para cada producto busca una foto de un FRASCO de perfume (primero con su
 * nota: rosa, jazmín, sándalo...; si no, un frasco cualquiera), descarga la
 * miniatura de ~600 px y la guarda en la base
 * (tabla producto_imagen), igual que cuando se elige una desde la app.
 * Desde ese momento la ven la vitrina y el catálogo.
 *
 * Los productos de las pruebas automáticas ("Prueba APP-...") se saltan.
 */
import { pool, query } from "../src/db/pool.js";

const API = "https://commons.wikimedia.org/w/api.php";
// Wikimedia pide un User-Agent que identifique a quien consulta.
const CABECERAS = { "User-Agent": "EssenceDonAire/1.0 (proyecto formativo SENA)" };
const MAXIMO_BYTES = 1.4 * 1024 * 1024;

// Todas las fotos son de frascos de perfume/loción. Primero se intenta con
// la nota del producto (ej. "rose perfume bottle") y, si no alcanza, con
// búsquedas generales de frascos. Van en inglés porque Wikimedia tiene
// muchas más fotos descritas en inglés.
const NOTAS = [
  [/rosa/i, "rose"],
  [/jazm[ií]n/i, "jasmine"],
  [/s[aá]ndalo/i, "sandalwood"],
  [/vetiver/i, "vetiver"],
  [/bergamota/i, "bergamot"],
  [/lim[oó]n/i, "lemon"],
  [/vainilla/i, "vanilla"],
  [/oud|agar/i, "oud"],
  [/[aá]mbar/i, "amber"],
  [/lavanda/i, "lavender"],
  [/naranja|azahar/i, "orange blossom"]
];
const GENERALES = ["perfume bottle", "eau de parfum bottle", "fragrance bottle", "cologne bottle", "perfume flacon"];

function busquedasPara(p) {
  const texto = `${p.nombre} ${p.descripcion ?? ""}`;
  const nota = NOTAS.find(([patron]) => patron.test(texto))?.[1];
  return [...(nota ? [`${nota} perfume bottle`] : []), ...GENERALES];
}

async function buscar(termino) {
  const url = new URL(API);
  Object.entries({
    action: "query",
    format: "json",
    formatversion: "2",
    generator: "search",
    gsrnamespace: "6",
    gsrsearch: `${termino} filetype:bitmap`,
    gsrlimit: "15",
    prop: "imageinfo",
    iiprop: "url|mime",
    iiurlwidth: "600"
  }).forEach(([k, v]) => url.searchParams.set(k, v));
  const r = await fetch(url, { headers: CABECERAS });
  if (!r.ok) throw new Error(`Wikimedia respondió ${r.status}`);
  const datos = await r.json();
  return (datos.query?.pages ?? [])
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
    .map((p) => ({ titulo: p.title, info: p.imageinfo?.[0] }))
    .filter((p) => p.info?.thumburl && ["image/jpeg", "image/png"].includes(p.info.mime));
}

async function descargar(url) {
  const r = await fetch(url, { headers: CABECERAS });
  if (!r.ok) throw new Error(`descarga ${r.status}`);
  const bytes = Buffer.from(await r.arrayBuffer());
  const jpg = bytes[0] === 0xff && bytes[1] === 0xd8;
  const png = bytes[0] === 0x89 && bytes[1] === 0x50;
  if (!jpg && !png) throw new Error("no es una imagen JPG/PNG");
  if (bytes.length > MAXIMO_BYTES) throw new Error("pesa demasiado");
  return { bytes, tipo: jpg ? "image/jpeg" : "image/png" };
}

async function main() {
  const todos = process.argv.includes("--todos");
  const { rows: productos } = await query(
    `SELECT p.id_producto, p.nombre, p.descripcion, c.nombre AS categoria
       FROM productos p
       LEFT JOIN categorias c ON c.id_categoria = p.id_categoria
      WHERE p.nombre NOT ILIKE 'Prueba%'
        ${todos ? "" : "AND NOT EXISTS (SELECT 1 FROM producto_imagen i WHERE i.id_producto = p.id_producto)"}
      ORDER BY p.id_producto`
  );
  if (!productos.length) {
    console.log("\nTodos los productos ya tienen foto. Usa --todos para reemplazarlas.\n");
    return;
  }
  console.log(`\nBuscando fotos en Wikimedia Commons para ${productos.length} producto(s)...\n`);

  const usadas = new Set(); // que dos productos no queden con la misma foto
  const resultados = new Map(); // búsquedas ya hechas
  let puestas = 0;
  for (const p of productos) {
    let guardada = null;
    for (const termino of busquedasPara(p)) {
      try {
        if (!resultados.has(termino)) resultados.set(termino, await buscar(termino));
      } catch (e) {
        console.log(`  error ${p.nombre.padEnd(22)} ${e.message}`);
        break;
      }
      const candidatas = resultados.get(termino).filter((c) => !usadas.has(c.info.thumburl));
      for (const c of candidatas.slice(0, 6)) {
        try {
          const img = await descargar(c.info.thumburl);
          await query(
            `INSERT INTO producto_imagen (id_producto, contenido, tipo_mime) VALUES ($1, $2, $3)
             ON CONFLICT (id_producto) DO UPDATE
                SET contenido = EXCLUDED.contenido, tipo_mime = EXCLUDED.tipo_mime, actualizada_en = CURRENT_TIMESTAMP`,
            [p.id_producto, img.bytes, img.tipo]
          );
          usadas.add(c.info.thumburl);
          guardada = { ...c, termino, kb: Math.round(img.bytes.length / 1024) };
          break;
        } catch {
          /* esa no se pudo descargar: se prueba la siguiente */
        }
      }
      if (guardada) break;
    }
    if (guardada) {
      puestas++;
      console.log(`  ok    ${p.nombre.padEnd(22)} "${guardada.termino}" -> ${guardada.titulo} (${guardada.kb} KB)`);
    } else {
      console.log(`  --    ${p.nombre.padEnd(22)} sin foto (ponla desde la app)`);
    }
  }
  console.log(`\nListo: ${puestas} de ${productos.length} producto(s) con foto.`);
  console.log("Fotos de Wikimedia Commons (licencias libres). Puedes cambiar cualquiera desde la app:");
  console.log("Catálogo > producto > Cambiar foto.\n");
}

main()
  .catch((e) => {
    console.error(`\nNo se pudo completar: ${e.message}\n`);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
