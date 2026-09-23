-- ============================================================
-- API Proyecto Formativo - Essence Don Aire
-- Extensión para la APP MÓVIL: proceso de ventas completo
-- Motor: PostgreSQL
-- ============================================================
--
-- Agrega lo que necesita la app del administrador (ficha del proyecto,
-- "Proceso Móvil"):
--
--   usuarios          quién entra a la app (login con JWT)
--   producto_imagen   foto de cada producto para el catálogo
--   pedidos           pedidos temporales (WhatsApp o punto físico)
--   detalle_pedido
--   ventas            ventas confirmadas, con número de factura
--   detalle_venta
--   pagos             pagos totales o parciales (abonos) de cada venta
--   wompi_links       links de pago de Wompi generados para una venta
--
-- Es IDEMPOTENTE: se puede correr sobre la base que ya está en Neon sin
-- borrar nada (usa IF NOT EXISTS). Por eso sirve tanto para migrar la base
-- desplegada como para montar una nueva desde cero.
--
-- Relaciones nuevas:
--   clientes  1 --- N  pedidos   1 --- N detalle_pedido  N --- 1 productos
--   clientes  1 --- N  ventas    1 --- N detalle_venta   N --- 1 productos
--   ventas    1 --- N  pagos
--   ventas    1 --- N  wompi_links
--   pedidos   0..1 --- 0..1 ventas   (un pedido confirmado se vuelve venta)
-- ============================================================

-- ------------------------------------------------------------
-- Ajuste a CLIENTES
-- La ficha pide nombre, dirección y teléfono. Muchos clientes de WhatsApp
-- no dan correo, así que deja de ser obligatorio (sigue siendo único
-- cuando viene: UNIQUE admite varios NULL).
-- ------------------------------------------------------------
ALTER TABLE clientes ALTER COLUMN correo DROP NOT NULL;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS documento VARCHAR(20);
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS notas     VARCHAR(250);

-- ------------------------------------------------------------
-- 1. USUARIOS (acceso a la app)
-- La contraseña se guarda como hash bcrypt, nunca en texto plano.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id_usuario      SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    correo          VARCHAR(100) NOT NULL,
    password_hash   VARCHAR(100) NOT NULL,
    rol             VARCHAR(30)  NOT NULL DEFAULT 'Administrador',
    estado          BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_acceso   TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_usuarios_correo UNIQUE (correo)
);

-- ------------------------------------------------------------
-- 2. IMAGEN DE PRODUCTO
-- Se guarda en la propia base (BYTEA) para no depender de otro servicio
-- de archivos. La app la comprime antes de subirla (~100 KB).
-- Tabla aparte para que listar productos no arrastre los bytes.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS producto_imagen (
    id_producto     INT PRIMARY KEY,
    contenido       BYTEA NOT NULL,
    tipo_mime       VARCHAR(30) NOT NULL DEFAULT 'image/jpeg',
    actualizada_en  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_imagen_producto
        FOREIGN KEY (id_producto) REFERENCES productos (id_producto) ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 3. PEDIDOS
-- Pedido temporal: NO descuenta stock. El stock se mueve cuando el pedido
-- se convierte en venta.
-- ------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_codigo_pedido;

CREATE TABLE IF NOT EXISTS pedidos (
    id_pedido         SERIAL PRIMARY KEY,
    codigo            VARCHAR(20) NOT NULL
                      DEFAULT ('PED-' || LPAD(nextval('seq_codigo_pedido')::TEXT, 5, '0')),
    id_cliente        INT NOT NULL,
    canal             VARCHAR(20) NOT NULL DEFAULT 'whatsapp',
    estado            VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    direccion_entrega VARCHAR(150),
    notas             VARCHAR(250),
    total             NUMERIC(12,2) NOT NULL DEFAULT 0,
    id_venta          INT,
    id_usuario        INT,
    fecha             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_pedidos_codigo UNIQUE (codigo),
    CONSTRAINT fk_pedidos_cliente FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente),
    CONSTRAINT fk_pedidos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario),
    CONSTRAINT chk_pedidos_canal  CHECK (canal IN ('whatsapp', 'punto_fisico')),
    CONSTRAINT chk_pedidos_estado CHECK (estado IN ('pendiente', 'confirmado', 'cancelado')),
    CONSTRAINT chk_pedidos_total  CHECK (total >= 0)
);

