# Despliegue

Cómo se publicó esta API en internet: el código en **Vercel** y la base de
datos en **Neon**, provisionada desde el propio Marketplace de Vercel.

Resultado: <https://api-proyecto-formativo.vercel.app>

| | |
|---|---|
| Documentación interactiva | `/docs` |
| Especificación OpenAPI | `/api/openapi.json` |
| Estado del servicio | `/api/health` |

---

## El orden importa

Al desplegar hay una dependencia que no es obvia: la base de datos se
provisiona **desde dentro** del proyecto de Vercel, así que el proyecto tiene
que existir primero. Por eso el orden es:

```
1. Subir el código a GitHub
2. Importarlo en Vercel y desplegar   -> la API vive, pero sin base
3. Crear la base Neon desde Vercel    -> se inyecta DATABASE_URL sola
4. Crear las tablas desde tu equipo   -> npm run db:setup
5. Volver a desplegar                 -> ahora sí, completa
```

Entre el paso 2 y el 5, `/api/health` responde `"baseDeDatos": "sin conexión"`.
Eso **no es un error**: es la API diciendo correctamente que está viva pero no
alcanza ninguna base.

---

## Parte 1 — Subir el código a GitHub

```bash
git init
git add .
git commit -m "API del proyecto formativo"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/api-proyecto-formativo.git
git push -u origin main
```

Antes del `push`, comprueba que el `.env` **no** vaya incluido:

```bash
git ls-files | grep env
```

Debe devolver `.env.example` y `src/config/env.js`, y nada más. Si aparece
`.env` a secas, ahí va la contraseña de tu base de datos: sácalo del índice
(`git rm --cached .env`) antes de subir nada. Una contraseña que entra al
historial de Git se queda ahí aunque borres el archivo después.

---

## Parte 2 — Crear el proyecto en Vercel

1. <https://vercel.com> → **Add New → Project**
2. Importa el repositorio
3. Vercel detecta *Express* solo. **No toques nada más**: ni Build Command, ni
   Output Directory, ni Root Directory (la API está en la raíz del repo).
4. **No agregues variables de entorno todavía.** Si Vercel te ofrece importar
   tu `.env` local, dile que no: esas variables apuntan a `localhost`, que
   desde un servidor de Vercel no existe, y además le bloquean el paso a la
   integración de la base de datos.
5. **Deploy**

Al terminar, abre la URL. La portada responde. `/api/health` dirá
`"sin conexión"`, que es lo esperado en este punto.

---

## Parte 3 — La base de datos, desde Vercel

No hace falta crear cuenta en Neon: se provisiona desde el propio Vercel y las
credenciales se inyectan solas en el proyecto.

1. Dentro del proyecto → pestaña **Storage** (*Almacenamiento*)
2. **Create Database** → **Neon — Serverless Postgres**
3. Región: la más cercana a Colombia (`us-east-1` o `us-east-2`)
4. Entornos: *Production* y *Preview*
5. **Prefijo personalizado: déjalo VACÍO.** Si le pones uno, la variable se
   llamaría `MIPREFIJO_DATABASE_URL` y el código busca `DATABASE_URL` a secas.
6. **Connect**

Si se queja de que ya existe una variable con ese nombre, es por el punto 4 de
la parte 2: ve a *Settings → Environments → Production → Environment Variables*
y borra las `PG*`, `PORT` y `NODE_ENV`. Deja `CORS_ORIGINS`.

Para confirmar que quedó: en esa misma pantalla debe aparecer `DATABASE_URL`.

---

## Parte 4 — Crear las tablas

La base existe pero está vacía. En la nube no hay pgAdmin para abrir el `.sql`
y darle *ejecutar*, así que se manda desde tu equipo.

**1.** En Vercel, en la pantalla de la base Neon, sección *Inicio rápido*, dale
a **Mostrar secreto** y copia el valor de `DATABASE_URL` — la primera, la que
dice *"Recommended for most uses"*. Lleva `-pooler` en el nombre del servidor:
esa reparte las conexiones y evita el error `too many connections`.

**2.** Agrégala a tu `.env` local. No hace falta comentar las variables `PG*`:
si `DATABASE_URL` existe, el código la usa y se olvida de las demás.

```powershell
Add-Content .env ""
Add-Content .env 'DATABASE_URL=PEGA_AQUI'
```

Las **comillas simples** importan: las contraseñas de Neon a veces traen un
`$`, y con comillas dobles PowerShell lo interpreta como el inicio de una
variable y corta la cadena.

**3.** Crea las tablas:

```powershell
npm run db:setup
```

Lo primero que imprime es la línea `Destino:`. **Léela antes de seguir**: tiene
que decir `neon.tech`. Si dice `localhost`, la variable no quedó bien pegada y
estarías borrando tu base local por error.

Debe terminar con 5 categorías, 4 proveedores, 5 clientes y 8 productos.

---

## Parte 5 — Volver a desplegar y comprobar

Las variables de entorno se leen **al desplegar**, y `DATABASE_URL` no existía
cuando se desplegó. Así que hay que repetir el despliegue:

*Deployments* → abre el último → `···` → **Redeploy**

(Un `git push` también sirve: dispara un despliegue nuevo por su cuenta.)

Y la comprobación completa, desde tu terminal:

```powershell
$env:API_URL="https://api-proyecto-formativo.vercel.app"
npm run test:api
```

Son **70 comprobaciones** contra el servidor desplegado: crea, edita y borra
registros de verdad en Neon. Si terminan en 70/0, el despliegue está completo.

---

## Parte 6 — Proceso de ventas de la app móvil

