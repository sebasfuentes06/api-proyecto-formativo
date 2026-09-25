import '../core/config.dart';
import '../core/formato.dart';

/// Modelos de datos. Cada uno sabe construirse desde el JSON de la API.

typedef Json = Map<String, dynamic>;

class Cliente {
  Cliente({
    required this.id,
    required this.nombre,
    this.correo,
    this.telefono,
    this.direccion,
    this.ciudad,
    this.documento,
    this.tipoDocumento,
    this.notas,
    this.estado = true,
    this.fechaRegistro,
    this.ultimaCompra,
    this.compras = 0,
    this.saldoPendiente = 0,
  });

  final int id;
  final String nombre;
  final String? correo, telefono, direccion, ciudad, documento, tipoDocumento, notas;
  final bool estado;
  final DateTime? fechaRegistro, ultimaCompra;
  final int compras;
  final double saldoPendiente;

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    return (partes.first[0] + (partes.length > 1 ? partes[1][0] : '')).toUpperCase();
  }

  factory Cliente.desdeJson(Json j) => Cliente(
        id: aInt(j['id_cliente']),
        nombre: j['nombre'] ?? '',
        correo: j['correo'],
        telefono: j['telefono'],
        direccion: j['direccion'],
        ciudad: j['ciudad'],
        documento: j['documento'],
        tipoDocumento: j['tipo_documento'],
        notas: j['notas'],
        estado: j['estado'] ?? true,
        fechaRegistro: aFecha(j['fecha_registro']),
        ultimaCompra: aFecha(j['ultima_compra']),
        compras: aInt(j['compras']),
        saldoPendiente: aNum(j['saldo_pendiente']),
      );
}

class Categoria {
  Categoria(this.id, this.nombre, this.estado);
  final int id;
  final String nombre;
  final bool estado;
  factory Categoria.desdeJson(Json j) => Categoria(aInt(j['id_categoria']), j['nombre'] ?? '', j['estado'] ?? true);
}

class Proveedor {
  Proveedor(this.id, this.nombre, this.estado);
  final int id;
  final String nombre;
  final bool estado;
  factory Proveedor.desdeJson(Json j) => Proveedor(aInt(j['id_proveedor']), j['nombre'] ?? '', j['estado'] ?? true);
}

class Producto {
  Producto({
    required this.id,
    required this.sku,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.stock,
    required this.stockMinimo,
    required this.estado,
    required this.idCategoria,
    required this.categoria,
    required this.idProveedor,
    required this.proveedor,
    this.imagenActualizada,
  });

  final int id;
  final String sku, nombre;
  final String? descripcion;
  final double precio;
  final int stock, stockMinimo;
  final bool estado;
  final int idCategoria, idProveedor;
  final String categoria, proveedor;
  final DateTime? imagenActualizada;

  bool get stockBajo => stock <= stockMinimo;
  bool get agotado => stock <= 0;
  bool get vendible => estado && stock > 0;

  /// La fecha de actualización va en la URL: si cambia la foto, cambia la URL
  /// y la app no se queda mostrando la vieja guardada en caché.
  String? get imagenUrl => imagenActualizada == null
      ? null
      : '${Config.apiUrl}/api/productos/$id/imagen?v=${imagenActualizada!.millisecondsSinceEpoch}';

  factory Producto.desdeJson(Json j) => Producto(
        id: aInt(j['id_producto']),
        sku: j['sku'] ?? '',
        nombre: j['nombre'] ?? '',
        descripcion: j['descripcion'],
        precio: aNum(j['precio']),
        stock: aInt(j['stock']),
        stockMinimo: aInt(j['stock_minimo']),
        estado: j['estado'] ?? true,
        idCategoria: aInt(j['id_categoria']),
        categoria: j['categoria'] ?? '',
        idProveedor: aInt(j['id_proveedor']),
        proveedor: j['proveedor'] ?? '',
        imagenActualizada: aFecha(j['imagen_actualizada']),
      );
}

/// Una línea de detalle de un pedido o una venta.
class Linea {
  Linea({
    required this.idProducto,
    required this.sku,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.stockActual,
    this.disponible = true,
  });

  final int idProducto;
  final String sku, nombre;
  final int cantidad;
  final double precioUnitario, subtotal;
  final int? stockActual;
  final bool disponible;

  factory Linea.desdeJson(Json j) => Linea(
        idProducto: aInt(j['id_producto']),
        sku: j['sku'] ?? '',
        nombre: j['nombre'] ?? '',
        cantidad: aInt(j['cantidad']),
        precioUnitario: aNum(j['precio_unitario']),
        subtotal: aNum(j['subtotal']),
        stockActual: j['stock_actual'] == null ? null : aInt(j['stock_actual']),
        disponible: j['disponible'] ?? true,
      );
}

