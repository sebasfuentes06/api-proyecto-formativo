-- ============================================================
-- Datos de ejemplo
-- Se corre DESPUÉS de esquema.sql.
-- Sirve para que la API tenga con qué responder apenas se levanta.
-- ============================================================

-- Se vacían primero por si el script se corre dos veces.
-- TRUNCATE ... RESTART IDENTITY deja los contadores de los SERIAL en 1,
-- así los ids vuelven a empezar desde 1 y las pruebas son repetibles.
TRUNCATE productos, categorias, proveedores, clientes RESTART IDENTITY CASCADE;

-- ------------------------------------------------------------
-- Categorías
-- ------------------------------------------------------------
INSERT INTO categorias (nombre, descripcion, estado) VALUES
    ('Floral',    'Fragancias con notas de flores: rosa, jazmín, peonía',  TRUE),
    ('Amaderado', 'Notas de sándalo, cedro y vetiver',                     TRUE),
    ('Cítrico',   'Bergamota, limón y naranja; frescos y ligeros',          TRUE),
    ('Oriental',  'Vainilla, ámbar y especias; intensos y duraderos',       TRUE),
    ('Acuático',  'Notas marinas y frescas',                               FALSE);

-- ------------------------------------------------------------
-- Proveedores
-- ------------------------------------------------------------
INSERT INTO proveedores (nombre, contacto, email, telefono, ciudad, calificacion, cantidad_resenas, estado) VALUES
    ('Esencias del Valle S.A.S.', 'Andrea Gómez',   'contacto@esenciasvalle.com', '+57 604 444 1122', 'Medellín',     4.6, 38, TRUE),
    ('Aromas Premium Ltda.',      'Julián Restrepo','ventas@aromaspremium.co',    '+57 601 555 8899', 'Bogotá',       4.2, 21, TRUE),
    ('Distribuidora Aroma Fina',  'Paola Cardona',  'info@aromafina.com',         '+57 602 333 7766', 'Cali',         3.8, 12, TRUE),
    ('Importadora Le Parfum',     'Camilo Ríos',    'compras@leparfum.com.co',    '+57 605 222 4455', 'Barranquilla', 4.9, 54, FALSE);

-- ------------------------------------------------------------
-- Clientes
-- ------------------------------------------------------------
INSERT INTO clientes (nombre, correo, telefono, direccion, ciudad, estado) VALUES
    ('Laura Restrepo Vélez',  'laura.restrepo@correo.com',  '+57 300 111 2233', 'Calle 10 #43-20',     'Medellín', TRUE),
    ('Andrés Mejía Ospina',   'andres.mejia@correo.com',    '+57 301 222 3344', 'Carrera 70 #45-11',   'Medellín', TRUE),
    ('Valentina Cano Ruiz',   'valentina.cano@correo.com',  '+57 302 333 4455', 'Avenida 30 #12-05',   'Bogotá',   TRUE),
    ('Santiago Ortiz Duque',  'santiago.ortiz@correo.com',  '+57 303 444 5566', 'Calle 5 #38-14',      'Cali',     TRUE),
    ('Mariana Zapata Hoyos',  'mariana.zapata@correo.com',  '+57 304 555 6677', 'Transversal 8 #22-40','Medellín', FALSE);

-- ------------------------------------------------------------
-- Productos
-- Los ids de categoría y proveedor corresponden al orden de arriba,
-- porque el TRUNCATE reinició los contadores.
-- Dos productos quedan por debajo del stock mínimo a propósito, para
-- que la consulta de stock bajo tenga qué mostrar.
-- ------------------------------------------------------------
INSERT INTO productos (id_categoria, id_proveedor, sku, nombre, descripcion, precio, stock, stock_minimo, estado) VALUES
    (1, 1, 'FLO-ROS-001', 'Rosa Eterna',      'Eau de parfum floral con rosa búlgara y peonía',  185000, 42,  15, TRUE),
    (1, 2, 'FLO-JAZ-002', 'Jazmín de Noche',  'Floral intenso con jazmín y ylang-ylang',         210000, 12,  20, TRUE),
    (2, 1, 'AMA-SAN-003', 'Sándalo Real',     'Amaderado con sándalo de Mysore y cedro',         245000, 30,  10, TRUE),
    (2, 3, 'AMA-VET-004', 'Vetiver Profundo', 'Amaderado seco con vetiver de Haití',             198000, 25,  10, TRUE),
    (3, 2, 'CIT-BER-005', 'Bergamota Fresca', 'Cítrico ligero con bergamota de Calabria',        152000,  8,  25, TRUE),
    (3, 3, 'CIT-LIM-006', 'Limón de Amalfi',  'Cítrico con limón de Amalfi y hierbabuena',       140000, 60,  20, TRUE),
    (4, 1, 'ORI-VAI-007', 'Vainilla Ámbar',   'Oriental cálido con vainilla de Madagascar',      265000, 18,  12, TRUE),
    (4, 2, 'ORI-ESP-008', 'Especias de Oud',  'Oriental intenso con oud y canela',               320000, 15,  10, FALSE);