CREATE TABLE IF NOT EXISTS detalle_pedido (
    id_detalle       SERIAL PRIMARY KEY,
    id_pedido        INT NOT NULL,
    id_producto      INT NOT NULL,
    cantidad         INT NOT NULL,
    precio_unitario  NUMERIC(12,2) NOT NULL,
    subtotal         NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    CONSTRAINT fk_detped_pedido   FOREIGN KEY (id_pedido)   REFERENCES pedidos (id_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_detped_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT chk_detped_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detped_precio   CHECK (precio_unitario >= 0),
    CONSTRAINT uq_detped_producto  UNIQUE (id_pedido, id_producto)
);

-- ------------------------------------------------------------
-- 4. VENTAS
-- El número de factura sale de una secuencia: nunca se repite ni se salta
-- por concurrencia. Una venta no se edita; si hubo un error se ANULA
-- (devuelve el stock) y se registra de nuevo.
-- ------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_numero_factura;

CREATE TABLE IF NOT EXISTS ventas (
    id_venta          SERIAL PRIMARY KEY,
    numero_factura    VARCHAR(20) NOT NULL
                      DEFAULT ('FV-' || LPAD(nextval('seq_numero_factura')::TEXT, 6, '0')),
    id_cliente        INT NOT NULL,
    id_pedido         INT,
    canal             VARCHAR(20) NOT NULL DEFAULT 'punto_fisico',
    subtotal          NUMERIC(12,2) NOT NULL DEFAULT 0,
    descuento         NUMERIC(12,2) NOT NULL DEFAULT 0,
    total             NUMERIC(12,2) NOT NULL DEFAULT 0,
    estado            VARCHAR(20) NOT NULL DEFAULT 'confirmada',
    notas             VARCHAR(250),
    motivo_anulacion  VARCHAR(250),
    id_usuario        INT,
    fecha             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    anulada_en        TIMESTAMP,
    CONSTRAINT uq_ventas_factura UNIQUE (numero_factura),
    CONSTRAINT fk_ventas_cliente FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente),
    CONSTRAINT fk_ventas_pedido  FOREIGN KEY (id_pedido)  REFERENCES pedidos (id_pedido),
    CONSTRAINT fk_ventas_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario),
    CONSTRAINT chk_ventas_canal  CHECK (canal IN ('whatsapp', 'punto_fisico')),
    CONSTRAINT chk_ventas_estado CHECK (estado IN ('confirmada', 'anulada')),
    CONSTRAINT chk_ventas_montos CHECK (subtotal >= 0 AND descuento >= 0 AND descuento <= subtotal
                                        AND total = subtotal - descuento)
);

-- La llave pedido -> venta se agrega después porque ventas no existía
-- cuando se creó pedidos. El DO evita el error al correr el script 2 veces.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_pedidos_venta') THEN
    ALTER TABLE pedidos ADD CONSTRAINT fk_pedidos_venta
      FOREIGN KEY (id_venta) REFERENCES ventas (id_venta);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS detalle_venta (
    id_detalle       SERIAL PRIMARY KEY,
    id_venta         INT NOT NULL,
    id_producto      INT NOT NULL,
    cantidad         INT NOT NULL,
    precio_unitario  NUMERIC(12,2) NOT NULL,
    subtotal         NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    CONSTRAINT fk_detven_venta    FOREIGN KEY (id_venta)    REFERENCES ventas (id_venta) ON DELETE CASCADE,
    CONSTRAINT fk_detven_producto FOREIGN KEY (id_producto) REFERENCES productos (id_producto),
    CONSTRAINT chk_detven_cantidad CHECK (cantidad > 0),
    CONSTRAINT chk_detven_precio   CHECK (precio_unitario >= 0),
    CONSTRAINT uq_detven_producto  UNIQUE (id_venta, id_producto)
);