La API ahora también sirve a la app Flutter (`app_movil/`): pedidos, ventas con
factura, pagos/abonos, Wompi y estado de cuenta. Son tres pasos, **en este
orden** (si se sube el código antes de migrar la base, la lista de clientes
falla porque busca tablas que todavía no existen):

**1. Migrar la base de Neon desde tu equipo** (con `DATABASE_URL` en el `.env`,
como en la parte 4). No borra nada: solo agrega tablas.

```bash
npm install
npm run db:movil
```

Crea las tablas nuevas y el usuario administrador (`ADMIN_CORREO` /
`ADMIN_PASSWORD` del `.env`, o `admin@essence.com` / `Essence2026*` si no están).

**2. Variables en Vercel** — *Settings → Environment Variables* (Production):

| Variable | Valor |
|---|---|
| `JWT_SECRETO` | una frase larga inventada por ti (obligatoria: sin ella no hay login) |
| `WOMPI_ENTORNO` | `sandbox` |
| `WOMPI_LLAVE_PUBLICA` | `pub_test_...` (panel de Wompi → Desarrolladores) |
| `WOMPI_LLAVE_PRIVADA` | `prv_test_...` |
| `WOMPI_SECRETO_EVENTOS` | `test_events_...` (sección *Secretos para integración técnica*) |

**3. Subir el código** (`git push`) — o *Redeploy* si ya estaba subido.

**4. URL de eventos en Wompi** — panel de comercios → *Desarrolladores* →
*URL de Eventos* (modo Sandbox):

```
https://api-proyecto-formativo.vercel.app/api/webhooks/wompi
```

Sin esto la app funciona igual, pero los pagos con link hay que confirmarlos a
mano con *Verificar pago Wompi*.

**Comprobar:**

```bash
API_URL=https://api-proyecto-formativo.vercel.app npm run test:movil
```

En PowerShell: `$env:API_URL="https://api-proyecto-formativo.vercel.app"; npm run test:movil`

---

## Antes de la sustentación

**La primera petición es lenta.** Son dos esperas que se suman: Vercel apaga la
función cuando nadie la usa y la primera petición la enciende; Neon suspende la
base por inactividad y la primera consulta la despierta. Juntas pueden ser
varios segundos.

**Abre `/docs` cinco minutos antes** y todo lo demás responde al instante.

**Qué mostrar, en este orden:**

1. **`/docs`** — la documentación interactiva. Se ven las 21 operaciones
   agrupadas por entidad. Es lo que da la primera impresión.
2. **`POST /api/productos`** desde ahí mismo: *Try it out*, ajustas el JSON,
   *Execute*. Sale el `201` con el producto creado y el id que asignó la base.
3. **`GET /api/productos`** — se ve el `JOIN` resuelto: cada producto trae el
   nombre de su categoría y su proveedor, no solo los ids.
4. **`DELETE /api/categorias/1`** — devuelve `409` explicando que la categoría
   tiene productos asociados. Sirve para mostrar que la integridad referencial
   está cuidada y que los errores se explican con palabras.
5. **`npm run test:api`** apuntando al despliegue, si piden ver todo junto.

**Ten a mano el registro del servidor** (`npm run dev` en local mientras corre
la suite): muestra las 20 operaciones con sus códigos HTTP y tiempos de
respuesta en una sola pantalla.

---

## Mantenimiento

**Actualizar la API.** Cada `git push` a `main` despliega solo. No hay que
tocar nada en Vercel.

**Cambiar una variable de entorno.** Vercel **no** vuelve a desplegar solo
después de cambiarla: hay que pedir *Redeploy* a mano.

**Volver a trabajar contra tu base local.** Quita la línea `DATABASE_URL` del
`.env` (o coméntala con `#` delante). Las variables `PG*` vuelven a mandar.

**Rotar la contraseña de la base.** En Neon: *Roles* → el usuario →
*Reset password*. Como Vercel administra esa variable, allá se actualiza sola;
en tu `.env` local hay que pegar la nueva a mano.

---

## Si algo falla

| Síntoma | Causa casi siempre | Solución |
|---|---|---|
| `404: NOT_FOUND` al abrir la URL | Vercel no encontró el punto de entrada | Confirma que `src/server.js` está en el repositorio |
| Una ruta nueva devuelve 404 pero las viejas funcionan | el despliegue aún no termina | espera a que el estado sea *Ready* y recarga con Ctrl+F5 |
| `"baseDeDatos": "sin conexión"` | falta `DATABASE_URL`, o no se hizo *Redeploy* tras agregarla | partes 3 y 5 |
| `too many connections` | se usó la cadena **sin** `-pooler` | cámbiala por la *Pooled connection* |
| La API responde pero las tablas no existen | no se corrió `npm run db:setup` contra Neon | parte 4 |
| La app dice "Falta configurar JWT_SECRETO" | no está la variable en Vercel o falta *Redeploy* | parte 6, paso 2 |
| La lista de clientes da error 500 tras subir el código | no se corrió `npm run db:movil` contra Neon | parte 6, paso 1 |
| "Wompi no está configurado" al crear un link | falta `WOMPI_LLAVE_PRIVADA` en Vercel | parte 6, paso 2 |
| El cliente pagó con el link pero el abono no aparece | la URL de eventos no está en Wompi, o `WOMPI_SECRETO_EVENTOS` no coincide | parte 6, paso 4; mientras tanto *Verificar pago Wompi* |
| `/docs` se queda en "Cargando la documentación…" | el CDN de Swagger no cargó | revisa la consola del navegador (F12); abre `/api/openapi.json` para confirmar que la especificación sí está |
| Cambié una variable y sigue igual | las variables se leen al desplegar | *Redeploy* |
