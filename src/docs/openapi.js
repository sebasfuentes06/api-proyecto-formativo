/**
 * Especificación OpenAPI 3.0 de la API.
 *
 * OpenAPI es el formato estándar para describir una API REST: qué rutas
 * tiene, qué recibe cada una, qué devuelve y con qué códigos. A partir de
 * este archivo, Swagger UI dibuja sola la página de /docs, y herramientas
 * como Postman o Insomnia pueden importar toda la colección de un golpe.
 *
 * Está escrito a mano, como un objeto de JavaScript, en vez de generarlo con
 * anotaciones en cada ruta: son cuatro entidades con las mismas cinco
 * operaciones, y verlas juntas en un solo archivo se entiende mejor que
 * repartidas en comentarios por todo el proyecto.
 */
import { tagsMovil, pathsMovil, seguridad } from "./openapi-movil.js";

/** Campos que comparten las cuatro entidades. */
const ESTADO = {
  type: "boolean",
  description: "Activo (true) o inactivo (false)",
  example: true
};

/** Parámetros de consulta comunes a todos los listados. */
const PARAMETROS_LISTADO = [
  {
    name: "search",
    in: "query",
    description: "Busca en los campos de texto del recurso",
    schema: { type: "string" },
    example: "floral"
  },
  {
    name: "status",
    in: "query",
    description: "Filtra por estado",
    schema: { type: "string", enum: ["all", "active", "inactive"], default: "all" }
  },
  {
    name: "sortBy",
    in: "query",
    description: "Columna por la que se ordena. Un valor no permitido se ignora y se usa la de por defecto.",
    schema: { type: "string" },
    example: "nombre"
  },
  {
    name: "sortDir",
    in: "query",
    description: "Sentido del orden",
    schema: { type: "string", enum: ["asc", "desc"], default: "asc" }
  },
  {
    name: "page",
    in: "query",
    description: "Número de página, desde 1",
    schema: { type: "integer", minimum: 1, default: 1 }
  },
  {
    name: "limit",
    in: "query",
    description: "Registros por página. Se recorta a 100 como máximo.",
    schema: { type: "integer", minimum: 1, maximum: 100, default: 10 }
  }
];

const PARAMETRO_ID = {
  name: "id",
  in: "path",
  required: true,
  description: "Identificador del registro",
  schema: { type: "integer", minimum: 1 },
  example: 1
};

/** Respuestas de error que puede devolver cualquier operación. */
const RESPUESTA_400 = {
  description: "Datos inválidos. El cuerpo trae `detalles` con el error de cada campo.",
  content: {
    "application/json": {
      schema: { $ref: "#/components/schemas/ErrorValidacion" },
      example: {
        ok: false,
        error: "Revisa los datos enviados.",
        detalles: {
          nombre: "El nombre es obligatorio.",
          precio: "El precio no puede ser menor que 0."
        }
      }
    }
  }
};

const RESPUESTA_404 = {
  description: "No existe un registro con ese id",
  content: {
    "application/json": {
      schema: { $ref: "#/components/schemas/Error" },
      example: { ok: false, error: "No existe un producto con ese id." }
    }
  }
};

const RESPUESTA_409 = {
  description: "Choca con una regla de negocio: valor repetido, o borrado que rompería una relación",
  content: {
    "application/json": {
      schema: { $ref: "#/components/schemas/Error" },
      example: {
        ok: false,
        error: "No se puede eliminar: la categoría tiene 3 producto(s) asociado(s). Cámbialos de categoría o desactívala en lugar de borrarla."
      }
    }
  }
};

/**
 * Arma las cinco operaciones de un recurso.
 *
 * Las cuatro entidades exponen exactamente la misma forma, así que se
 * describe una vez y se llama con los datos de cada una. Si se escribiera a
 * mano cuatro veces, tarde o temprano una quedaría desactualizada.
 */
