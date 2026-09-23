# Essence Don Aire — App móvil (Flutter)

App del **administrador** para gestionar el proceso de ventas desde el celular
(ficha del proyecto, *Proceso Móvil*). Se conecta a la API desplegada en Vercel,
que a su vez usa la base PostgreSQL de Neon.

| Pestaña | Subproceso de la ficha | Qué se puede hacer |
|---|---|---|
| **Clientes** | Subproceso de clientes | Registrar, buscar, editar, activar/desactivar; historial de compras, favoritos, estado de cuenta (pantalla, WhatsApp y PDF); llamar o escribir por WhatsApp |
| **Catálogo** | Subproceso de catálogo | Productos con foto, precio y stock; filtros por categoría y stock bajo; crear/editar producto; tomar o cambiar la foto; ingreso rápido de mercancía; compartir por WhatsApp |
| **Pedidos** | Subproceso de pedidos | Registrar pedidos de WhatsApp o del local (sin mover stock), editarlos, cancelarlos, confirmarlos por WhatsApp y **convertirlos en venta** |
| **Ventas** | Subproceso de ventas | Resumen del día y del mes; nueva venta (contado o crédito, descuento, precio especial); historial con filtros y rango de fechas; **factura PDF** (compartir o imprimir); anular venta |
| **Pagos** | Subproceso de pagos y abonos | Pagos totales o abonos (efectivo, transferencia, Nequi, Daviplata, tarjeta); **link de pago Wompi**; cartera por cliente; **reporte PDF de pagos pendientes**; recordatorio por WhatsApp; anular pagos |

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
  main.dart                  arranque, tema y login/app según la sesión
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
  pdf/documentos_pdf.dart    factura, estado de cuenta, reporte de pendientes
  screens/                   una carpeta por pestaña
```

## Pagos con Wompi (modo pruebas)

1. En la venta, **Link Wompi** ▸ monto ▸ *Enviar por WhatsApp*.
2. El cliente abre el link y paga. En pruebas: tarjeta `4242 4242 4242 4242`
   (aprobada) o `4111 1111 1111 1111` (rechazada), fecha futura y cualquier CVC.
3. Wompi avisa a la API (webhook) y el abono aparece solo en la venta.
4. Si el webhook no está configurado todavía: menú ⋮ ▸ *Verificar pago Wompi*
   con el id de la transacción.