class Pedido {
  Pedido({
    required this.id,
    required this.codigo,
    required this.fecha,
    required this.canal,
    required this.estado,
    required this.total,
    this.notas,
    this.direccionEntrega,
    required this.idCliente,
    required this.cliente,
    this.clienteTelefono,
    this.clienteDireccion,
    this.idVenta,
    this.numeroFactura,
    this.unidades = 0,
    this.items = const [],
    this.metodoPago,
  });

  final int id;
  final String codigo;
  /// Cómo va a pagar: wompi, transferencia, efectivo...
  final String? metodoPago;
  final DateTime? fecha;
  final String canal, estado;
  final double total;
  final String? notas, direccionEntrega;
  final int idCliente;
  final String cliente;
  final String? clienteTelefono, clienteDireccion;
  final int? idVenta;
  final String? numeroFactura;
  final int unidades;
  final List<Linea> items;

  bool get pendiente => estado == 'pendiente';

  factory Pedido.desdeJson(Json j) => Pedido(
        id: aInt(j['id_pedido']),
        codigo: j['codigo'] ?? '',
        fecha: aFecha(j['fecha']),
        canal: j['canal'] ?? 'whatsapp',
        estado: j['estado'] ?? 'pendiente',
        total: aNum(j['total']),
        notas: j['notas'],
        direccionEntrega: j['direccion_entrega'],
        idCliente: aInt(j['id_cliente']),
        cliente: j['cliente'] ?? '',
        clienteTelefono: j['cliente_telefono'],
        clienteDireccion: j['cliente_direccion'],
        idVenta: j['id_venta'] == null ? null : aInt(j['id_venta']),
        numeroFactura: j['numero_factura'],
        unidades: aInt(j['unidades']),
        items: ((j['items'] as List?) ?? []).map((e) => Linea.desdeJson(e as Json)).toList(),
        metodoPago: j['metodo_pago'],
      );
}

class Pago {
  Pago({
    required this.id,
    required this.idVenta,
    required this.monto,
    required this.metodo,
    this.referencia,
    this.nota,
    required this.estado,
    this.fecha,
    this.numeroFactura,
    this.cliente,
    this.clienteTelefono,
    this.motivoRechazo,
    this.tieneComprobante = false,
  });

  final int id, idVenta;
  final double monto;
  final String metodo, estado;
  final String? referencia, nota, numeroFactura, cliente, clienteTelefono, motivoRechazo;
  final DateTime? fecha;
  final bool tieneComprobante;

  bool get anulado => estado == 'anulado';
  bool get aplicado => estado == 'aplicado';
  /// Reportado por el cliente, esperando que el Administrador lo apruebe.
  bool get porAprobar => estado == 'pendiente';
  bool get rechazado => estado == 'rechazado';

  /// La imagen exige sesión: se pide con la cabecera Authorization.
  String get comprobanteUrl => '${Config.apiUrl}/api/pagos/$id/comprobante';

  factory Pago.desdeJson(Json j) => Pago(
        id: aInt(j['id_pago']),
        idVenta: aInt(j['id_venta']),
        monto: aNum(j['monto']),
        metodo: j['metodo'] ?? '',
        referencia: j['referencia'],
        nota: j['nota'],
        estado: j['estado'] ?? 'aplicado',
        fecha: aFecha(j['fecha']),
        numeroFactura: j['numero_factura'],
        cliente: j['cliente'],
        clienteTelefono: j['cliente_telefono'],
        motivoRechazo: j['motivo_rechazo'],
        tieneComprobante: j['tiene_comprobante'] == true,
      );
}

class WompiLink {
  WompiLink({required this.id, required this.monto, required this.url, required this.estado, this.creadoEn, this.expiraEn});
  final String id, url, estado;
  final double monto;
  final DateTime? creadoEn, expiraEn;

  factory WompiLink.desdeJson(Json j) => WompiLink(
        id: j['id_link'] ?? '',
        monto: aNum(j['monto']),
        url: j['url'] ?? '',
        estado: j['estado'] ?? 'activo',
        creadoEn: aFecha(j['creado_en']),
        expiraEn: aFecha(j['expira_en']),
      );
}