-- ------------------------------------------------------------
-- 5. PAGOS (pagos totales y abonos)
-- Un pago no se borra: se ANULA, para que quede rastro.
-- wompi_transaccion_id es UNIQUE: si Wompi manda el mismo evento dos veces
-- (lo hace cuando reintenta) el abono no se registra doble.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pagos (
    id_pago               SERIAL PRIMARY KEY,
    id_venta              INT NOT NULL,
    monto                 NUMERIC(12,2) NOT NULL,
    metodo                VARCHAR(20) NOT NULL,
    referencia            VARCHAR(100),
    nota                  VARCHAR(250),
    estado                VARCHAR(20) NOT NULL DEFAULT 'aplicado',
    wompi_transaccion_id  VARCHAR(60),
    id_usuario            INT,
    fecha                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    anulado_en            TIMESTAMP,
    CONSTRAINT fk_pagos_venta   FOREIGN KEY (id_venta)   REFERENCES ventas (id_venta),
    CONSTRAINT fk_pagos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario),
    CONSTRAINT chk_pagos_monto  CHECK (monto > 0),
    CONSTRAINT chk_pagos_metodo CHECK (metodo IN ('efectivo', 'transferencia', 'nequi', 'daviplata', 'tarjeta', 'wompi')),
    CONSTRAINT chk_pagos_estado CHECK (estado IN ('aplicado', 'anulado')),
    CONSTRAINT uq_pagos_wompi   UNIQUE (wompi_transaccion_id)
);

-- ------------------------------------------------------------
-- 6. LINKS DE PAGO WOMPI
-- id_link es el id que devuelve Wompi (ej. "3Z0Cfi").
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wompi_links (
    id_link      VARCHAR(40) PRIMARY KEY,
    id_venta     INT NOT NULL,
    monto        NUMERIC(12,2) NOT NULL,
    url          VARCHAR(200) NOT NULL,
    estado       VARCHAR(20) NOT NULL DEFAULT 'activo',
    id_pago      INT,
    creado_en    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en    TIMESTAMP,
    CONSTRAINT fk_wompi_venta FOREIGN KEY (id_venta) REFERENCES ventas (id_venta),
    CONSTRAINT fk_wompi_pago  FOREIGN KEY (id_pago)  REFERENCES pagos (id_pago),
    CONSTRAINT chk_wompi_monto  CHECK (monto > 0),
    CONSTRAINT chk_wompi_estado CHECK (estado IN ('activo', 'pagado', 'rechazado', 'anulado'))
);

-- ------------------------------------------------------------
-- 7. VISTA DE SALDOS
-- Una sola definición de "cuánto se ha pagado y cuánto falta" para toda la
-- API. Si cada consulta lo calculara a su manera, tarde o temprano dos
-- pantallas mostrarían saldos distintos para la misma venta.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_ventas_saldo AS
SELECT v.id_venta,
       v.total,
       COALESCE(SUM(p.monto) FILTER (WHERE p.estado = 'aplicado'), 0)::NUMERIC(12,2) AS pagado,
       (v.total - COALESCE(SUM(p.monto) FILTER (WHERE p.estado = 'aplicado'), 0))::NUMERIC(12,2) AS saldo,
       CASE
         WHEN v.estado = 'anulada' THEN 'anulada'
         WHEN COALESCE(SUM(p.monto) FILTER (WHERE p.estado = 'aplicado'), 0) >= v.total THEN 'pagada'
         WHEN COALESCE(SUM(p.monto) FILTER (WHERE p.estado = 'aplicado'), 0) > 0 THEN 'parcial'
         ELSE 'pendiente'
       END AS estado_pago
  FROM ventas v
  LEFT JOIN pagos p ON p.id_venta = v.id_venta
 GROUP BY v.id_venta, v.total, v.estado;

-- ------------------------------------------------------------
-- 8. HORA DE COLOMBIA
-- Las fechas se guardan en la zona del servidor (en Neon es UTC). Sin esto,
-- una venta de las 8 p. m. en La Pintada quedaría contada como "mañana" en
-- el resumen del día. Estas funciones pasan cualquier fecha a hora Colombia.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fecha_local(ts TIMESTAMP) RETURNS TIMESTAMP
  LANGUAGE SQL STABLE AS
