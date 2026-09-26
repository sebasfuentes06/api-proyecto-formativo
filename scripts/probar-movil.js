/**
 * Prueba automática de los módulos de la APP MÓVIL.
 *
 *     npm run test:movil                                   (contra localhost)
 *     API_URL=https://mi-api.vercel.app npm run test:movil (contra el despliegue)
 *
 * Variables:
 *   ADMIN_CORREO / ADMIN_PASSWORD   credenciales del administrador
 *   WOMPI_SIMULADO=1                prueba Wompi contra un Wompi falso que
 *                                   este script levanta en el puerto 4010
 *                                   (la API debe tener WOMPI_API_URL=http://localhost:4010/v1
 *                                   y WOMPI_SECRETO_EVENTOS igual al de aquí)
 *
 * Recorre el proceso de ventas completo: cliente -> pedido -> venta ->
 * abonos -> estado de cuenta, más los casos que deben fallar (stock
 * insuficiente, abono mayor al saldo, pedido ya convertido, sin sesión...).
 *
 * IMPORTANTE: crea registros (y anula lo que puede). Úsalo en la base de pruebas.
 */
import { createServer } from "node:http";
import { createHash } from "node:crypto";

const BASE = (process.env.API_URL ?? "http://localhost:3000").replace(/\/$/, "");
const CORREO = process.env.ADMIN_CORREO ?? "admin@essence.com";
const CLAVE = process.env.ADMIN_PASSWORD ?? "Essence2026*";
const SIMULAR_WOMPI = process.env.WOMPI_SIMULADO === "1";
const SECRETO_EVENTOS = process.env.WOMPI_SECRETO_EVENTOS ?? "test_events_fake";

let token = null;
let pasadas = 0;
let falladas = 0;
const fallos = [];

async function pedir(metodo, ruta, cuerpo, { sinToken = false } = {}) {
  const r = await fetch(`${BASE}${ruta}`, {
    method: metodo,
    headers: {
      ...(cuerpo ? { "Content-Type": "application/json" } : {}),
      ...(token && !sinToken ? { Authorization: `Bearer ${token}` } : {})
    },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined
  });
  const tipo = r.headers.get("content-type") ?? "";
  const datos = tipo.includes("json") ? await r.json().catch(() => null) : await r.arrayBuffer();
  return { estado: r.status, cuerpo: datos, tipo };
}

function comprobar(descripcion, condicion, detalle = "") {
  if (condicion) {
    pasadas += 1;
    console.log(`  ok    ${descripcion}`);
  } else {
    falladas += 1;
    fallos.push(descripcion);
    console.log(`  FALLA ${descripcion}${detalle ? ` -> ${typeof detalle === "string" ? detalle : JSON.stringify(detalle)}` : ""}`);
  }
}

const titulo = (t) => console.log(`\n${t}\n${"-".repeat(t.length)}`);
const num = (v) => Number(v);

/** Wompi falso: crea links y responde transacciones que el script define. */
function levantarWompiFalso() {
  const transacciones = new Map();
  let n = 0;
  const servidor = createServer((req, res) => {
    let cuerpo = "";
    req.on("data", (c) => (cuerpo += c));
    req.on("end", () => {
      res.setHeader("Content-Type", "application/json");
      if (req.method === "POST" && req.url === "/v1/payment_links") {
        const datos = JSON.parse(cuerpo || "{}");
        if (req.headers.authorization !== "Bearer prv_test_fake") {
          res.statusCode = 401;
          return res.end(JSON.stringify({ error: { type: "INVALID_ACCESS_TOKEN", reason: "Llave inválida" } }));
        }
        n += 1;
        return res.end(JSON.stringify({ data: { id: `LNK${Date.now()}${n}`, ...datos } }));
      }
      const m = req.url.match(/^\/v1\/transactions\/(.+)$/);
      if (req.method === "GET" && m) {
        const tx = transacciones.get(decodeURIComponent(m[1]));
        if (!tx) {
          res.statusCode = 404;
          return res.end(JSON.stringify({ error: { type: "NOT_FOUND_ERROR", reason: "No existe" } }));
        }
        return res.end(JSON.stringify({ data: tx }));
      }
      res.statusCode = 404;
      res.end("{}");
    });
  });
  return new Promise((ok) => servidor.listen(4010, () => ok({ servidor, transacciones })));
}

function eventoFirmado(tx, secreto = SECRETO_EVENTOS) {
  const timestamp = Math.floor(Date.now() / 1000);
  const properties = ["transaction.id", "transaction.status", "transaction.amount_in_cents"];
  const checksum = createHash("sha256")
    .update(`${tx.id}${tx.status}${tx.amount_in_cents}${timestamp}${secreto}`)
    .digest("hex")
    .toUpperCase();
  return { event: "transaction.updated", data: { transaction: tx }, environment: "test", signature: { properties, checksum }, timestamp };
}

