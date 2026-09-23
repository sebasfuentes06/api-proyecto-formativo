# API Proyecto Formativo — Essence Don Aire

API REST con operaciones **CRUD** sobre cuatro entidades del sistema de gestión
de fragancias Essence Don Aire: categorías, proveedores, clientes y productos.

**Node.js + Express + PostgreSQL**, con SQL parametrizado y sin ORM.

---

## Índice

1. [Puesta en marcha](#puesta-en-marcha)
2. [Estructura del proyecto](#estructura-del-proyecto)
3. [Modelo de datos](#modelo-de-datos)
4. [Endpoints](#endpoints)
5. [Formato de las respuestas](#formato-de-las-respuestas)
6. [Validaciones](#validaciones)
7. [Cómo probarla](#cómo-probarla)
8. [Decisiones técnicas](#decisiones-técnicas)

---

## Puesta en marcha

Requisitos: **Node.js 20 o superior** y **PostgreSQL**.

```bash
# 1. Instalar dependencias
npm install

# 2. Configurar la conexión
copy .env.example .env      # en Windows
#   (en Linux o Mac:  cp .env.example .env)
#   y completar PGPASSWORD con la clave de tu PostgreSQL

# 3. Crear la base de datos (una sola vez, desde psql o pgAdmin)
#    CREATE DATABASE essence_api;

# 4. Crear las tablas y cargar los datos de ejemplo
npm run db:setup

# 5. Levantar la API
npm run dev
```

Queda en <http://localhost:3000>. Para comprobarlo, abre
<http://localhost:3000/api/health>.

### Comandos

| Comando | Qué hace |
|---|---|
| `npm run dev` | Levanta la API y la reinicia al guardar cambios |
| `npm start` | La levanta sin recarga automática |
| `npm run db:setup` | Crea las tablas y carga los datos de ejemplo |
| `npm run db:seed` | Recarga solo los datos, sin tocar las tablas |
| `npm run test:api` | Corre 76 pruebas automáticas contra la API |

---

## Estructura del proyecto

El código está separado por capas. Cada archivo tiene un solo trabajo, y eso
es lo que permite cambiar una cosa sin romper las demás.

```
src/
├── config/env.js          Lee las variables de entorno
├── db/pool.js             Conexión a PostgreSQL
├── models/                SQL. Hablan con la base de datos
├── controllers/           Reciben la petición y arman la respuesta
├── routes/                Qué URL llama a qué controlador
├── middlewares/           Validación y manejo de errores
├── validaciones/          Reglas de cada entidad
├── docs/                  Especificación OpenAPI y página de Swagger UI
├── web/                   Las páginas HTML: portada, panel y estilos compartidos
├── utils/                 Paginación, orden, filtros
├── app.js                 Arma la aplicación Express
└── server.js              La arranca
```

**El recorrido de una petición**, de principio a fin:

```
GET /api/productos/5
      ↓
app.js            aplica CORS, registra la petición, lee el JSON
      ↓
routes/           encuentra la ruta y ejecuta sus middlewares
      ↓
middlewares/      valida que el id sea un número
      ↓
controllers/      pide el producto al modelo
      ↓
models/           ejecuta el SELECT con JOIN
      ↓
controllers/      responde 200 con los datos, o 404 si no existe
```

La regla que sostiene todo: **el controlador no escribe SQL y el modelo no
sabe qué es HTTP.** Si mañana hubiera que cambiar de PostgreSQL a otro motor,
solo se tocan los modelos. Si hubiera que cambiar el formato de las
respuestas, solo se tocan los controladores.

---

## Modelo de datos

Cuatro tablas, tomadas del modelo aprobado del proyecto Essence Don Aire.

```
  categorias                      proveedores
  ─────────────                   ─────────────
  id_categoria (PK)               id_proveedor (PK)
  nombre (único)                  nombre (único)
  descripcion                     contacto, email, telefono
  estado                          ciudad, calificacion
  created_at                      fecha_alta, estado
        │                                │
        │  1                          1  │
        │                                │
        └────────────┐      ┌────────────┘
                   N │      │ N
                  productos
                  ─────────────
                  id_producto (PK)
                  id_categoria (FK)
                  id_proveedor (FK)
                  sku (único)
                  nombre, descripcion
                  precio, stock, stock_minimo
                  estado, fecha_creacion

  clientes
  ─────────────
  id_cliente (PK)
  nombre
  correo (único)
  telefono, direccion, ciudad
  estado, fecha_registro, ultima_compra
```

Un producto pertenece **siempre** a una categoría y a un proveedor: las dos
llaves foráneas son `NOT NULL`. Por eso no se puede borrar una categoría que
tenga productos, y la API lo explica en vez de dejar que falle la base.

**Una diferencia con el modelo completo.** En el proyecto grande los clientes
viven dentro de la tabla `usuarios`, diferenciados por su rol, porque ese
sistema maneja roles y permisos. Esta API no los maneja, así que `clientes` va
como tabla propia con los mismos campos. El modelo de datos no cambia: cambia
dónde se guarda la misma información.

---

## Endpoints

Base: `/api`

### Páginas web

Tres rutas devuelven HTML en vez de JSON. Son la cara visible de la API, para
personas; todo lo demás es para programas.

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/` | Portada: qué es la API, sus recursos y cifras en vivo de la base |
| `GET` | `/panel` | **Panel de gestión**: la API en uso, con CRUD completo |
| `GET` | `/docs` | **Documentación interactiva** (Swagger UI) |

`/panel` es una aplicación de una sola página que consume esta misma API:
barra lateral con módulos, un tablero con indicadores y gráfico, y las cuatro
entidades con búsqueda, filtros, paginación y formularios de creación y
edición.

No tiene datos propios ni estado guardado: cada pantalla que se abre y cada
botón que se pulsa es una llamada HTTP. El indicador de la esquina superior
muestra la última petición con su código, y el tablero guarda el historial.
Eso hace visible, en vivo, la relación entre la interfaz y la API.

### Sistema y documentación

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/api` | Índice de la API en JSON |
| `GET` | `/api/openapi.json` | Especificación OpenAPI 3.0 de toda la API |
| `GET` | `/api/health` | Estado de la API y de la base de datos |

`/api/openapi.json` es esa misma información en el formato estándar OpenAPI.
Sirve para importar toda la colección en Postman o Insomnia de un solo golpe:
*Import → Link* y esa URL.

### Las cuatro entidades

Las cuatro exponen las mismas cinco operaciones:

| Método | Ruta | Descripción | Respuesta |
|---|---|---|---|
| `GET` | `/api/{recurso}` | Listar, con filtros y paginación | `200` |
| `GET` | `/api/{recurso}/:id` | Obtener uno | `200` / `404` |
| `POST` | `/api/{recurso}` | Crear | `201` / `400` / `409` |
| `PUT` | `/api/{recurso}/:id` | Actualizar | `200` / `400` / `404` |
| `DELETE` | `/api/{recurso}/:id` | Eliminar | `200` / `404` / `409` |

Donde `{recurso}` es `categorias`, `proveedores`, `clientes` o `productos`.
Son **20 operaciones** en total.

### Parámetros de los listados

| Parámetro | Vale para | Ejemplo |
|---|---|---|
| `search` | todos | `?search=floral` |
| `status` | todos | `?status=active` · `inactive` · `all` |
| `sortBy` | todos | `?sortBy=nombre` |
| `sortDir` | todos | `?sortDir=desc` |
| `page` | todos | `?page=2` |
| `limit` | todos | `?limit=20` (máximo 100) |
| `ciudad` | proveedores, clientes | `?ciudad=Medellín` |
| `categoria` | productos | `?categoria=1` |
| `proveedor` | productos | `?proveedor=3` |
| `stockBajo` | productos | `?stockBajo=1` |

Se combinan:

```
GET /api/productos?search=rosa&categoria=1&status=active&sortBy=precio&sortDir=desc&page=1&limit=10
```

El filtrado, el orden y la paginación los hace **PostgreSQL**, no JavaScript.
Con ocho productos da igual; con ocho mil es la diferencia entre una respuesta
inmediata y traerse la tabla entera para mostrar diez filas.

---

## Formato de las respuestas

Todas responden con la misma forma, de modo que quien consuma la API no tenga
que adivinar.

**Listado:**

```json
{
  "ok": true,
  "datos": [ { "id_producto": 1, "nombre": "Rosa Eterna" } ],
  "paginacion": { "total": 8, "pagina": 1, "porPagina": 10, "totalPaginas": 1 }
}
```

**Un registro:**

```json
{
  "ok": true,
  "datos": {
    "id_producto": 1,
    "sku": "FLO-ROS-001",
    "nombre": "Rosa Eterna",
    "precio": "185000.00",
    "stock": 42,
    "stock_minimo": 15,
    "id_categoria": 1,
    "categoria": "Floral",
    "id_proveedor": 1,
    "proveedor": "Esencias del Valle S.A.S.",
    "stock_bajo": false
  }
}
```

Fíjate en `categoria` y `proveedor`: la API resuelve el `JOIN` y devuelve los
nombres. Sin eso, el cliente recibiría `id_categoria: 1` y tendría que hacer
otra petición para saber qué es 1.

**Error:**

```json
{
  "ok": false,
  "error": "Revisa los datos enviados.",
  "detalles": {
    "nombre": "El nombre es obligatorio.",
    "precio": "El precio no puede ser menor que 0."
  }
}
```

### Códigos usados

| Código | Cuándo |
|---|---|
| `200` | Operación correcta |
| `201` | Registro creado |
| `400` | Datos inválidos, o un id que no es número |
| `404` | El registro o la ruta no existen |
| `409` | Choca con una regla: valor repetido, o borrado que rompe una relación |
| `500` | Error del servidor |
| `503` | La API está viva pero no alcanza la base de datos |

---

## Validaciones

Se revisan **antes** de tocar la base, para poder responder con un mensaje
claro en lugar de un error de PostgreSQL.

| Entidad | Reglas |
|---|---|
| Categorías | nombre obligatorio, máx. 100; descripción máx. 200; nombre no repetido |
| Proveedores | nombre obligatorio; correo con formato válido; calificación entre 0 y 5 |
| Clientes | nombre y correo obligatorios; correo válido y no repetido; teléfono con formato |
| Productos | SKU, nombre, categoría, proveedor y precio obligatorios; precio y stock ≥ 0; la categoría y el proveedor deben existir |

La base de datos tiene además sus propias restricciones (`NOT NULL`, `CHECK`,
`UNIQUE`, llaves foráneas). Son la segunda línea: aunque alguien escribiera
directo en la base, saltándose la API, esas reglas siguen aplicando.

---

## Cómo probarla

### Pruebas automáticas

```bash
npm run test:api
```

Recorre las 20 operaciones, los casos que deben fallar (datos inválidos, ids
inexistentes, valores repetidos, borrados que romperían una relación), los
filtros y la documentación. Son **76 comprobaciones** y termina con el conteo.

Para probar el despliegue en lugar de tu equipo:

```bash
API_URL=https://tu-api.vercel.app npm run test:api
```

### Desde el navegador

Dos formas, sin instalar nada:

- **`/docs`** — recorre las operaciones una por una: se despliega cada una, se
  edita el cuerpo de la petición y se ejecuta contra el servidor de verdad.
- **`/panel`** — la API usada como la usaría una aplicación real: tablero,
  módulos, formularios, y el registro de peticiones a la vista.

### Pruebas manuales

El archivo `pruebas.http` trae todas las peticiones listas. Se usa con la
extensión **REST Client** de VS Code: se abre el archivo y se le da clic a
*Send Request* encima de cada bloque. También sirve de referencia para armar
las mismas peticiones en Postman o Thunder Client.

---

## Decisiones técnicas

**SQL parametrizado, sin ORM.** Los valores nunca se pegan dentro del texto de
la consulta: van aparte, como `$1`, `$2`. Si alguien escribe
`'; DROP TABLE productos; --` en el buscador, PostgreSQL lo trata como texto a
buscar, no como una orden. Los nombres de columna sí hay que pegarlos —no se
pueden parametrizar—, así que se validan contra una **lista blanca**: cualquier
otra cosa se ignora y se usa la columna por defecto.

**Separación en capas.** Rutas, controladores y modelos son archivos distintos.
Cuesta unos archivos de más y evita el problema de tener el SQL, la validación
y la respuesta HTTP mezclados en la misma función.

**Manejo de errores centralizado.** Un solo middleware traduce los códigos de
PostgreSQL a mensajes entendibles. Sin eso, un correo repetido devolvería
`duplicate key value violates unique constraint "uq_clientes_correo"`.

**Datos calculados, no guardados.** `total_productos` y `stock_bajo` se
calculan en la consulta. Guardarlos en una columna significa que se
desactualizan en cuanto alguien crea o borra un producto.

**Validación propia, sin librerías.** Se puede leer de arriba abajo y no
agrega una dependencia más que explicar.

**Las páginas HTML van incrustadas en el código**, no como archivos en una
carpeta `public/`. En un despliegue serverless Express no sirve archivos
estáticos, así que un `.css` o un `.js` enlazados devolverían 404 y las páginas
se verían sin formato. Por eso los estilos y el JavaScript del cliente viajan
dentro del HTML que genera el servidor.

**El panel no usa ninguna librería.** Es JavaScript a secas contra `fetch`,
con las cuatro entidades descritas como configuración —columnas, campos,
filtros— en vez de cuatro pantallas escritas a mano. Así queda claro que el
trabajo lo hace la API, no un framework, y que agregar una quinta entidad
cuesta unas veinte líneas de descripción.

**Swagger UI desde un CDN, no como dependencia.** No es por ahorrar un
paquete: en un despliegue serverless, Express no sirve archivos estáticos, así
que `swagger-ui-express` cargaría la página sin estilos ni JavaScript. Trayendo
la interfaz del CDN y sirviendo solo la especificación desde la API, funciona
igual en local que desplegada.

**La misma aplicación corre local y desplegada.** `server.js` exporta la app y
solo abre un puerto cuando no está en un entorno serverless. No hay una versión
"de desarrollo" y otra "de producción" que puedan desincronizarse.

Para publicarla en internet, ver **[DESPLIEGUE.md](./DESPLIEGUE.md)**.

---

## App móvil y proceso de ventas

Además del CRUD, la API sirve a la **app Flutter del administrador**
(carpeta [`app_movil/`](app_movil/README.md)), con los cinco subprocesos del
*Proceso Móvil* de la ficha: clientes, catálogo, pedidos, ventas y pagos/abonos.

| Recurso | Qué hace |
|---|---|
| `POST /api/auth/login` | Login del administrador (JWT + bcrypt) |
| `/api/pedidos` | Pedidos temporales; `POST /:id/convertir` los vuelve venta |
| `/api/ventas` | Ventas con número de factura `FV-000001`; descuentan stock con bloqueo de filas; `POST /:id/anular` devuelve el stock |
| `/api/pagos` | Pagos totales y abonos; `GET /pendientes` es el reporte de cartera |
| `/api/pagos/wompi/links` | Link de pago de Wompi; el abono entra por `POST /api/webhooks/wompi` (firma SHA-256) |
| `/api/clientes/:id/historial` y `/estado-cuenta` | Historial de compras y saldo del cliente |
| `/api/productos/:id/imagen` | Foto del producto (se guarda en PostgreSQL) |
| `/api/dashboard/resumen` | Ventas del día y del mes, cartera, pedidos pendientes, stock bajo |
| `/api/usuarios` | Usuarios y roles (Administrador, Vendedor, Cliente); solo Administrador. `POST /:id/aprobar` y `/:id/rechazar` para las solicitudes de registro |
| `POST /api/auth/registro` | Registro desde la app: queda **pendiente** hasta que el Administrador lo apruebe |
| `POST /api/auth/olvide` y `/restablecer` | Recuperar contraseña con un código de 6 dígitos enviado al correo (vence en 15 min, 5 intentos) |

**Roles.** Administrador: todo. Vendedor: clientes, pedidos, ventas y abonos, sin
anular ni editar catálogo o usuarios. Cliente: solo su catálogo, sus pedidos, sus
compras y su saldo (paga en línea con Wompi). Las rutas del CRUD base siguen
abiertas sin token para el panel web; con token se aplican los roles.

Las tablas nuevas están en `database/movil.sql` (se aplica con
`npm run db:movil` sobre una base existente). Pruebas: `npm run test:movil`
(112 comprobaciones del proceso completo y de los roles; con `WOMPI_SIMULADO=1`
también simula Wompi). El paso a paso del despliegue está en `DESPLIEGUE.md`, parte 6.
