-- ============================================================
-- API Proyecto Formativo - Essence Don Aire
-- Script de creación de la base de datos
-- Motor: PostgreSQL
-- ============================================================
--
-- Este esquema es un recorte del modelo aprobado del proyecto
-- Essence Don Aire. Se conservan las cuatro entidades sobre las que
-- trabaja esta API y las relaciones que hay entre ellas.
--
-- Una diferencia con el modelo completo, y por qué:
--   En el proyecto grande los clientes viven dentro de `usuarios`,
--   diferenciados por su rol, porque ese sistema tiene roles y
--   permisos. Esta API no maneja roles, así que `clientes` va como
--   tabla propia con los mismos campos que usaba un cliente allá
--   (nombre, correo, teléfono, dirección, ciudad). El modelo de
--   datos no cambia: cambia dónde se guarda la misma información.
--
-- Relaciones:
--   categorias  1 --- N  productos
--   proveedores 1 --- N  productos
--   clientes            (independiente en esta API)
-- ============================================================

-- ------------------------------------------------------------
-- Limpieza: permite volver a correr el script sin errores.
-- El orden importa: primero la tabla que tiene las llaves foráneas.
-- ------------------------------------------------------------
-- Primero las tablas de la app móvil (database/movil.sql), que dependen
-- de estas. Si ya existían, sin esto el DROP de productos fallaría.
DROP VIEW  IF EXISTS v_ventas_saldo;
DROP TABLE IF EXISTS wompi_links, pagos, detalle_venta, detalle_pedido,
                     producto_imagen CASCADE;
DROP TABLE IF EXISTS ventas, pedidos CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;
DROP SEQUENCE IF EXISTS seq_numero_factura, seq_codigo_pedido;
DROP FUNCTION IF EXISTS fecha_local(TIMESTAMP), hoy_local();

DROP TABLE IF EXISTS productos;
DROP TABLE IF EXISTS categorias;
DROP TABLE IF EXISTS proveedores;
DROP TABLE IF EXISTS clientes;

-- ------------------------------------------------------------
-- 1. CATEGORÍAS
-- ------------------------------------------------------------
CREATE TABLE categorias (
    id_categoria    SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    descripcion     VARCHAR(200),
    estado          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- El nombre no se repite: sin esto se pueden crear dos categorías
    -- "Floral" y nadie sabe en cuál va cada producto.
    CONSTRAINT uq_categorias_nombre UNIQUE (nombre)
);

-- ------------------------------------------------------------
-- 2. PROVEEDORES
-- ------------------------------------------------------------
CREATE TABLE proveedores (
    id_proveedor     SERIAL PRIMARY KEY,
    nombre           VARCHAR(100) NOT NULL,
    contacto         VARCHAR(100),
    email            VARCHAR(100),
    telefono         VARCHAR(20),
    ciudad           VARCHAR(100),
    calificacion     NUMERIC(2,1) NOT NULL DEFAULT 0,
    cantidad_resenas INT NOT NULL DEFAULT 0,
    fecha_alta       DATE NOT NULL DEFAULT CURRENT_DATE,
    estado           BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_proveedores_nombre UNIQUE (nombre),
    CONSTRAINT chk_proveedores_calificacion CHECK (calificacion BETWEEN 0 AND 5),
    CONSTRAINT chk_proveedores_resenas CHECK (cantidad_resenas >= 0)
);

-- ------------------------------------------------------------
-- 3. CLIENTES
-- ------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente      SERIAL PRIMARY KEY,
    nombre          VARCHAR(150) NOT NULL,
    correo          VARCHAR(100) NOT NULL,
    telefono        VARCHAR(20),
    direccion       VARCHAR(150),
    ciudad          VARCHAR(100),
    estado          BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ultima_compra   TIMESTAMP,
    -- Dos cuentas con el mismo correo no tienen sentido: sería la
    -- misma persona registrada dos veces.
    CONSTRAINT uq_clientes_correo UNIQUE (correo)
);

-- ------------------------------------------------------------
-- 4. PRODUCTOS
--    Depende de categorías y proveedores: se crea al final.
-- ------------------------------------------------------------
CREATE TABLE productos (
    id_producto     SERIAL PRIMARY KEY,
    id_categoria    INT NOT NULL,
    id_proveedor    INT NOT NULL,
    sku             VARCHAR(30) NOT NULL UNIQUE,
    nombre          VARCHAR(100) NOT NULL,
    descripcion     VARCHAR(250),
    precio          NUMERIC(12,2) NOT NULL DEFAULT 0,
    stock           INT NOT NULL DEFAULT 0,
    stock_minimo    INT NOT NULL DEFAULT 0,
    estado          BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_productos_categorias
        FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria),
    CONSTRAINT fk_productos_proveedores
        FOREIGN KEY (id_proveedor) REFERENCES proveedores (id_proveedor),
    CONSTRAINT chk_productos_precio CHECK (precio >= 0),
    CONSTRAINT chk_productos_stock CHECK (stock >= 0),
    CONSTRAINT chk_productos_stock_minimo CHECK (stock_minimo >= 0)
);

-- ------------------------------------------------------------
-- Índices
-- Las llaves primarias y las restricciones UNIQUE ya crean el suyo.
-- Estos son para las columnas por las que la API filtra y ordena:
-- sin ellos PostgreSQL recorre la tabla entera en cada consulta.
-- ------------------------------------------------------------
CREATE INDEX idx_productos_categoria ON productos (id_categoria);
CREATE INDEX idx_productos_proveedor ON productos (id_proveedor);
CREATE INDEX idx_productos_estado    ON productos (estado);
CREATE INDEX idx_clientes_ciudad     ON clientes (ciudad);