function recurso({ nombre, ruta, etiqueta, esquema, esquemaEntrada, ejemplo, ejemploCrear, parametrosExtra = [] }) {
  return {
    [`/api/${ruta}`]: {
      get: {
        tags: [etiqueta],
        summary: `Listar ${nombre}`,
        description:
          "Devuelve una página de resultados. El filtrado, el orden y la paginación los resuelve PostgreSQL.",
        parameters: [...PARAMETROS_LISTADO, ...parametrosExtra],
        responses: {
          200: {
            description: "Listado paginado",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    ok: { type: "boolean", example: true },
                    datos: { type: "array", items: { $ref: `#/components/schemas/${esquema}` } },
                    paginacion: { $ref: "#/components/schemas/Paginacion" }
                  }
                }
              }
            }
          }
        }
      },
      post: {
        tags: [etiqueta],
        summary: `Crear ${nombre.replace(/s$/, "")}`,
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: `#/components/schemas/${esquemaEntrada}` },
              example: ejemploCrear
            }
          }
        },
        responses: {
          201: {
            description: "Creado. Devuelve el registro con el id que asignó la base de datos.",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    ok: { type: "boolean", example: true },
                    mensaje: { type: "string" },
                    datos: { $ref: `#/components/schemas/${esquema}` }
                  }
                },
                example: { ok: true, mensaje: "Creado.", datos: ejemplo }
              }
            }
          },
          400: RESPUESTA_400,
          409: RESPUESTA_409
        }
      }
    },
    [`/api/${ruta}/{id}`]: {
      get: {
        tags: [etiqueta],
        summary: `Obtener ${nombre.replace(/s$/, "")} por id`,
        parameters: [PARAMETRO_ID],
        responses: {
          200: {
            description: "El registro solicitado",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    ok: { type: "boolean", example: true },
                    datos: { $ref: `#/components/schemas/${esquema}` }
                  }
                },
                example: { ok: true, datos: ejemplo }
              }
            }
          },
          400: {
            description: "El id no es un número entero positivo",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/Error" },
                example: { ok: false, error: "El id debe ser un número entero positivo." }
              }
            }
          },
          404: RESPUESTA_404
        }
      },
      put: {
        tags: [etiqueta],
        summary: `Actualizar ${nombre.replace(/s$/, "")}`,
        description:
          "Los campos que no se envíen conservan su valor actual, así que sirve tanto para una edición completa como para cambiar un solo campo.",
        parameters: [PARAMETRO_ID],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: `#/components/schemas/${esquemaEntrada}` },
              example: ejemploCrear
            }
          }
        },
        responses: {
          200: {
            description: "Actualizado",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    ok: { type: "boolean", example: true },
                    mensaje: { type: "string" },
                    datos: { $ref: `#/components/schemas/${esquema}` }
                  }
                }
              }
            }
          },
          400: RESPUESTA_400,
          404: RESPUESTA_404,
          409: RESPUESTA_409
        }
      },
      delete: {
        tags: [etiqueta],
        summary: `Eliminar ${nombre.replace(/s$/, "")}`,
        parameters: [PARAMETRO_ID],
        responses: {
          200: {
            description: "Eliminado. Devuelve el registro que se borró.",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    ok: { type: "boolean", example: true },
                    mensaje: { type: "string" },
                    datos: { $ref: `#/components/schemas/${esquema}` }
                  }
                }
              }
            }
          },
          404: RESPUESTA_404,
          409: RESPUESTA_409
        }
      }
    }
  };
}

const ejemploCategoria = {
  id_categoria: 1,
  nombre: "Floral",
  descripcion: "Fragancias con notas de flores: rosa, jazmín, peonía",
  estado: true,
  created_at: "2026-09-15T01:07:10.853Z",
  total_productos: 2
};

const ejemploProveedor = {
  id_proveedor: 1,
  nombre: "Esencias del Valle S.A.S.",
  contacto: "Andrea Gómez",
  email: "contacto@esenciasvalle.com",
  telefono: "+57 604 444 1122",
  ciudad: "Medellín",
  calificacion: "4.6",
  cantidad_resenas: 38,
  fecha_alta: "2026-09-15",
  estado: true,
  total_productos: 3
};

const ejemploCliente = {
  id_cliente: 1,
  nombre: "Laura Restrepo Vélez",
  correo: "laura.restrepo@correo.com",
  telefono: "+57 300 111 2233",
  direccion: "Calle 10 #43-20",
  ciudad: "Medellín",
  estado: true,
  fecha_registro: "2026-09-15T01:07:10.853Z",
  ultima_compra: null
};