$$ SELECT (ts AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Bogota' $$;

CREATE OR REPLACE FUNCTION hoy_local() RETURNS DATE
  LANGUAGE SQL STABLE AS
$$ SELECT (now() AT TIME ZONE 'America/Bogota')::DATE $$;

-- ------------------------------------------------------------
-- Índices para los filtros de la app
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pedidos_cliente ON pedidos (id_cliente);
CREATE INDEX IF NOT EXISTS idx_pedidos_estado  ON pedidos (estado);
CREATE INDEX IF NOT EXISTS idx_ventas_cliente  ON ventas (id_cliente);
CREATE INDEX IF NOT EXISTS idx_ventas_fecha    ON ventas (fecha);
CREATE INDEX IF NOT EXISTS idx_pagos_venta     ON pagos (id_venta);
CREATE INDEX IF NOT EXISTS idx_detven_producto ON detalle_venta (id_producto);
CREATE INDEX IF NOT EXISTS idx_wompi_venta     ON wompi_links (id_venta);

-- ============================================================
-- 9. ROLES (Administrador, Vendedor, Cliente)
-- Los mismos tres perfiles del proyecto principal. Un usuario con rol
-- Cliente queda enlazado a su ficha en `clientes` (id_cliente): así ve
-- solo sus pedidos, sus compras y su estado de cuenta.
-- ============================================================
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS id_cliente INT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_usuarios_cliente') THEN
    ALTER TABLE usuarios ADD CONSTRAINT fk_usuarios_cliente
      FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente);
  END IF;
  -- Una ficha de cliente tiene como máximo un usuario.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_usuarios_cliente') THEN
    ALTER TABLE usuarios ADD CONSTRAINT uq_usuarios_cliente UNIQUE (id_cliente);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_usuarios_rol') THEN
    ALTER TABLE usuarios ADD CONSTRAINT chk_usuarios_rol
      CHECK (rol IN ('Administrador', 'Vendedor', 'Cliente'));
  END IF;
  -- El rol Cliente siempre apunta a una ficha; los demás, nunca.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_usuarios_rol_cliente') THEN
    ALTER TABLE usuarios ADD CONSTRAINT chk_usuarios_rol_cliente
      CHECK ((rol = 'Cliente') = (id_cliente IS NOT NULL));
  END IF;
END $$;

-- Canal "app": pedidos que el cliente hace él mismo desde la app.
ALTER TABLE pedidos DROP CONSTRAINT IF EXISTS chk_pedidos_canal;
ALTER TABLE pedidos ADD CONSTRAINT chk_pedidos_canal CHECK (canal IN ('whatsapp', 'punto_fisico', 'app'));
ALTER TABLE ventas  DROP CONSTRAINT IF EXISTS chk_ventas_canal;
ALTER TABLE ventas  ADD CONSTRAINT chk_ventas_canal  CHECK (canal IN ('whatsapp', 'punto_fisico', 'app'));

CREATE INDEX IF NOT EXISTS idx_ventas_usuario ON ventas (id_usuario);

-- ============================================================
-- 10. REGISTRO CON APROBACIÓN Y RECUPERACIÓN DE CONTRASEÑA
-- ------------------------------------------------------------
-- Cualquiera puede registrarse desde la app, pero la cuenta queda
-- "pendiente" hasta que el Administrador la apruebe (y le asigne rol).
-- Los usuarios creados por el Administrador nacen "aprobado".
-- ============================================================
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS aprobacion     VARCHAR(20) NOT NULL DEFAULT 'aprobado';
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS telefono       VARCHAR(20);
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS motivo_rechazo VARCHAR(250);
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS revisado_en    TIMESTAMP;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_usuarios_aprobacion') THEN
    ALTER TABLE usuarios ADD CONSTRAINT chk_usuarios_aprobacion
      CHECK (aprobacion IN ('pendiente', 'aprobado', 'rechazado'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_usuarios_aprobacion ON usuarios (aprobacion);

-- Códigos de "olvidé mi contraseña". Se guarda el HASH del código, no el
-- código: si alguien lee la tabla, no puede usar los códigos vigentes.
CREATE TABLE IF NOT EXISTS codigos_recuperacion (
    id_codigo    SERIAL PRIMARY KEY,
    id_usuario   INT NOT NULL,
    codigo_hash  VARCHAR(64) NOT NULL,
    expira_en    TIMESTAMP NOT NULL,
    intentos     INT NOT NULL DEFAULT 0,
    usado_en     TIMESTAMP,
    creado_en    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_codigos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_codigos_usuario ON codigos_recuperacion (id_usuario);
