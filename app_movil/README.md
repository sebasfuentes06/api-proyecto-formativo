# Essence Don Aire — App móvil (Flutter)

App para gestionar el proceso de ventas desde el celular (ficha del proyecto,
*Proceso Móvil*), con los **mismos tres roles del proyecto principal**. Se conecta a la API desplegada en Vercel,
que a su vez usa la base PostgreSQL de Neon.

| Pestaña | Subproceso de la ficha | Qué se puede hacer |
|---|---|---|
| **Clientes** | Subproceso de clientes | Registrar, buscar, editar, activar/desactivar; historial de compras, favoritos, estado de cuenta (pantalla, WhatsApp y PDF); llamar o escribir por WhatsApp |
| **Catálogo** | Subproceso de catálogo | Productos con foto, precio y stock; filtros por categoría y stock bajo; crear/editar producto; tomar o cambiar la foto; ingreso rápido de mercancía; compartir por WhatsApp |
| **Pedidos** | Subproceso de pedidos | Registrar pedidos de WhatsApp o del local (sin mover stock), editarlos, cancelarlos, confirmarlos por WhatsApp y **convertirlos en venta** |
| **Ventas** | Subproceso de ventas | Resumen del día y del mes; nueva venta (contado o crédito, descuento, precio especial); historial con filtros y rango de fechas; **factura PDF** (compartir o imprimir); anular venta |
| **Pagos** | Subproceso de pagos y abonos | Pagos totales o abonos (efectivo, transferencia, Nequi, Daviplata, tarjeta); **link de pago Wompi**; cartera por cliente; **reporte PDF de pagos pendientes**; recordatorio por WhatsApp; anular pagos |

## Antes del login: vitrina de productos

Quien abre la app sin sesión ve el catálogo real (fotos, precios, categorías y
buscador). Para pedir tiene que **registrarse** o **iniciar sesión**.

## Roles

| | Administrador | Vendedor | Cliente |
|---|---|---|---|
| Pestañas | Clientes · Catálogo · Pedidos · Ventas · Pagos | las mismas | Catálogo · Mis pedidos · Mis compras · Mi cuenta |
| Clientes | todo, incluido activar/desactivar y darles acceso | ver, crear, editar | — |
| Catálogo | crear, editar, fotos, stock | ver | ver y pedir |
| Pedidos | todo | crear, editar, convertir en venta | los suyos: crear, editar, cancelar |
| Ventas | todo, incluido anular | registrar, ver | ver sus compras y su factura |
| Pagos | todo, incluido anular pagos | registrar abonos, links Wompi | pagar su saldo en línea con Wompi |
| Resumen | del negocio | de sus ventas | — |
| Usuarios | crear, editar rol, desactivar, restablecer clave | — | — |

Los usuarios se gestionan en **avatar ▸ Usuarios y roles**. Para darle acceso a
un cliente: ficha del cliente ▸ ⋮ ▸ *Dar acceso a la app*. La API valida cada
permiso: ocultar un botón en la app es comodidad, no la única protección.

## Registro y recuperación de contraseña