const ejemploProducto = {
  id_producto: 1,
  sku: "FLO-ROS-001",
  nombre: "Rosa Eterna",
  descripcion: "Eau de parfum floral con rosa búlgara y peonía",
  precio: "185000.00",
  stock: 42,
  stock_minimo: 15,
  estado: true,
  fecha_creacion: "2026-09-15T01:07:10.853Z",
  id_categoria: 1,
  categoria: "Floral",
  id_proveedor: 1,
  proveedor: "Esencias del Valle S.A.S.",
  stock_bajo: false
};

const LOCAL = "http://localhost:3000";

/** Se construye como función para que la URL del servidor salga de la petición. */
function construirEspecificacion({ url } = {}) {
  return {
    openapi: "3.0.3",
    info: {
      title: "API Proyecto Formativo — Essence Don Aire",
      version: "1.0.0",
      description: [
        "API REST con operaciones **CRUD** sobre cuatro entidades del sistema de gestión",
        "de fragancias Essence Don Aire: categorías, proveedores, clientes y productos,",
        "y el **proceso de ventas de la app móvil**: pedidos, ventas con factura,",
        "pagos y abonos (incluido Wompi) y estado de cuenta.",
        "",
        "Los endpoints con candado piden sesión: haz login en `POST /api/auth/login`,",
        "copia el token y pégalo en **Authorize**.",
        "",
        "**Roles:** Administrador (todo), Vendedor (clientes, pedidos, ventas y abonos; no anula",
        "ni edita catálogo ni usuarios) y Cliente (solo su catálogo, sus pedidos, sus compras y su saldo).",
        "",
        "Construida con **Node.js + Express + PostgreSQL**, con SQL parametrizado y sin ORM.",
        "",
        "### Cómo probar desde aquí",
        "",
        "Despliega cualquier operación, dale a **Try it out**, ajusta los datos y",
        "**Execute**. La petición sale de verdad contra esta API y la respuesta es real.",
        "",
        "> Las operaciones de escritura modifican datos de verdad. Es una base de",
        "> pruebas, así que no hay problema, pero conviene saberlo."
      ].join("\n"),
      contact: {
        name: "Sebastián Fuentes Hernández — SENA, Análisis y Desarrollo de Software"
      }
    },
    // Primero el servidor desde el que se está sirviendo esta página, para que
    // "Try it out" apunte solo al sitio correcto. El local se agrega aparte,
    // salvo que ya sea el mismo y quedaría repetido en el desplegable.
    servers: [
      ...(url ? [{ url, description: "Esta API" }] : []),
      ...(url === LOCAL ? [] : [{ url: LOCAL, description: "Entorno local" }])
    ],
    tags: [
      { name: "Sistema", description: "Estado del servicio" },
      { name: "Categorías", description: "Tipos de fragancia. Un producto pertenece a una categoría." },
      { name: "Proveedores", description: "Empresas que surten los productos." },
      { name: "Clientes", description: "Personas registradas en la tienda." },
      { name: "Productos", description: "Las fragancias. Dependen de una categoría y un proveedor." },
      ...tagsMovil
    ],
    paths: {
      "/api/health": {
        get: {
          tags: ["Sistema"],
          summary: "Estado de la API y de la base de datos",
          description:
            "La primera URL que hay que abrir cuando algo no funciona: dice si el problema está en la API o en la conexión a PostgreSQL.",
          responses: {
            200: {
              description: "Todo en orden",
              content: {
                "application/json": {
                  example: {
                    ok: true,
                    api: "en línea",
                    baseDeDatos: "conectada",
                    tiempoRespuestaMs: 22
                  }
                }
              }
            },
            503: {
              description: "La API responde pero no alcanza la base de datos",
              content: {
                "application/json": {
                  example: {
                    ok: false,
                    api: "en línea",
                    baseDeDatos: "sin conexión",
                    error: "connect ECONNREFUSED 127.0.0.1:5432"
                  }
                }
              }
            }
          }
        }
      },
      ...recurso({
        nombre: "categorías",
        ruta: "categorias",
        etiqueta: "Categorías",
        esquema: "Categoria",
        esquemaEntrada: "CategoriaEntrada",
        ejemplo: ejemploCategoria,
        ejemploCrear: {
          nombre: "Gourmand",
          descripcion: "Notas dulces: caramelo, chocolate, café",
          estado: true
        }
      }),
      ...recurso({
        nombre: "proveedores",
        ruta: "proveedores",
        etiqueta: "Proveedores",
        esquema: "Proveedor",
        esquemaEntrada: "ProveedorEntrada",
        ejemplo: ejemploProveedor,
        ejemploCrear: {
          nombre: "Fragancias del Norte S.A.S.",
          contacto: "Diana Álvarez",
          email: "ventas@fragnorte.com",
          telefono: "+57 605 111 2233",
          ciudad: "Santa Marta",
          calificacion: 4.3
        },
        parametrosExtra: [
          {
            name: "ciudad",
            in: "query",
            description: "Filtra por ciudad exacta",
            schema: { type: "string" },
            example: "Medellín"
          }
        ]
      }),
      ...recurso({
        nombre: "clientes",
        ruta: "clientes",
        etiqueta: "Clientes",
        esquema: "Cliente",
        esquemaEntrada: "ClienteEntrada",
        ejemplo: ejemploCliente,
        ejemploCrear: {
          nombre: "Camila Arango Pérez",
          correo: "camila.arango@correo.com",
          telefono: "+57 305 666 7788",
          direccion: "Carrera 43A #18-20",
          ciudad: "Medellín"
        },
        parametrosExtra: [
          {
            name: "ciudad",
            in: "query",
            description: "Filtra por ciudad exacta",
            schema: { type: "string" },
            example: "Medellín"
          }
        ]
      }),
      ...recurso({
        nombre: "productos",
        ruta: "productos",
        etiqueta: "Productos",
        esquema: "Producto",
        esquemaEntrada: "ProductoEntrada",
        ejemplo: ejemploProducto,
        ejemploCrear: {
          sku: "GOU-CAR-009",
          nombre: "Caramelo Salado",
          descripcion: "Gourmand dulce con caramelo y sal marina",
          id_categoria: 1,
          id_proveedor: 1,
          precio: 175000,
          stock: 20,
          stock_minimo: 8,
          estado: true
        },
        parametrosExtra: [
          {
            name: "categoria",
            in: "query",
            description: "Filtra por id de categoría",
            schema: { type: "integer" },
            example: 1
          },
          {
            name: "proveedor",
            in: "query",
            description: "Filtra por id de proveedor",
            schema: { type: "integer" },
            example: 1
          },
          {
            name: "stockBajo",
            in: "query",
            description: "Con valor 1, devuelve solo los productos con stock igual o menor al mínimo",
            schema: { type: "string", enum: ["1"] }
          }
        ]
      }),
      ...pathsMovil
    },
    components: {
      securitySchemes: seguridad,
      schemas: {
        Paginacion: {
          type: "object",
          properties: {
            total: { type: "integer", example: 8, description: "Registros que cumplen el filtro" },
            pagina: { type: "integer", example: 1 },
            porPagina: { type: "integer", example: 10 },
            totalPaginas: { type: "integer", example: 1 }
          }
        },
        Error: {
          type: "object",
          properties: {
            ok: { type: "boolean", example: false },
            error: { type: "string" }
          }
        },
        ErrorValidacion: {
          type: "object",
          properties: {
            ok: { type: "boolean", example: false },
            error: { type: "string", example: "Revisa los datos enviados." },
            detalles: {
              type: "object",
              additionalProperties: { type: "string" },
              description: "Un mensaje por cada campo que falló"
            }
          }
        },

        Categoria: {
          type: "object",
          properties: {
            id_categoria: { type: "integer", example: 1 },
            nombre: { type: "string", maxLength: 100, example: "Floral" },
            descripcion: { type: "string", maxLength: 200, nullable: true },
            estado: ESTADO,
            created_at: { type: "string", format: "date-time" },
            total_productos: {
              type: "integer",
              description: "Calculado en la consulta, no guardado en la tabla",
              example: 2
            }
          }
        },
        CategoriaEntrada: {
          type: "object",
          required: ["nombre"],
          properties: {
            nombre: { type: "string", maxLength: 100, example: "Gourmand" },
            descripcion: { type: "string", maxLength: 200, nullable: true },
            estado: ESTADO
          }
        },

        Proveedor: {
          type: "object",
          properties: {
            id_proveedor: { type: "integer", example: 1 },
            nombre: { type: "string", maxLength: 100 },
            contacto: { type: "string", maxLength: 100, nullable: true },
            email: { type: "string", format: "email", nullable: true },
            telefono: { type: "string", maxLength: 20, nullable: true },
            ciudad: { type: "string", maxLength: 100, nullable: true },
            calificacion: { type: "string", description: "Entre 0 y 5", example: "4.6" },
            cantidad_resenas: { type: "integer", example: 38 },
            fecha_alta: { type: "string", format: "date" },
            estado: ESTADO,
            total_productos: { type: "integer", example: 3 }
          }
        },
        ProveedorEntrada: {
          type: "object",
          required: ["nombre"],
          properties: {
            nombre: { type: "string", maxLength: 100 },
            contacto: { type: "string", maxLength: 100, nullable: true },
            email: { type: "string", format: "email", nullable: true },
            telefono: { type: "string", maxLength: 20, nullable: true },
            ciudad: { type: "string", maxLength: 100, nullable: true },
            calificacion: { type: "number", minimum: 0, maximum: 5, example: 4.3 },
            estado: ESTADO
          }
        },

        Cliente: {
          type: "object",
          properties: {
            id_cliente: { type: "integer", example: 1 },
            nombre: { type: "string", maxLength: 150 },
            correo: { type: "string", format: "email", description: "No se puede repetir" },
            telefono: { type: "string", maxLength: 20, nullable: true },
            direccion: { type: "string", maxLength: 150, nullable: true },
            ciudad: { type: "string", maxLength: 100, nullable: true },
            estado: ESTADO,
            fecha_registro: { type: "string", format: "date-time" },
            ultima_compra: { type: "string", format: "date-time", nullable: true }
          }
        },
        ClienteEntrada: {
          type: "object",
          required: ["nombre", "correo"],
          properties: {
            nombre: { type: "string", maxLength: 150 },
            correo: { type: "string", format: "email" },
            telefono: { type: "string", maxLength: 20, nullable: true },
            direccion: { type: "string", maxLength: 150, nullable: true },
            ciudad: { type: "string", maxLength: 100, nullable: true },
            estado: ESTADO
          }
        },

        Producto: {
          type: "object",
          properties: {
            id_producto: { type: "integer", example: 1 },
            sku: { type: "string", maxLength: 30, description: "No se puede repetir", example: "FLO-ROS-001" },
            nombre: { type: "string", maxLength: 100 },
            descripcion: { type: "string", maxLength: 250, nullable: true },
            precio: { type: "string", description: "Numérico con dos decimales", example: "185000.00" },
            stock: { type: "integer", minimum: 0, example: 42 },
            stock_minimo: { type: "integer", minimum: 0, example: 15 },
            estado: ESTADO,
            fecha_creacion: { type: "string", format: "date-time" },
            id_categoria: { type: "integer", example: 1 },
            categoria: { type: "string", description: "Resuelto con JOIN", example: "Floral" },
            id_proveedor: { type: "integer", example: 1 },
            proveedor: { type: "string", description: "Resuelto con JOIN" },
            stock_bajo: {
              type: "boolean",
              description: "Calculado: stock <= stock_minimo",
              example: false
            }
          }
        },
        ProductoEntrada: {
          type: "object",
          required: ["sku", "nombre", "id_categoria", "id_proveedor", "precio"],
          properties: {
            sku: { type: "string", maxLength: 30, example: "GOU-CAR-009" },
            nombre: { type: "string", maxLength: 100 },
            descripcion: { type: "string", maxLength: 250, nullable: true },
            id_categoria: { type: "integer", minimum: 1, description: "Debe existir" },
            id_proveedor: { type: "integer", minimum: 1, description: "Debe existir" },
            precio: { type: "number", minimum: 0, example: 175000 },
            stock: { type: "integer", minimum: 0, example: 20 },
            stock_minimo: { type: "integer", minimum: 0, example: 8 },
            estado: ESTADO
          }
        }
      }
    }
  };
}

export { construirEspecificacion };
