/**
 * Prueba automática de la API.
 *
 *     npm run test:api                              (contra localhost)
 *     API_URL=https://mi-api.vercel.app npm run test:api   (contra el despliegue)
 *
 * Recorre las cinco operaciones de las cuatro entidades y, además, los casos
 * que deben fallar: datos inválidos, ids que no existen, valores repetidos y
 * borrados que romperían una relación.
 *
 * No usa ninguna librería de pruebas a propósito: se entiende leyéndola, y
 * sirve para mostrar la API funcionando en vivo durante la sustentación.
 *
 * IMPORTANTE: crea y borra registros. Úsalo contra la base de pruebas.
 */

const BASE = (process.env.API_URL ?? "http://localhost:3000").replace(/\/$/, "");

let pasadas = 0;
let falladas = 0;
const fallos = [];

/** Hace la petición y devuelve { estado, cuerpo }. */
async function pedir(metodo, ruta, cuerpo) {
  const respuesta = await fetch(`${BASE}${ruta}`, {
    method: metodo,
    headers: cuerpo ? { "Content-Type": "application/json" } : {},
    body: cuerpo ? JSON.stringify(cuerpo) : undefined
  });
  let datos = null;
  try {
    datos = await respuesta.json();
  } catch {
    datos = null;
  }
  return { estado: respuesta.status, cuerpo: datos };
}

/** Comprueba una condición y la anota. */
function comprobar(descripcion, condicion, detalle = "") {
  if (condicion) {
    pasadas += 1;
    console.log(`  ok    ${descripcion}`);
  } else {
    falladas += 1;
    fallos.push(descripcion);
    console.log(`  FALLA ${descripcion}${detalle ? ` -> ${detalle}` : ""}`);
  }
}

function titulo(texto) {
  console.log(`\n${texto}`);
  console.log("-".repeat(texto.length));
}

/**
 * El CRUD completo de una entidad. Las cuatro se prueban igual, así que la
 * secuencia se escribe una vez y se llama con los datos de cada una.
 */
async function probarCrud({ nombre, ruta, campoId, nuevo, editado, campoVisible }) {
  titulo(`${nombre}: CRUD completo`);

  const lista = await pedir("GET", `${ruta}?limit=5`);
  comprobar("listar responde 200", lista.estado === 200, `estado ${lista.estado}`);
  comprobar("la lista trae datos y paginación", Array.isArray(lista.cuerpo?.datos) && !!lista.cuerpo?.paginacion);

  const creado = await pedir("POST", ruta, nuevo);
  comprobar("crear responde 201", creado.estado === 201, `estado ${creado.estado} ${JSON.stringify(creado.cuerpo)}`);
  const id = creado.cuerpo?.datos?.[campoId];
  comprobar("crear devuelve el id asignado", Number.isInteger(id), `id ${id}`);

  if (!Number.isInteger(id)) {
    console.log("  (se omite el resto: sin id no se puede continuar)");
    return null;
  }

  const obtenido = await pedir("GET", `${ruta}/${id}`);
  comprobar("obtener por id responde 200", obtenido.estado === 200);
  comprobar(
    "el registro obtenido es el que se creó",
    obtenido.cuerpo?.datos?.[campoVisible] === nuevo[campoVisible],
    `${obtenido.cuerpo?.datos?.[campoVisible]} != ${nuevo[campoVisible]}`
  );

  const actualizado = await pedir("PUT", `${ruta}/${id}`, editado);
  comprobar("actualizar responde 200", actualizado.estado === 200, JSON.stringify(actualizado.cuerpo));
  comprobar(
    "el cambio quedó guardado",
    actualizado.cuerpo?.datos?.[campoVisible] === editado[campoVisible],
    `${actualizado.cuerpo?.datos?.[campoVisible]} != ${editado[campoVisible]}`
  );

  return id;
}

async function eliminar(ruta, id, nombre) {
  const borrado = await pedir("DELETE", `${ruta}/${id}`);
  comprobar(`${nombre}: eliminar responde 200`, borrado.estado === 200, JSON.stringify(borrado.cuerpo));
  const luego = await pedir("GET", `${ruta}/${id}`);
  comprobar(`${nombre}: ya no existe después de borrarlo`, luego.estado === 404, `estado ${luego.estado}`);
}