- **Regístrate** (en la vitrina o en el login), en este orden: nombre completo,
  tipo de documento, documento, celular (solo números), **municipio de
  Antioquia** (lista que se consume de la API pública
  [API Colombia](https://api-colombia.com); si no hay internet usa una lista
  guardada), dirección, correo y contraseña. El formulario de *Nuevo cliente*
  usa exactamente los mismos campos. La cuenta queda
  **pendiente**; al administrador le llega un correo y un aviso en la pestaña
  Ventas. La aprueba (eligiendo el rol) o la rechaza en **avatar ▸ Usuarios y
  roles ▸ Pendientes**, y a la persona le llega el correo con la respuesta.
- **¿Olvidaste tu contraseña?**: llega un **código de 6 dígitos** al correo
  registrado; se escribe en la app junto con la contraseña nueva. Vence en 15
  minutos y se invalida tras 5 intentos fallidos.

El envío de correos se configura en Vercel (ver `DESPLIEGUE.md`, parte 7).

## Primera vez

Dentro de esta carpeta (`app_movil`):

```bash
# 1. Genera las carpetas de Android/iOS que no vienen en el repo.
#    No sobrescribe lib/, pubspec.yaml ni el AndroidManifest que ya trae.
flutter create . --org com.essencedonaire --project-name essence_movil --platforms android

# 2. Descarga las dependencias
flutter pub get

# 3. Revisa que no haya errores
flutter analyze

# 4. Córrela en el emulador o en tu celular conectado por USB
flutter run
```

Credenciales iniciales: `admin@essence.com` / `Essence2026*` (cámbiala desde
el avatar ▸ *Cambiar contraseña*).

## Contra la API local

Por defecto la app usa `https://api-proyecto-formativo.vercel.app`. Para
probar contra la API corriendo en tu PC (`npm run dev`):

```bash
# Emulador de Android (10.0.2.2 = el localhost de tu PC)
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

> `http://` (sin s) solo está permitido en modo debug (lo habilita
> `android/app/src/debug/AndroidManifest.xml`). El APK release solo habla por https.

## Generar el APK para instalar en el celular de Yésica

```bash
flutter build apk --release
# Queda en build/app/outputs/flutter-apk/app-release.apk
```

## Estructura

```
lib/
  main.dart                  arranque, tema y vitrina/app según la sesión
  core/
    api.dart                 cliente HTTP: token, errores, paginación
    sesion.dart              login, token guardado, cerrar sesión
    eventos.dart             aviso global para recargar listas tras un cambio
    formato.dart             dinero, fechas, números que llegan como texto
    contacto.dart            WhatsApp, llamadas, abrir links
    config.dart              URL de la API y datos del negocio
  models/modelos.dart        Cliente, Producto, Pedido, Venta, Pago, WompiLink...
  widgets/
    comunes.dart             lista paginada, etiquetas, diálogos, buscador
    carrito.dart             editor de productos y campos de pago
    selectores.dart          elegir cliente / producto
    perfil.dart              cuenta, contraseña, estado de Wompi, salir
    campos_persona.dart      campos del registro y del cliente; municipios (API Colombia)
    buscador_imagenes.dart   buscar fotos en la API de Wikimedia Commons
  pdf/documentos_pdf.dart    factura, estado de cuenta, reporte de pendientes
  screens/                   una carpeta por pestaña
```

## Pagos del cliente, comprobantes y método de pago

- **Nueva venta**: el método de pago es obligatorio (efectivo, transferencia,
  Nequi, Daviplata, tarjeta o Wompi). Sale en el detalle y en la factura PDF.
- **Pedido del cliente**: escoge cómo va a pagar — Wompi, transferencia o
  efectivo en el punto físico. Al convertirlo en venta se conserva.
- **Reportar pago** (cliente): en una compra con saldo, el cliente escribe el
  monto, la referencia y adjunta la foto del comprobante. Queda *Por aprobar*.
- **Aprobar** (administrador): Pagos ▸ *Por aprobar* (o el aviso en Ventas) ▸
  toca el pago ▸ ve el comprobante ▸ Aprobar / Rechazar. El cliente recibe un
  correo con la respuesta.
- El equipo también puede adjuntar el comprobante a cualquier abono.

## Fotos del catálogo desde internet

Detalle del producto ▸ *Agregar foto* ▸ **Buscar imagen en internet**: la app
consulta la API de **Wikimedia Commons** (fotos de licencia libre), se elige una
y queda guardada en la base, así la ven todos (y la vitrina).

## Pagos con Wompi (modo pruebas)

1. En la venta, **Link Wompi** ▸ monto ▸ *Enviar por WhatsApp*.
2. El cliente abre el link y paga. En pruebas: tarjeta `4242 4242 4242 4242`
   (aprobada) o `4111 1111 1111 1111` (rechazada), fecha futura y cualquier CVC.
3. Wompi avisa a la API (webhook) y el abono aparece solo en la venta.
4. Si el webhook no está configurado todavía: menú ⋮ ▸ *Verificar pago Wompi*
   con el id de la transacción.