async function main() {
  console.log(`\nProbando la app móvil contra ${BASE}`);

  // ------------------------------------------------------------------
  titulo("Sesión");
  let r = await pedir("GET", "/api/ventas");
  comprobar("sin token: ventas responde 401", r.estado === 401, r.estado);
  r = await pedir("POST", "/api/auth/login", { correo: CORREO, password: "clave-equivocada" });
  comprobar("login con clave mala responde 401", r.estado === 401, r.estado);
  r = await pedir("POST", "/api/auth/login", { correo: CORREO, password: CLAVE });
  comprobar("login correcto responde 200 con token", r.estado === 200 && !!r.cuerpo?.datos?.token, r.cuerpo);
  token = r.cuerpo?.datos?.token;
  if (!token) throw new Error("Sin token no se puede seguir. Revisa ADMIN_CORREO / ADMIN_PASSWORD.");
  r = await pedir("GET", "/api/auth/yo");
  comprobar("/auth/yo devuelve al administrador", r.cuerpo?.datos?.correo === CORREO);
  const alterado = await fetch(`${BASE}/api/ventas`, { headers: { Authorization: `Bearer ${token.slice(0, -2)}xx` } });
  comprobar("token alterado es rechazado (401)", alterado.status === 401);

  // ------------------------------------------------------------------
  titulo("Preparación: cliente y productos");
  const marca = Date.now();
  const fichaBase = { nombre: `Cliente App ${marca}`, tipo_documento: "CC", documento: String(marca).slice(-10), telefono: "3001234567", ciudad: "La Pintada", direccion: "Calle 1 # 2-3" };
  r = await pedir("POST", "/api/clientes", { ...fichaBase, tipo_documento: undefined, documento: undefined });
  comprobar("desde la app, cliente sin tipo ni número de documento: 400", r.estado === 400 && !!r.cuerpo?.detalles?.tipo_documento && !!r.cuerpo?.detalles?.documento, r.cuerpo);
  r = await pedir("POST", "/api/clientes", { ...fichaBase, telefono: "300-12a" });
  comprobar("celular con letras o incompleto: 400", r.estado === 400 && !!r.cuerpo?.detalles?.telefono, r.cuerpo);
  r = await pedir("POST", "/api/clientes", { ...fichaBase, ciudad: "" });
  comprobar("cliente sin municipio: 400", r.estado === 400 && !!r.cuerpo?.detalles?.ciudad);
  r = await pedir("POST", "/api/clientes", fichaBase);
  comprobar("cliente sin correo se crea (201) con tipo de documento", r.estado === 201 && r.cuerpo?.datos?.tipo_documento === "CC", r.cuerpo);
  const idCliente = r.cuerpo?.datos?.id_cliente;
  comprobar("el cliente nuevo arranca sin saldo", num(r.cuerpo?.datos?.saldo_pendiente) === 0);

  const { cuerpo: cat } = await pedir("GET", "/api/categorias?limit=1");
  const { cuerpo: prov } = await pedir("GET", "/api/proveedores?limit=1");
  const nuevoProducto = async (sku, precio, stock) =>
    (
      await pedir("POST", "/api/productos", {
        sku, nombre: `Prueba ${sku}`, precio, stock, stock_minimo: 1,
        id_categoria: cat.datos[0].id_categoria, id_proveedor: prov.datos[0].id_proveedor
      })
    ).cuerpo?.datos;
  const pA = await nuevoProducto(`APP-A-${marca}`, 100000, 10);
  const pB = await nuevoProducto(`APP-B-${marca}`, 50000, 3);
  comprobar("productos de prueba creados", pA?.id_producto && pB?.id_producto);
  const stockDe = async (id) => (await pedir("GET", `/api/productos/${id}`)).cuerpo?.datos?.stock;

  // ------------------------------------------------------------------
  titulo("Catálogo: imagen de producto");
  const png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  r = await pedir("PUT", `/api/productos/${pA.id_producto}/imagen`, { base64: png1x1, tipo_mime: "image/png" }, { sinToken: true });
  comprobar("subir imagen sin sesión: 401", r.estado === 401);
  r = await pedir("PUT", `/api/productos/${pA.id_producto}/imagen`, { base64: png1x1, tipo_mime: "image/png" });
  comprobar("subir imagen: 200", r.estado === 200, r.cuerpo);
  r = await pedir("GET", `/api/productos/${pA.id_producto}/imagen`, null, { sinToken: true });
  comprobar("la imagen se descarga como image/png", r.estado === 200 && r.tipo.startsWith("image/png"));
  r = await pedir("GET", `/api/productos/${pA.id_producto}`);
  comprobar("el producto informa que tiene imagen", !!r.cuerpo?.datos?.imagen_actualizada);
  r = await pedir("PUT", `/api/productos/${pA.id_producto}/imagen`, { base64: "AAAA", tipo_mime: "image/gif" });
  comprobar("formato gif rechazado (400)", r.estado === 400);

  // ------------------------------------------------------------------
  titulo("Pedidos");
  r = await pedir("POST", "/api/pedidos", { id_cliente: idCliente, canal: "whatsapp", items: [{ id_producto: pB.id_producto, cantidad: 5 }] });
  comprobar("pedido con más unidades que el stock: 409", r.estado === 409, r.cuerpo);
  r = await pedir("POST", "/api/pedidos", { id_cliente: idCliente, canal: "whatsapp", items: [] });
  comprobar("pedido sin productos: 400", r.estado === 400);
  r = await pedir("POST", "/api/pedidos", {
    id_cliente: idCliente, canal: "whatsapp", direccion_entrega: "Vereda El Cedrón",
    items: [{ id_producto: pA.id_producto, cantidad: 1 }, { id_producto: pA.id_producto, cantidad: 1 }, { id_producto: pB.id_producto, cantidad: 1 }]
  });
  comprobar("crear pedido: 201", r.estado === 201, r.cuerpo);
  const pedido = r.cuerpo?.datos;
  comprobar("productos repetidos se suman (2 x A)", pedido?.items?.find((i) => i.id_producto === pA.id_producto)?.cantidad === 2);
  comprobar("total del pedido = 2x100000 + 50000", num(pedido?.total) === 250000, pedido?.total);
  comprobar("el pedido NO descuenta stock", (await stockDe(pA.id_producto)) === 10);

  r = await pedir("PUT", `/api/pedidos/${pedido.id_pedido}`, { items: [{ id_producto: pA.id_producto, cantidad: 3 }], notas: "Entregar en la tarde" });
  comprobar("editar pedido pendiente: 200", r.estado === 200, r.cuerpo);
  comprobar("el total se recalcula al editar", num(r.cuerpo?.datos?.total) === 300000, r.cuerpo?.datos?.total);

  r = await pedir("GET", "/api/pedidos?estado=pendiente");
  comprobar("listar pedidos pendientes lo incluye", r.cuerpo?.datos?.some((p) => p.id_pedido === pedido.id_pedido));

  r = await pedir("POST", `/api/pedidos/${pedido.id_pedido}/convertir`, { descuento: 20000, pago_inicial: { monto: 100000, metodo: "nequi", referencia: "NQ123" } });
  comprobar("convertir pedido en venta: 201", r.estado === 201, r.cuerpo);
  const ventaPedido = r.cuerpo?.datos;
  comprobar("la venta tiene número de factura FV-", /^FV-\d{6}$/.test(ventaPedido?.numero_factura ?? ""));
  comprobar("total de la venta con descuento = 280000", num(ventaPedido?.total) === 280000, ventaPedido?.total);
  comprobar("el abono inicial queda aplicado (saldo 180000)", num(ventaPedido?.saldo) === 180000, ventaPedido?.saldo);
  comprobar("estado de pago: parcial", ventaPedido?.estado_pago === "parcial");
  comprobar("ahora sí se descuenta el stock (10 -> 7)", (await stockDe(pA.id_producto)) === 7);

  r = await pedir("GET", `/api/pedidos/${pedido.id_pedido}`);
  comprobar("el pedido queda confirmado y enlazado a la venta", r.cuerpo?.datos?.estado === "confirmado" && r.cuerpo?.datos?.id_venta === ventaPedido.id_venta);
  r = await pedir("POST", `/api/pedidos/${pedido.id_pedido}/convertir`, {});
  comprobar("convertir dos veces: 409", r.estado === 409);
  r = await pedir("PUT", `/api/pedidos/${pedido.id_pedido}`, { notas: "x" });
  comprobar("editar un pedido confirmado: 409", r.estado === 409);

  r = await pedir("POST", "/api/pedidos", { id_cliente: idCliente, canal: "punto_fisico", items: [{ id_producto: pB.id_producto, cantidad: 1 }] });
  const pedido2 = r.cuerpo?.datos;
  r = await pedir("POST", `/api/pedidos/${pedido2.id_pedido}/cancelar`, { motivo: "El cliente desistió" });
  comprobar("cancelar pedido: 200 y estado cancelado", r.estado === 200 && r.cuerpo?.datos?.estado === "cancelado", r.cuerpo);

  // ------------------------------------------------------------------
  titulo("Ventas directas");
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, items: [{ id_producto: pB.id_producto, cantidad: 1 }] });
  comprobar("venta sin método de pago: 400", r.estado === 400 && !!r.cuerpo?.detalles?.metodo_pago, r.cuerpo);
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "bitcoin", items: [{ id_producto: pB.id_producto, cantidad: 1 }] });
  comprobar("venta con método de pago inventado: 400", r.estado === 400);
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "efectivo", items: [{ id_producto: pB.id_producto, cantidad: 4 }] });
  comprobar("vender más que el stock: 409", r.estado === 409, r.cuerpo);
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, items: [{ id_producto: pB.id_producto, cantidad: 1 }], descuento: 999999, metodo_pago: "efectivo" });
  comprobar("descuento mayor que el subtotal: 400", r.estado === 400);
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, items: [{ id_producto: pB.id_producto, cantidad: 1 }], pago_inicial: { monto: 60000, metodo: "efectivo" } });
  comprobar("pago inicial mayor que el total: 409", r.estado === 409, r.cuerpo);
  comprobar("una venta rechazada no toca el stock (B sigue en 3)", (await stockDe(pB.id_producto)) === 3);

  r = await pedir("POST", "/api/ventas", {
    id_cliente: idCliente, canal: "punto_fisico", metodo_pago: "nequi",
    items: [{ id_producto: pB.id_producto, cantidad: 1 }],
    pago_inicial: { monto: 50000, referencia: "NQ-1", comprobante: { base64: png1x1, tipo_mime: "image/png" } }
  });
  comprobar("venta de contado: 201 y pagada", r.estado === 201 && r.cuerpo?.datos?.estado_pago === "pagada", r.cuerpo);
  comprobar("la venta guarda su método de pago y el pago inicial lo hereda",
    r.cuerpo?.datos?.metodo_pago === "nequi" && r.cuerpo?.datos?.pagos?.[0]?.metodo === "nequi", r.cuerpo?.datos);
  comprobar("el pago inicial guarda su comprobante", r.cuerpo?.datos?.pagos?.[0]?.tiene_comprobante === true);
  const ventaContado = r.cuerpo?.datos;

  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "wompi", items: [{ id_producto: pB.id_producto, cantidad: 1, precio_unitario: 45000 }] });
  comprobar("venta a crédito con precio especial: 201 y pendiente", r.estado === 201 && r.cuerpo?.datos?.estado_pago === "pendiente" && num(r.cuerpo?.datos?.total) === 45000, r.cuerpo);
  const ventaCredito = r.cuerpo?.datos;

  // Dos ventas simultáneas por la última unidad: solo una debe pasar.
  const [c1, c2] = await Promise.all([
    pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "efectivo", items: [{ id_producto: pB.id_producto, cantidad: 1 }] }),
    pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "efectivo", items: [{ id_producto: pB.id_producto, cantidad: 1 }] })
  ]);
  const estados = [c1.estado, c2.estado].sort();
  comprobar("dos ventas simultáneas del último frasco: una 201 y otra 409", estados[0] === 201 && estados[1] === 409, estados);
  comprobar("el stock nunca queda negativo (B = 0)", (await stockDe(pB.id_producto)) === 0);
  const ventaUltima = (c1.estado === 201 ? c1 : c2).cuerpo?.datos;

  r = await pedir("GET", `/api/ventas?id_cliente=${idCliente}&limit=50`);
  comprobar("historial de ventas filtrado por cliente", r.cuerpo?.datos?.length === 4, r.cuerpo?.datos?.length);
  r = await pedir("GET", `/api/ventas?estado_pago=con_saldo&id_cliente=${idCliente}`);
  comprobar("filtro con_saldo trae solo las que deben", r.cuerpo?.datos?.every((v) => num(v.saldo) > 0));

  r = await pedir("GET", `/api/ventas/${ventaPedido.id_venta}`);
  comprobar("detalle de venta trae items, pagos y cliente", r.cuerpo?.datos?.items?.length === 1 && r.cuerpo?.datos?.pagos?.length === 1 && !!r.cuerpo?.datos?.cliente);

  // ------------------------------------------------------------------
  titulo("Pagos y abonos");
  r = await pedir("POST", "/api/pagos", { id_venta: ventaPedido.id_venta, monto: 500000, metodo: "efectivo" });
  comprobar("abono mayor que el saldo: 409", r.estado === 409);
  r = await pedir("POST", "/api/pagos", { id_venta: ventaPedido.id_venta, monto: 1000, metodo: "bitcoin" });
  comprobar("método de pago inválido: 400", r.estado === 400);
  r = await pedir("POST", "/api/pagos", { id_venta: ventaPedido.id_venta, monto: 80000, metodo: "transferencia", referencia: "TR-555" });
  comprobar("abono parcial: 201, saldo 100000", r.estado === 201 && r.cuerpo?.datos?.venta?.saldo === 100000, r.cuerpo);
  const abono = r.cuerpo?.datos?.pago;
  r = await pedir("POST", "/api/pagos", { id_venta: ventaPedido.id_venta, monto: 100000, metodo: "daviplata" });
  comprobar("abono final deja la venta pagada", r.cuerpo?.datos?.venta?.estado_pago === "pagada", r.cuerpo);
  r = await pedir("POST", "/api/pagos", { id_venta: ventaPedido.id_venta, monto: 1, metodo: "efectivo" });
  comprobar("pagar una venta ya pagada: 409", r.estado === 409);
  r = await pedir("POST", `/api/pagos/${abono.id_pago}/anular`, { motivo: "Transferencia devuelta" });
  comprobar("anular un abono sube el saldo otra vez (80000)", r.estado === 200 && r.cuerpo?.datos?.venta?.saldo === 80000, r.cuerpo);
  r = await pedir("GET", `/api/pagos?id_venta=${ventaPedido.id_venta}`);
  comprobar("listar pagos de la venta (3, uno anulado)", r.cuerpo?.datos?.length === 3 && r.cuerpo?.datos?.filter((p) => p.estado === "anulado").length === 1);

  r = await pedir("GET", `/api/clientes/${idCliente}/estado-cuenta`);
  const cuenta = r.cuerpo?.datos?.resumen;
  // pendiente: 80000 (ventaPedido) + 45000 (crédito) + 50000 (última unidad)
  comprobar("estado de cuenta: saldo = 175000", cuenta?.saldo === 175000, cuenta);
  r = await pedir("GET", `/api/clientes/${idCliente}`);
  comprobar("el cliente muestra saldo_pendiente 175000 y 4 compras", num(r.cuerpo?.datos?.saldo_pendiente) === 175000 && r.cuerpo?.datos?.compras === 4, r.cuerpo?.datos);
  r = await pedir("GET", `/api/clientes/${idCliente}/historial`);
  comprobar("historial de compras con productos", r.cuerpo?.datos?.ventas?.[0]?.productos?.length >= 1 && r.cuerpo?.datos?.favoritos?.length >= 1);
  r = await pedir("GET", "/api/pagos/pendientes");
  comprobar("reporte de pagos pendientes incluye al cliente", r.cuerpo?.datos?.clientes?.some((c) => c.id_cliente === idCliente && c.saldo === 175000), r.cuerpo?.datos?.clientes?.find((c) => c.id_cliente === idCliente));

  // ------------------------------------------------------------------
  titulo("Anular venta");
  r = await pedir("POST", `/api/ventas/${ventaContado.id_venta}/anular`, {});
  comprobar("anular sin motivo: 400", r.estado === 400);
  r = await pedir("POST", `/api/ventas/${ventaContado.id_venta}/anular`, { motivo: "Producto defectuoso" });
  comprobar("anular venta: 200, estado anulada", r.estado === 200 && r.cuerpo?.datos?.estado === "anulada", r.cuerpo);
  comprobar("anular devuelve el stock (B = 1)", (await stockDe(pB.id_producto)) === 1);
  comprobar("anular anula también sus pagos", r.cuerpo?.datos?.pagos?.every((p) => p.estado === "anulado"));
  r = await pedir("POST", `/api/ventas/${ventaContado.id_venta}/anular`, { motivo: "otra vez" });
  comprobar("anular dos veces: 409", r.estado === 409);
  r = await pedir("POST", `/api/ventas/${ventaPedido.id_venta}/anular`, { motivo: "Prueba de pedido" });
  r = await pedir("GET", `/api/pedidos/${pedido.id_pedido}`);
  comprobar("anular una venta que vino de un pedido cancela el pedido", r.cuerpo?.datos?.estado === "cancelado");

  // ------------------------------------------------------------------
  titulo("Roles: usuarios, Vendedor y Cliente");
  const tokenAdmin = token;
  const como = async (t, metodo, ruta, cuerpo) => {
    const previo = token;
    token = t;
    try {
      return await pedir(metodo, ruta, cuerpo);
    } finally {
      token = previo;
    }
  };

  r = await pedir("POST", "/api/usuarios", { nombre: "Sin ficha", correo: `sinficha${marca}@essence.com`, password: "Clave12345", rol: "Cliente" });
  comprobar("usuario Cliente sin ficha de cliente: 400", r.estado === 400, r.cuerpo);
  r = await pedir("POST", "/api/usuarios", { nombre: "Rol raro", correo: `raro${marca}@essence.com`, password: "Clave12345", rol: "Supervisor" });
  comprobar("rol inexistente: 400", r.estado === 400);

  r = await pedir("POST", "/api/usuarios", { nombre: `Vendedor ${marca}`, correo: `vendedor${marca}@essence.com`, password: "Clave12345", rol: "Vendedor" });
  comprobar("crear usuario Vendedor: 201", r.estado === 201, r.cuerpo);
  const idVendedor = r.cuerpo?.datos?.id_usuario;
  r = await pedir("POST", "/api/usuarios", { nombre: `Cliente ${marca}`, correo: `cliente${marca}@essence.com`, password: "Clave12345", rol: "Cliente", id_cliente: idCliente });
  comprobar("crear usuario Cliente enlazado a su ficha: 201", r.estado === 201 && r.cuerpo?.datos?.id_cliente === idCliente, r.cuerpo);
  const idUsuarioCliente = r.cuerpo?.datos?.id_usuario;
  r = await pedir("POST", "/api/usuarios", { nombre: "Otro", correo: `otro${marca}@essence.com`, password: "Clave12345", rol: "Cliente", id_cliente: idCliente });
  comprobar("la misma ficha no puede tener dos usuarios: 409", r.estado === 409);
  r = await pedir("GET", "/api/usuarios?limit=50");
  comprobar("listar usuarios (Administrador)", r.estado === 200 && r.cuerpo?.datos?.some((u) => u.id_usuario === idVendedor));

  const login = async (correo) => (await pedir("POST", "/api/auth/login", { correo, password: "Clave12345" })).cuerpo?.datos;
  const sesionV = await login(`vendedor${marca}@essence.com`);
  const sesionC = await login(`cliente${marca}@essence.com`);
  comprobar("el Vendedor inicia sesión", sesionV?.usuario?.rol === "Vendedor");
  comprobar("el Cliente inicia sesión y trae su id_cliente", sesionC?.usuario?.rol === "Cliente" && sesionC?.usuario?.id_cliente === idCliente);
  const tV = sesionV?.token;
  const tC = sesionC?.token;

  // --- Vendedor
  r = await como(tV, "GET", "/api/usuarios");
  comprobar("Vendedor no gestiona usuarios (403)", r.estado === 403);
  r = await como(tV, "PUT", `/api/productos/${pA.id_producto}`, { precio: 1 });
  comprobar("Vendedor no edita el catálogo (403)", r.estado === 403);
  r = await como(tV, "PUT", `/api/productos/${pA.id_producto}/imagen`, { base64: png1x1, tipo_mime: "image/png" });
  comprobar("Vendedor no cambia fotos (403)", r.estado === 403);
  r = await como(tV, "PUT", `/api/clientes/${idCliente}`, { direccion: "Calle nueva 1" });
  comprobar("Vendedor sí edita datos de un cliente", r.estado === 200, r.cuerpo);
  r = await como(tV, "PUT", `/api/clientes/${idCliente}`, { estado: false });
  comprobar("Vendedor no desactiva clientes (403)", r.estado === 403);
  r = await como(tV, "POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "transferencia", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("Vendedor registra una venta", r.estado === 201, r.cuerpo);
  const ventaVendedor = r.cuerpo?.datos;
  r = await como(tV, "POST", "/api/pagos", { id_venta: ventaVendedor?.id_venta, monto: 10000, metodo: "efectivo" });
  comprobar("Vendedor registra un abono", r.estado === 201);
  const abonoVendedor = r.cuerpo?.datos?.pago;
  r = await como(tV, "POST", `/api/pagos/${abonoVendedor?.id_pago}/anular`, { motivo: "prueba" });
  comprobar("Vendedor no anula pagos (403)", r.estado === 403);
  r = await como(tV, "POST", `/api/ventas/${ventaVendedor?.id_venta}/anular`, { motivo: "prueba" });
  comprobar("Vendedor no anula ventas (403)", r.estado === 403);
  r = await como(tV, "GET", "/api/dashboard/resumen");
  comprobar("el resumen del Vendedor es solo de sus ventas", r.cuerpo?.datos?.alcance === "mis_ventas" && Number(r.cuerpo?.datos?.ventas_hoy) === 100000, r.cuerpo?.datos);

  // --- Cliente
  r = await como(tC, "GET", "/api/clientes");
  comprobar("Cliente no ve la lista de clientes (403)", r.estado === 403);
  r = await como(tC, "GET", `/api/clientes/${idCliente}`);
  comprobar("Cliente sí ve su propia ficha", r.estado === 200);
  const { cuerpo: otros } = await pedir("GET", "/api/clientes?limit=5");
  const otroCliente = otros?.datos?.find((c) => c.id_cliente !== idCliente)?.id_cliente;
  r = await como(tC, "GET", `/api/clientes/${otroCliente}/estado-cuenta`);
  comprobar("Cliente no ve el estado de cuenta de otro (404)", r.estado === 404);
  r = await como(tC, "GET", `/api/clientes/${idCliente}/estado-cuenta`);
  comprobar("Cliente ve su estado de cuenta", r.estado === 200 && r.cuerpo?.datos?.cliente?.id_cliente === idCliente);
  r = await como(tC, "GET", "/api/ventas?limit=100");
  comprobar("Cliente solo ve sus compras", r.estado === 200 && r.cuerpo?.datos?.length > 0 && r.cuerpo.datos.every((v) => v.id_cliente === idCliente));
  r = await como(tC, "GET", "/api/pagos?limit=100");
  comprobar("Cliente solo ve sus pagos", r.estado === 200 && r.cuerpo?.datos?.every((p) => p.id_cliente === idCliente));
  r = await como(tC, "POST", "/api/ventas", { id_cliente: idCliente, items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("Cliente no registra ventas (403)", r.estado === 403);
  r = await como(tC, "POST", "/api/pagos", { id_venta: ventaVendedor?.id_venta, monto: 1000, metodo: "efectivo", referencia: "x" });
  comprobar("Cliente no puede reportar pagos en efectivo (400)", r.estado === 400);
  r = await como(tC, "GET", "/api/pagos/pendientes");
  comprobar("Cliente no ve la cartera del negocio (403)", r.estado === 403);
  r = await como(tC, "GET", "/api/dashboard/resumen");
  comprobar("Cliente no ve el resumen del negocio (403)", r.estado === 403);
  r = await como(tC, "POST", "/api/pedidos", { canal: "app", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("pedido del Cliente sin escoger cómo pagar: 400", r.estado === 400 && !!r.cuerpo?.detalles?.metodo_pago, r.cuerpo);
  r = await como(tC, "POST", "/api/pedidos", { canal: "app", metodo_pago: "tarjeta", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("el Cliente solo escoge Wompi, transferencia o efectivo (400)", r.estado === 400);
  r = await como(tC, "POST", "/api/pedidos", { metodo_pago: "transferencia", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("pedido por transferencia sin comprobante: 400", r.estado === 400 && !!r.cuerpo?.detalles?.comprobante, r.cuerpo);
  r = await como(tC, "POST", "/api/pedidos", {
    id_cliente: otroCliente, canal: "punto_fisico", metodo_pago: "transferencia", referencia_pago: "TRF-PED-1",
    comprobante: { base64: png1x1, tipo_mime: "image/png" },
    items: [{ id_producto: pA.id_producto, cantidad: 1, precio_unitario: 1 }]
  });
  comprobar("pedido del Cliente queda a su nombre, por canal app y con su forma de pago",
    r.estado === 201 && r.cuerpo?.datos?.id_cliente === idCliente && r.cuerpo?.datos?.canal === "app" && r.cuerpo?.datos?.metodo_pago === "transferencia", r.cuerpo);
  const pedidoCliente = r.cuerpo?.datos;
  comprobar("el pedido guarda el comprobante de la transferencia", pedidoCliente?.tiene_comprobante === true);
  comprobar("el Cliente no puede poner su propio precio", num(pedidoCliente?.total) === num(pA.precio), pedidoCliente?.total);
  const imgPed = await fetch(`${BASE}/api/pedidos/${pedidoCliente?.id_pedido}/comprobante`, { headers: { Authorization: `Bearer ${tC}` } });
  comprobar("el Cliente ve el comprobante de su pedido", imgPed.status === 200 && imgPed.headers.get("content-type") === "image/png");
  r = await como(tC, "POST", `/api/pedidos/${pedidoCliente?.id_pedido}/convertir`, {});
  comprobar("Cliente no convierte su pedido en venta (403)", r.estado === 403);
  r = await como(tC, "POST", `/api/pedidos/${pedidoCliente?.id_pedido}/cancelar`, { motivo: "Ya no lo quiero" });
  comprobar("Cliente cancela su propio pedido", r.estado === 200);
  r = await como(tC, "GET", "/api/pedidos?limit=100");
  comprobar("Cliente solo ve sus pedidos", r.estado === 200 && r.cuerpo?.datos?.every((p) => p.id_cliente === idCliente));
  r = await como(tC, "GET", "/api/productos?limit=5");
  comprobar("Cliente ve el catálogo", r.estado === 200 && r.cuerpo?.datos?.length > 0);

  // --- El cliente paga por Wompi: su pedido, al confirmarse, hereda el método
  r = await como(tC, "POST", "/api/pedidos", { metodo_pago: "wompi", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  const pedidoWompi = r.cuerpo?.datos;
  r = await pedir("POST", `/api/pedidos/${pedidoWompi?.id_pedido}/convertir`, {});
  comprobar("al convertir el pedido, la venta queda con el método que eligió el cliente", r.estado === 201 && r.cuerpo?.datos?.metodo_pago === "wompi", r.cuerpo);
  if (r.cuerpo?.datos) await pedir("POST", `/api/ventas/${r.cuerpo.datos.id_venta}/anular`, { motivo: "Limpieza de pruebas" });
  r = await como(tC, "POST", "/api/pedidos", {
    metodo_pago: "transferencia", comprobante: { base64: png1x1, tipo_mime: "image/png" },
    items: [{ id_producto: pA.id_producto, cantidad: 1 }]
  });
  r = await pedir("POST", `/api/pedidos/${r.cuerpo?.datos?.id_pedido}/convertir`, {});
  const ventaTrf = r.cuerpo?.datos;
  const pagoTrf = ventaTrf?.pagos?.find((p) => p.estado === "pendiente");
  comprobar("al convertirlo, el comprobante del pedido queda como pago por aprobar",
    !!pagoTrf && pagoTrf.tiene_comprobante === true && num(pagoTrf.monto) === num(ventaTrf.total) && num(ventaTrf.saldo) === num(ventaTrf.total), ventaTrf?.pagos);
  r = await pedir("POST", `/api/pagos/${pagoTrf?.id_pago}/aprobar`, {});
  comprobar("al aprobarlo, esa venta queda pagada", r.estado === 200 && r.cuerpo?.datos?.venta?.saldo === 0, r.cuerpo);
  if (ventaTrf) await pedir("POST", `/api/ventas/${ventaTrf.id_venta}/anular`, { motivo: "Limpieza de pruebas" });
  r = await como(tC, "GET", "/api/pagos/datos-pago");
  comprobar("el Cliente consulta los datos para pagar", r.estado === 200 && "transferencia" in (r.cuerpo?.datos ?? {}) && !!r.cuerpo?.datos?.punto_fisico);

  // ------------------------------------------------------------------
  titulo("Pagos reportados por el cliente (con comprobante)");
  const idVV = ventaVendedor?.id_venta;
  const saldoDe = async (id) => num((await pedir("GET", `/api/ventas/${id}`)).cuerpo?.datos?.saldo);
  const saldoInicial = await saldoDe(idVV);
  r = await como(tC, "POST", "/api/pagos", { id_venta: idVV, monto: 30000, metodo: "transferencia" });
  comprobar("reportar sin comprobante ni referencia: 400", r.estado === 400 && !!r.cuerpo?.detalles?.comprobante);
  r = await como(tC, "POST", "/api/pagos", {
    id_venta: idVV, monto: 30000, metodo: "transferencia", referencia: "TRF-001",
    comprobante: { base64: png1x1, tipo_mime: "image/png" }
  });
  comprobar("el Cliente reporta un pago con comprobante: 201 pendiente", r.estado === 201 && r.cuerpo?.datos?.pago?.estado === "pendiente", r.cuerpo);
  const reporte1 = r.cuerpo?.datos?.pago;
  comprobar("un pago reportado NO baja el saldo todavía", (await saldoDe(idVV)) === saldoInicial);
  r = await como(tC, "POST", "/api/pagos", { id_venta: idVV, monto: saldoInicial - 30000 + 1, metodo: "nequi", referencia: "NQ" });
  comprobar("no se reporta más que el saldo menos lo ya reportado (409)", r.estado === 409, r.cuerpo);
  const { cuerpo: ajenas } = await pedir("GET", "/api/ventas?estado_pago=con_saldo&limit=100");
  const ajena = ajenas?.datos?.find((v) => v.id_cliente !== idCliente);
  if (ajena) {
    r = await como(tC, "POST", "/api/pagos", { id_venta: ajena.id_venta, monto: 1000, metodo: "nequi", referencia: "NQ" });
    comprobar("el Cliente no reporta pagos a ventas de otro cliente (404)", r.estado === 404, r.cuerpo);
  }

  const img = await fetch(`${BASE}/api/pagos/${reporte1?.id_pago}/comprobante`, { headers: { Authorization: `Bearer ${tC}` } });
  comprobar("el Cliente ve su comprobante (image/png)", img.status === 200 && img.headers.get("content-type") === "image/png");
  const imgSin = await fetch(`${BASE}/api/pagos/${reporte1?.id_pago}/comprobante`);
  comprobar("el comprobante no es público (401 sin sesión)", imgSin.status === 401);
  r = await como(tC, "PUT", `/api/pagos/${reporte1?.id_pago}/comprobante`, { base64: "AAAA", tipo_mime: "image/gif" });
  comprobar("comprobante que no es imagen: 400", r.estado === 400);

  r = await pedir("GET", "/api/dashboard/resumen");
  comprobar("el Administrador ve cuántos pagos hay por aprobar", r.cuerpo?.datos?.pagos_por_aprobar >= 1, r.cuerpo?.datos);
  r = await pedir("GET", "/api/pagos?estado=pendiente&limit=100");
  comprobar("filtro de pagos por aprobar", r.cuerpo?.datos?.some((p) => p.id_pago === reporte1?.id_pago && p.tiene_comprobante === true));
  r = await como(tV, "POST", `/api/pagos/${reporte1?.id_pago}/aprobar`, {});
  comprobar("el Vendedor no aprueba pagos (403)", r.estado === 403);
  r = await pedir("POST", `/api/pagos/${reporte1?.id_pago}/anular`, { motivo: "prueba" });
  comprobar("un reporte no se anula: se aprueba o se rechaza (409)", r.estado === 409);
  r = await pedir("POST", `/api/pagos/${reporte1?.id_pago}/aprobar`, {});
  comprobar("el Administrador aprueba el pago", r.estado === 200 && r.cuerpo?.datos?.pago?.estado === "aplicado", r.cuerpo);
  comprobar("al aprobarlo, el saldo baja", (await saldoDe(idVV)) === saldoInicial - 30000);
  r = await pedir("POST", `/api/pagos/${reporte1?.id_pago}/aprobar`, {});
  comprobar("aprobar dos veces: 409", r.estado === 409);

  r = await como(tC, "POST", "/api/pagos", { id_venta: idVV, monto: 20000, metodo: "nequi", referencia: "NQ-777" });
  const reporte2 = r.cuerpo?.datos?.pago;
  r = await pedir("POST", `/api/pagos/${reporte2?.id_pago}/rechazar`, {});
  comprobar("rechazar sin motivo: 400", r.estado === 400);
  r = await pedir("POST", `/api/pagos/${reporte2?.id_pago}/rechazar`, { motivo: "No llegó la transferencia" });
  comprobar("el Administrador rechaza un pago", r.estado === 200 && r.cuerpo?.datos?.pago?.estado === "rechazado");
  comprobar("un pago rechazado no cuenta en el saldo", (await saldoDe(idVV)) === saldoInicial - 30000);
  r = await como(tC, "PUT", `/api/pagos/${reporte2?.id_pago}/comprobante`, { base64: png1x1, tipo_mime: "image/png" });
  comprobar("ya revisado, el Cliente no cambia el comprobante (409)", r.estado === 409);
  r = await pedir("PUT", `/api/pagos/${abonoVendedor?.id_pago}/comprobante`, { base64: png1x1, tipo_mime: "image/png" });
  comprobar("el equipo adjunta comprobante a un abono", r.estado === 200, r.cuerpo);

  // --- Resguardos de usuarios
  r = await pedir("GET", "/api/usuarios?rol=Administrador&status=active&limit=100");
  const admins = r.cuerpo?.datos ?? [];
  if (admins.length === 1) {
    r = await pedir("PUT", `/api/usuarios/${admins[0].id_usuario}`, { estado: false });
    comprobar("no se puede desactivar al único administrador (409)", r.estado === 409);
  }
  r = await pedir("PUT", `/api/usuarios/${idVendedor}/password`, { nueva: "OtraClave99" });
  comprobar("el Administrador restablece una contraseña", r.estado === 200);
  r = await pedir("POST", "/api/auth/login", { correo: `vendedor${marca}@essence.com`, password: "OtraClave99" });
  comprobar("la contraseña nueva funciona", r.estado === 200);
  for (const id of [idVendedor, idUsuarioCliente]) await pedir("PUT", `/api/usuarios/${id}`, { estado: false });
  r = await pedir("POST", "/api/auth/login", { correo: `vendedor${marca}@essence.com`, password: "OtraClave99" });
  comprobar("un usuario desactivado ya no entra (403)", r.estado === 403);
  if (ventaVendedor) await pedir("POST", `/api/ventas/${ventaVendedor.id_venta}/anular`, { motivo: "Limpieza de pruebas" });
  token = tokenAdmin;

  // ------------------------------------------------------------------
  titulo("Registro con aprobación y recuperación de contraseña");
  const correoReg = `registro${marca}@correo.com`;
  const registroBase = {
    nombre: `Registro Prueba ${marca}`, tipo_documento: "CC", documento: String(marca).slice(-9), telefono: "3105556677",
    ciudad: "La Pintada", direccion: "Calle 5 # 4-3", correo: correoReg, password: "Registro123"
  };
  r = await pedir("POST", "/api/auth/registro", { ...registroBase, telefono: "310555", tipo_documento: "XX", acepta_datos: true }, { sinToken: true });
  comprobar("registro con celular corto y tipo de documento inválido: 400",
    r.estado === 400 && !!r.cuerpo?.detalles?.telefono && !!r.cuerpo?.detalles?.tipo_documento, r.cuerpo);
  r = await pedir("POST", "/api/auth/registro", registroBase, { sinToken: true });
  comprobar("registro sin aceptar tratamiento de datos: 400", r.estado === 400);
  r = await pedir("POST", "/api/auth/registro", { ...registroBase, acepta_datos: true }, { sinToken: true });
  comprobar("registro correcto: 201", r.estado === 201, r.cuerpo);
  r = await pedir("POST", "/api/auth/registro", { ...registroBase, acepta_datos: true }, { sinToken: true });
  comprobar("registrarse dos veces con el mismo correo: 409", r.estado === 409);
  r = await pedir("POST", "/api/auth/login", { correo: correoReg, password: "Registro123" }, { sinToken: true });
  comprobar("una cuenta pendiente no puede entrar (403)", r.estado === 403 && /pendiente/i.test(r.cuerpo?.error ?? ""), r.cuerpo);

  r = await pedir("GET", "/api/usuarios?aprobacion=pendiente&limit=100");
  const solicitud = r.cuerpo?.datos?.find((u) => u.correo === correoReg);
  comprobar("la solicitud aparece en Pendientes del Administrador", !!solicitud && solicitud.estado === false);
  r = await pedir("GET", "/api/dashboard/resumen");
  comprobar("el resumen del Administrador cuenta las solicitudes", r.cuerpo?.datos?.solicitudes_pendientes >= 1);
  r = await pedir("PUT", `/api/usuarios/${solicitud?.id_usuario}`, { estado: true });
  comprobar("no se activa una solicitud sin aprobarla (409)", r.estado === 409);
  r = await pedir("POST", `/api/usuarios/${solicitud?.id_usuario}/aprobar`, { rol: "Cliente" });
  comprobar("aprobar la solicitud como Cliente", r.estado === 200 && r.cuerpo?.datos?.aprobacion === "aprobado", r.cuerpo);
  r = await pedir("POST", "/api/auth/login", { correo: correoReg, password: "Registro123" }, { sinToken: true });
  comprobar("la cuenta aprobada ya entra y queda como Cliente", r.estado === 200 && r.cuerpo?.datos?.usuario?.rol === "Cliente");
  const idFichaReg = r.cuerpo?.datos?.usuario?.id_cliente;
  r = await pedir("GET", `/api/clientes/${idFichaReg}`);
  comprobar("su ficha de cliente quedó activa y con sus datos", r.cuerpo?.datos?.estado === true && r.cuerpo?.datos?.tipo_documento === "CC" && r.cuerpo?.datos?.ciudad === "La Pintada");

  const correoRech = `rechazo${marca}@correo.com`;
  await pedir("POST", "/api/auth/registro", { ...registroBase, correo: correoRech, acepta_datos: true }, { sinToken: true });
  r = await pedir("GET", `/api/usuarios?aprobacion=pendiente&search=${encodeURIComponent(correoRech)}`);
  const idRech = r.cuerpo?.datos?.[0]?.id_usuario;
  r = await pedir("POST", `/api/usuarios/${idRech}/rechazar`, {});
  comprobar("rechazar sin motivo: 400", r.estado === 400);
  r = await pedir("POST", `/api/usuarios/${idRech}/rechazar`, { motivo: "No es cliente de la tienda" });
  comprobar("rechazar una solicitud", r.estado === 200 && r.cuerpo?.datos?.aprobacion === "rechazado");
  r = await pedir("POST", "/api/auth/login", { correo: correoRech, password: "Registro123" }, { sinToken: true });
  comprobar("una cuenta rechazada no entra (403)", r.estado === 403);

  r = await pedir("POST", "/api/auth/olvide", { correo: `nadie${marca}@correo.com` }, { sinToken: true });
  const olvidoDisponible = r.estado === 200;
  comprobar("olvidé contraseña con un correo inexistente no revela nada", r.estado === 200 || r.estado === 503, r.cuerpo);

  const bandeja = await pedir("GET", `/api/auth/prueba/ultimo-correo?para=${correoReg}`, null, { sinToken: true });
  if (olvidoDisponible && bandeja.estado === 200) {
    r = await pedir("POST", "/api/auth/olvide", { correo: correoReg }, { sinToken: true });
    comprobar("pedir código de recuperación: 200", r.estado === 200, r.cuerpo);
    r = await pedir("POST", "/api/auth/olvide", { correo: correoReg }, { sinToken: true });
    comprobar("pedir otro código de inmediato: 429", r.estado === 429);
    const ultimo = (await pedir("GET", `/api/auth/prueba/ultimo-correo?para=${correoReg}`, null, { sinToken: true })).cuerpo?.datos;
    const codigo = ultimo?.texto?.match(/\b(\d{6})\b/)?.[1];
    comprobar("el correo trae un código de 6 dígitos", /^\d{6}$/.test(codigo ?? ""), ultimo);
    const malo = codigo === "000000" ? "111111" : "000000";
    r = await pedir("POST", "/api/auth/restablecer", { correo: correoReg, codigo: malo, nueva: "NuevaClave123" }, { sinToken: true });
    comprobar("código incorrecto: 400 y dice cuántos intentos quedan", r.estado === 400 && /quedan 4/.test(r.cuerpo?.error ?? ""), r.cuerpo);
    r = await pedir("POST", "/api/auth/restablecer", { correo: correoReg, codigo, nueva: "NuevaClave123" }, { sinToken: true });
    comprobar("código correcto cambia la contraseña", r.estado === 200, r.cuerpo);
    r = await pedir("POST", "/api/auth/restablecer", { correo: correoReg, codigo, nueva: "OtraMas123" }, { sinToken: true });
    comprobar("el mismo código no sirve dos veces", r.estado === 400);
    r = await pedir("POST", "/api/auth/login", { correo: correoReg, password: "NuevaClave123" }, { sinToken: true });
    comprobar("entra con la contraseña nueva", r.estado === 200);
  } else {
    console.log("  (flujo completo del código omitido: solo corre en local con CORREO_MODO=prueba)");
  }
  await pedir("PUT", `/api/usuarios/${solicitud?.id_usuario}`, { estado: false });

  // ------------------------------------------------------------------
  titulo("Wompi");
  r = await pedir("GET", "/api/pagos/wompi");
  comprobar("estado de configuración de Wompi", r.estado === 200 && typeof r.cuerpo?.datos?.links === "boolean");
  r = await pedir("POST", "/api/webhooks/wompi", { event: "transaction.updated", data: { transaction: { id: "x", status: "APPROVED", amount_in_cents: 1 } }, signature: { properties: ["transaction.id"], checksum: "FALSA" }, timestamp: 1 }, { sinToken: true });
  comprobar("webhook con firma falsa: 401", r.estado === 401);

  if (SIMULAR_WOMPI) {
    const { servidor, transacciones } = await levantarWompiFalso();
    try {
      r = await pedir("POST", "/api/pagos/wompi/links", { id_venta: ventaCredito.id_venta, monto: 99999999 });
      comprobar("link por más del saldo: 400", r.estado === 400);
      r = await pedir("POST", "/api/pagos/wompi/links", { id_venta: ventaCredito.id_venta, monto: 20000 });
      comprobar("crear link de pago: 201 con url de checkout", r.estado === 201 && r.cuerpo?.datos?.url?.startsWith("https://checkout.wompi.co/l/"), r.cuerpo);
      const link = r.cuerpo?.datos;

      const tx = { id: `TX-${marca}`, status: "APPROVED", amount_in_cents: 2000000, payment_link_id: link.id_link, payment_method_type: "CARD", reference: "ref" };
      r = await pedir("POST", "/api/webhooks/wompi", eventoFirmado(tx), { sinToken: true });
      comprobar("webhook firmado registra el abono", r.estado === 200 && r.cuerpo?.resultado === "registrado", r.cuerpo);
      r = await pedir("POST", "/api/webhooks/wompi", eventoFirmado(tx), { sinToken: true });
      comprobar("el mismo evento dos veces no duplica el abono", r.cuerpo?.resultado === "ya_registrado", r.cuerpo);
      r = await pedir("GET", `/api/ventas/${ventaCredito.id_venta}`);
      comprobar("la venta baja a saldo 25000 y el link queda pagado", num(r.cuerpo?.datos?.saldo) === 25000 && r.cuerpo?.datos?.wompi_links?.[0]?.estado === "pagado", r.cuerpo?.datos?.saldo);
      comprobar("el pago queda con método wompi", r.cuerpo?.datos?.pagos?.some((p) => p.metodo === "wompi"));

      // Plan B: verificar a mano cuando el webhook no llegó.
      r = await pedir("POST", "/api/pagos/wompi/links", { id_venta: ventaCredito.id_venta });
      const link2 = r.cuerpo?.datos;
      comprobar("link sin monto usa todo el saldo (25000)", num(link2?.monto) === 25000, link2);
      transacciones.set(`TX2-${marca}`, { id: `TX2-${marca}`, status: "DECLINED", amount_in_cents: 2500000, payment_link_id: link2.id_link });
      r = await pedir("POST", "/api/pagos/wompi/verificar", { id_transaccion: `TX2-${marca}` });
      comprobar("verificar una transacción rechazada no abona (409)", r.estado === 409 && r.cuerpo?.datos?.resultado === "no_aprobada", r.cuerpo);
      transacciones.set(`TX3-${marca}`, { id: `TX3-${marca}`, status: "APPROVED", amount_in_cents: 2500000, payment_link_id: link2.id_link, payment_method_type: "NEQUI" });
      r = await pedir("POST", "/api/pagos/wompi/verificar", { id_transaccion: `TX3-${marca}` });
      comprobar("verificar una transacción aprobada la abona", r.estado === 200 && r.cuerpo?.datos?.resultado === "registrado", r.cuerpo);
      r = await pedir("GET", `/api/ventas/${ventaCredito.id_venta}`);
      comprobar("la venta a crédito queda pagada por Wompi", r.cuerpo?.datos?.estado_pago === "pagada");
    } finally {
      servidor.close();
    }
  } else {
    console.log("  (pruebas de links omitidas: corre con WOMPI_SIMULADO=1 para simular Wompi)");
  }

  // ------------------------------------------------------------------
  titulo("Dashboard");
  r = await pedir("GET", "/api/dashboard/resumen");
  comprobar("resumen responde 200 con ventas de hoy", r.estado === 200 && num(r.cuerpo?.datos?.ventas_hoy) > 0, r.cuerpo?.datos);

  // ------------------------------------------------------------------
  titulo("Limpieza");
  // Se anulan las ventas que quedan para no dejar cartera de prueba.
  for (const v of [ventaCredito, ventaUltima]) {
    if (v) await pedir("POST", `/api/ventas/${v.id_venta}/anular`, { motivo: "Limpieza de pruebas" });
  }
  r = await pedir("PUT", `/api/clientes/${idCliente}`, { estado: false });
  comprobar("cliente de prueba desactivado", r.estado === 200);
  r = await pedir("POST", "/api/ventas", { id_cliente: idCliente, metodo_pago: "efectivo", items: [{ id_producto: pA.id_producto, cantidad: 1 }] });
  comprobar("no se le vende a un cliente inactivo (409)", r.estado === 409);

  console.log("\n====================================================");
  console.log(`  Pruebas pasadas: ${pasadas}`);
  console.log(`  Pruebas falladas: ${falladas}`);
  console.log("====================================================");
  if (falladas) {
    console.log("\nFallaron:");
    fallos.forEach((f) => console.log(`  - ${f}`));
    process.exitCode = 1;
  } else {
    console.log("\nTodo en orden.\n");
  }
}

main().catch((error) => {
  console.error(`\nLa prueba se detuvo: ${error.message}`);
  process.exitCode = 1;
});