async function main() {
  console.log(`\nProbando la API en ${BASE}`);

  titulo("Estado del servicio");
  const salud = await pedir("GET", "/api/health");
  comprobar("/api/health responde 200", salud.estado === 200, `estado ${salud.estado}`);
  comprobar("la base de datos está conectada", salud.cuerpo?.baseDeDatos === "conectada", JSON.stringify(salud.cuerpo));

  if (salud.estado !== 200) {
    console.log("\nLa API no responde. ¿Está levantada? (npm run dev)\n");
    process.exitCode = 1;
    return;
  }

  const indice = await pedir("GET", "/api");
  comprobar("el índice /api lista los recursos", indice.estado === 200 && !!indice.cuerpo?.recursos);

  titulo("Páginas web");
  for (const [ruta, marca] of [
    ["/", "API de gestión de fragancias"],
    ["/panel", "Panel de gestión"],
    ["/docs", "swagger-ui-bundle.js"]
  ]) {
    const pagina = await fetch(`${BASE}${ruta}`);
    const html = await pagina.text();
    comprobar(`${ruta} responde 200`, pagina.status === 200, `estado ${pagina.status}`);
    comprobar(
      `${ruta} devuelve HTML`,
      (pagina.headers.get("content-type") ?? "").includes("text/html")
    );
    comprobar(`${ruta} trae su contenido`, html.includes(marca));
  }

  titulo("Documentación");
  const spec = await pedir("GET", "/api/openapi.json");
  comprobar("/api/openapi.json responde 200", spec.estado === 200);
  comprobar("es una especificación OpenAPI 3", String(spec.cuerpo?.openapi ?? "").startsWith("3."));
  const operaciones = Object.values(spec.cuerpo?.paths ?? {}).reduce(
    (total, ruta) => total + Object.keys(ruta).length,
    0
  );
  // 21 del CRUD base + 27 del proceso de ventas + 6 de usuarios + 3 de registro/recuperación.
  comprobar("describe las 57 operaciones", operaciones === 57, `describe ${operaciones}`);
  comprobar(
    "el servidor de la spec apunta a esta API",
    spec.cuerpo?.servers?.[0]?.url === BASE,
    `${spec.cuerpo?.servers?.[0]?.url} != ${BASE}`
  );

  const docs = await fetch(`${BASE}/docs`);
  const html = await docs.text();
  comprobar("/docs apunta a la especificación", html.includes("/api/openapi.json"));

  // Marca de tiempo para que los datos de prueba no choquen con los de una
  // corrida anterior (los correos y los SKU no se pueden repetir).
  const marca = Date.now().toString().slice(-6);

  const idCategoria = await probarCrud({
    nombre: "Categorías",
    ruta: "/api/categorias",
    campoId: "id_categoria",
    campoVisible: "nombre",
    nuevo: { nombre: `Prueba ${marca}`, descripcion: "Creada por el script de pruebas", estado: true },
    editado: { nombre: `Prueba ${marca} editada`, descripcion: "Descripción cambiada" }
  });

  const idProveedor = await probarCrud({
    nombre: "Proveedores",
    ruta: "/api/proveedores",
    campoId: "id_proveedor",
    campoVisible: "nombre",
    nuevo: {
      nombre: `Proveedor Prueba ${marca}`,
      contacto: "Contacto de prueba",
      email: `prueba${marca}@proveedor.com`,
      telefono: "+57 300 000 0000",
      ciudad: "Medellín",
      calificacion: 4.5
    },
    editado: { nombre: `Proveedor Prueba ${marca} editado`, ciudad: "Bogotá" }
  });

  const idCliente = await probarCrud({
    nombre: "Clientes",
    ruta: "/api/clientes",
    campoId: "id_cliente",
    campoVisible: "nombre",
    nuevo: {
      nombre: `Cliente Prueba ${marca}`,
      correo: `cliente${marca}@correo.com`,
      telefono: "+57 310 000 0000",
      direccion: "Calle falsa 123",
      ciudad: "Cali"
    },
    editado: { nombre: `Cliente Prueba ${marca} editado`, ciudad: "Medellín" }
  });

  let idProducto = null;
  if (idCategoria && idProveedor) {
    idProducto = await probarCrud({
      nombre: "Productos",
      ruta: "/api/productos",
      campoId: "id_producto",
      campoVisible: "nombre",
      nuevo: {
        sku: `TST-${marca}`,
        nombre: `Producto Prueba ${marca}`,
        descripcion: "Creado por el script de pruebas",
        id_categoria: idCategoria,
        id_proveedor: idProveedor,
        precio: 99000,
        stock: 10,
        stock_minimo: 5
      },
      editado: { nombre: `Producto Prueba ${marca} editado`, precio: 120000, stock: 3 }
    });
  }

  // ----------------------------------------------------------------
  titulo("Relaciones entre tablas");
  const conJoin = await pedir("GET", `/api/productos/${idProducto}`);
  comprobar(
    "el producto trae el nombre de su categoría y su proveedor",
    !!conJoin.cuerpo?.datos?.categoria && !!conJoin.cuerpo?.datos?.proveedor,
    JSON.stringify(conJoin.cuerpo?.datos)
  );
  comprobar(
    "marca el stock bajo cuando stock <= stock_minimo",
    conJoin.cuerpo?.datos?.stock_bajo === true,
    `stock ${conJoin.cuerpo?.datos?.stock} / mínimo ${conJoin.cuerpo?.datos?.stock_minimo}`
  );

  const borrarCategoriaEnUso = await pedir("DELETE", `/api/categorias/${idCategoria}`);
  comprobar(
    "no deja borrar una categoría que tiene productos",
    borrarCategoriaEnUso.estado === 409,
    `estado ${borrarCategoriaEnUso.estado}`
  );

  const borrarProveedorEnUso = await pedir("DELETE", `/api/proveedores/${idProveedor}`);
  comprobar(
    "no deja borrar un proveedor que surte productos",
    borrarProveedorEnUso.estado === 409,
    `estado ${borrarProveedorEnUso.estado}`
  );

  // ----------------------------------------------------------------
  titulo("Validaciones");
  const sinNombre = await pedir("POST", "/api/categorias", { descripcion: "sin nombre" });
  comprobar("rechaza una categoría sin nombre", sinNombre.estado === 400);
  comprobar("dice cuál campo falló", !!sinNombre.cuerpo?.detalles?.nombre, JSON.stringify(sinNombre.cuerpo));

  const correoMalo = await pedir("POST", "/api/clientes", { nombre: "Alguien", correo: "esto-no-es-un-correo" });
  comprobar("rechaza un correo con formato inválido", correoMalo.estado === 400);

  const precioNegativo = await pedir("POST", "/api/productos", {
    sku: `NEG-${marca}`,
    nombre: "Precio negativo",
    id_categoria: idCategoria,
    id_proveedor: idProveedor,
    precio: -5000
  });
  comprobar("rechaza un precio negativo", precioNegativo.estado === 400);

  const categoriaInexistente = await pedir("POST", "/api/productos", {
    sku: `REF-${marca}`,
    nombre: "Categoría inexistente",
    id_categoria: 999999,
    id_proveedor: idProveedor,
    precio: 1000
  });
  comprobar("rechaza un producto con categoría inexistente", categoriaInexistente.estado === 400);

  const repetida = await pedir("POST", "/api/categorias", { nombre: `Prueba ${marca} editada` });
  comprobar("rechaza una categoría con nombre repetido", repetida.estado === 409, `estado ${repetida.estado}`);

  // ----------------------------------------------------------------
  titulo("Errores");
  const noExiste = await pedir("GET", "/api/productos/999999");
  comprobar("un id inexistente devuelve 404", noExiste.estado === 404);

  const idInvalido = await pedir("GET", "/api/productos/abc");
  comprobar("un id que no es número devuelve 400", idInvalido.estado === 400);

  const rutaInventada = await pedir("GET", "/api/inventado");
  comprobar("una ruta que no existe devuelve 404", rutaInventada.estado === 404);

  // ----------------------------------------------------------------
  titulo("Búsqueda, filtros y paginación");
  const paginado = await pedir("GET", "/api/productos?limit=2&page=1");
  comprobar("limit=2 devuelve como máximo 2 registros", (paginado.cuerpo?.datos?.length ?? 99) <= 2);
  comprobar("informa el total de páginas", Number.isInteger(paginado.cuerpo?.paginacion?.totalPaginas));

  const limiteAbusivo = await pedir("GET", "/api/productos?limit=99999");
  comprobar("recorta un limit exagerado a 100", limiteAbusivo.cuerpo?.paginacion?.porPagina === 100);

  const buscado = await pedir("GET", `/api/productos?search=${marca}`);
  comprobar("la búsqueda encuentra el producto de prueba", (buscado.cuerpo?.datos?.length ?? 0) >= 1);

  const inyeccion = await pedir("GET", "/api/productos?sortBy=nombre;DROP TABLE productos;--");
  comprobar("ignora un intento de inyección por sortBy", inyeccion.estado === 200);
  const siguenVivos = await pedir("GET", "/api/productos?limit=1");
  comprobar("la tabla productos sigue existiendo", siguenVivos.estado === 200);

  // ----------------------------------------------------------------
  titulo("Limpieza");
  if (idProducto) await eliminar("/api/productos", idProducto, "Productos");
  if (idCategoria) await eliminar("/api/categorias", idCategoria, "Categorías");
  if (idProveedor) await eliminar("/api/proveedores", idProveedor, "Proveedores");
  if (idCliente) await eliminar("/api/clientes", idCliente, "Clientes");

  // ----------------------------------------------------------------
  console.log("\n" + "=".repeat(52));
  console.log(`  Pruebas pasadas: ${pasadas}`);
  console.log(`  Pruebas falladas: ${falladas}`);
  console.log("=".repeat(52));

  if (falladas > 0) {
    console.log("\nFallaron:");
    for (const fallo of fallos) console.log(`  - ${fallo}`);
    process.exitCode = 1;
  } else {
    console.log("\nTodo en orden.\n");
  }
}

main().catch((error) => {
  console.error("\nNo se pudo ejecutar la prueba:", error.message);
  console.error("¿Está la API levantada en", BASE, "?\n");
  process.exitCode = 1;
});