class Venta {
  Venta({
    required this.id,
    required this.numeroFactura,
    this.fecha,
    required this.canal,
    required this.estado,
    required this.subtotal,
    required this.descuento,
    required this.total,
    required this.pagado,
    required this.saldo,
    required this.estadoPago,
    required this.idCliente,
    required this.cliente,
    this.clienteTelefono,
    this.clienteCorreo,
    this.clienteDireccion,
    this.clienteCiudad,
    this.clienteDocumento,
    this.idPedido,
    this.pedidoCodigo,
    this.vendedor,
    this.notas,
    this.motivoAnulacion,
    this.unidades = 0,
    this.items = const [],
    this.pagos = const [],
    this.links = const [],
    this.metodoPago,
  });

  final int id;
  final String numeroFactura;
  final String? metodoPago;
  final DateTime? fecha;
  final String canal, estado, estadoPago;
  final double subtotal, descuento, total, pagado, saldo;
  final int idCliente;
  final String cliente;
  final String? clienteTelefono, clienteCorreo, clienteDireccion, clienteCiudad, clienteDocumento;
  final int? idPedido;
  final String? pedidoCodigo, vendedor, notas, motivoAnulacion;
  final int unidades;
  final List<Linea> items;
  final List<Pago> pagos;
  final List<WompiLink> links;

  bool get anulada => estado == 'anulada';
  bool get debe => !anulada && saldo > 0;

  factory Venta.desdeJson(Json j) => Venta(
        id: aInt(j['id_venta']),
        numeroFactura: j['numero_factura'] ?? '',
        fecha: aFecha(j['fecha']),
        canal: j['canal'] ?? 'punto_fisico',
        estado: j['estado'] ?? 'confirmada',
        subtotal: aNum(j['subtotal']),
        descuento: aNum(j['descuento']),
        total: aNum(j['total']),
        pagado: aNum(j['pagado']),
        saldo: aNum(j['saldo']),
        estadoPago: j['estado_pago'] ?? 'pendiente',
        idCliente: aInt(j['id_cliente']),
        cliente: j['cliente'] ?? '',
        clienteTelefono: j['cliente_telefono'],
        clienteCorreo: j['cliente_correo'],
        clienteDireccion: j['cliente_direccion'],
        clienteCiudad: j['cliente_ciudad'],
        clienteDocumento: j['cliente_documento'],
        idPedido: j['id_pedido'] == null ? null : aInt(j['id_pedido']),
        pedidoCodigo: j['pedido_codigo'],
        vendedor: j['vendedor'],
        notas: j['notas'],
        motivoAnulacion: j['motivo_anulacion'],
        unidades: aInt(j['unidades']),
        items: ((j['items'] as List?) ?? []).map((e) => Linea.desdeJson(e as Json)).toList(),
        pagos: ((j['pagos'] as List?) ?? []).map((e) => Pago.desdeJson(e as Json)).toList(),
        links: ((j['wompi_links'] as List?) ?? []).map((e) => WompiLink.desdeJson(e as Json)).toList(),
        metodoPago: j['metodo_pago'],
      );
}

/// Línea del carrito mientras se arma un pedido o una venta.
class LineaCarrito {
  LineaCarrito(this.producto, {this.cantidad = 1, double? precio}) : precio = precio ?? producto.precio;
  final Producto producto;
  int cantidad;
  double precio;
  double get subtotal => cantidad * precio;

  Json aJson() => {
        'id_producto': producto.id,
        'cantidad': cantidad,
        'precio_unitario': precio,
      };
}

/// Cuenta de acceso a la app (gestión de usuarios del Administrador).
class UsuarioApp {
  UsuarioApp({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.estado,
    this.idCliente,
    this.cliente,
    this.ultimoAcceso,
    this.aprobacion = 'aprobado',
    this.telefono,
    this.motivoRechazo,
    this.creadoEn,
  });

  final int id;
  final String nombre, correo, rol;
  final bool estado;
  final int? idCliente;
  final String? cliente;
  final DateTime? ultimoAcceso;

  /// pendiente | aprobado | rechazado (registro desde la app).
  final String aprobacion;
  final String? telefono, motivoRechazo;
  final DateTime? creadoEn;

  bool get pendiente => aprobacion == 'pendiente';
  bool get rechazado => aprobacion == 'rechazado';

  factory UsuarioApp.desdeJson(Json j) => UsuarioApp(
        id: aInt(j['id_usuario']),
        nombre: j['nombre'] ?? '',
        correo: j['correo'] ?? '',
        rol: j['rol'] ?? '',
        estado: j['estado'] ?? true,
        idCliente: j['id_cliente'] == null ? null : aInt(j['id_cliente']),
        cliente: j['cliente'],
        ultimoAcceso: aFecha(j['ultimo_acceso']),
        aprobacion: j['aprobacion'] ?? 'aprobado',
        telefono: j['telefono'],
        motivoRechazo: j['motivo_rechazo'],
        creadoEn: aFecha(j['created_at']),
      );
}
