# Despliegue

Guía para publicar esta API en internet: la base de datos en **Neon**
(PostgreSQL administrado, plan gratuito) y la API en **Vercel**.

Al terminar tendrás una URL pública tipo
`https://api-proyecto-formativo.vercel.app/api/health` que se puede abrir en
cualquier navegador y mostrar en la sustentación.

---

## Parte 1 — La base de datos en Neon

### 1.1 Crear el proyecto

1. Entra a <https://neon.com> y crea la cuenta (puedes usar tu GitHub).
2. **Create project**:
   - Name: `essence-api`
   - Region: la más cercana a Colombia (normalmente `AWS us-east-1` o `us-east-2`)
3. Al crear el proyecto te muestra la cadena de conexión. **Cópiala.**

Se ve así:

```
postgresql://usuario:clave@ep-algo-nombre-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require
```

Fíjate en el `-pooler` del nombre del servidor. **Usa la que lo tenga** (en la
pantalla de Neon aparece como *Pooled connection*). Esa cadena reparte las
conexiones entre varias peticiones; sin ella, una API en la nube se queda sin
cupo de conexiones apenas la usan dos o tres personas a la vez.

### 1.2 Crear las tablas desde tu equipo

En la nube no hay pgAdmin para abrir el `.sql` y darle *ejecutar*. Se manda
desde la terminal con el mismo comando de siempre.

En tu `.env`, comenta las variables locales y agrega la cadena de Neon:

```env
# PGHOST=localhost
# PGPORT=5432
# PGDATABASE=essence_api
# PGUSER=postgres
# PGPASSWORD=tu_clave

DATABASE_URL=postgresql://usuario:clave@ep-algo-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require
```

Y corre:

```bash
npm run db:setup
```

Debe terminar mostrando 5 categorías, 4 proveedores, 5 clientes y 8 productos.

### 1.3 Comprobar

```bash
npm run dev
npm run test:api
```

Las 62 pruebas deben pasar, ahora contra la base que está en la nube. Con eso
ya sabes que el esquema quedó bien antes de meterte con el despliegue.

**Cuando termines, devuelve el `.env` a como estaba** para seguir trabajando
contra tu PostgreSQL local. La cadena de Neon la vas a necesitar otra vez en
la parte 2, así que guárdala aparte.

---

## Parte 2 — La API en Vercel

### 2.1 Subir el proyecto a GitHub

Vercel despliega desde un repositorio, así que primero hay que crear uno.

```bash
git init
git add .
git commit -m "API del proyecto formativo: CRUD de las cuatro entidades"
```

Crea un repositorio vacío en GitHub (sin README, sin .gitignore) y conéctalo:

```bash
git remote add origin https://github.com/tu-usuario/api-proyecto-formativo.git
git branch -M main
git push -u origin main
```

Antes del `push`, corre `git status` y confirma que **`.env` no aparece** en la
lista. El `.gitignore` ya lo excluye, pero ahí va la contraseña de tu base de
datos y vale la pena mirarlo con los ojos.

### 2.2 Crear el proyecto en Vercel

1. Entra a <https://vercel.com> y crea la cuenta con GitHub.
2. **Add New → Project** e importa el repositorio que acabas de subir.
3. Vercel reconoce Express solo. No hace falta tocar Build Command ni Output
   Directory: déjalos vacíos.

Como esta API está en la raíz del repositorio, **no hay que configurar Root
Directory**. (Eso solo hace falta cuando la API vive dentro de una subcarpeta.)

### 2.3 Variables de entorno

En la misma pantalla, sección **Environment Variables**:

| Nombre | Valor |
|---|---|
| `DATABASE_URL` | la cadena *pooled* de Neon, completa |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | `*` |

`CORS_ORIGINS=*` permite que cualquier página llame a la API. Para una entrega
académica está bien y facilita las pruebas; si esto fuera un sistema real,
habría que poner el dominio concreto del frontend.

### 2.4 Desplegar y probar

Dale **Deploy** y espera. Cuando termine:

- `https://tu-proyecto.vercel.app/` → la portada con la lista de recursos
- `https://tu-proyecto.vercel.app/api/health` → debe decir `"baseDeDatos": "conectada"`
- `https://tu-proyecto.vercel.app/api/productos` → los ocho productos

Y la prueba completa contra el despliegue, desde tu terminal:

```bash
API_URL=https://tu-proyecto.vercel.app npm run test:api
```

En PowerShell la variable se pasa distinto:

```powershell
$env:API_URL="https://tu-proyecto.vercel.app"; npm run test:api
```

Si pasan las 62, la entrega está lista.

---

## Antes de la sustentación

**La primera petición es lenta.** Son dos esperas que se suman: Vercel apaga la
función cuando nadie la usa y la primera petición la enciende; Neon suspende la
base por inactividad y la primera consulta la despierta. Juntas pueden ser
varios segundos.

**Abre `/api/health` cinco minutos antes de sustentar** y todo lo demás
responde al instante.

**Ten a mano estas tres pestañas:**

1. `https://tu-proyecto.vercel.app/api/productos` — se ve el JSON con el JOIN
   resuelto, mostrando el nombre de la categoría y del proveedor.
2. `https://tu-proyecto.vercel.app/api/productos?stockBajo=1` — un filtro real
   funcionando.
3. `https://tu-proyecto.vercel.app/api/productos/999999` — el 404 con su
   mensaje, para mostrar que los errores están manejados.

Y si te piden ver las operaciones de escritura, `npm run test:api` apuntando al
despliegue las recorre todas en vivo, incluidos los casos que deben fallar.

---

## Si algo falla

| Síntoma | Causa casi siempre | Solución |
|---|---|---|
| `404: NOT_FOUND` al abrir la URL | Vercel no encontró el punto de entrada | Confirma que `src/server.js` existe y que el repositorio subió completo |
| `"baseDeDatos": "sin conexión"` | `DATABASE_URL` mal copiada o sin `?sslmode=require` | Vuelve a copiarla de Neon, completa |
| `too many connections` | usaste la cadena **sin** `-pooler` | Cámbiala por la *Pooled connection* |
| La API responde pero las tablas no existen | no corriste `npm run db:setup` contra Neon | Parte 1.2 |
| Cambié una variable y sigue igual | las variables se leen al desplegar | Deployments → ⋯ → *Redeploy* |

Un detalle de Vercel: cambiar una variable de entorno **no** vuelve a desplegar
solo. Siempre hay que pedir *Redeploy* después.
