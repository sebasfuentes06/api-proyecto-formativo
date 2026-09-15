/**
 * Ayudas para armar los listados: búsqueda, orden y paginación.
 *
 * Las cuatro entidades comparten estos parámetros, así que la lógica vive
 * aquí una sola vez en lugar de estar copiada en cada modelo.
 */

/**
 * Traduce ?page= y ?limit= a LIMIT/OFFSET.
 *
 * Se recortan los valores a propósito: si alguien pide ?limit=999999 no debe
 * poder traerse la tabla entera de un golpe.
 */
function paginacion({ page, limit } = {}) {
  const pagina = Math.max(1, Number(page) || 1);
  const porPagina = Math.min(100, Math.max(1, Number(limit) || 10));
  return { pagina, porPagina, offset: (pagina - 1) * porPagina };
}

/**
 * Decide por cuál columna se ordena.
 *
 * El nombre de una columna NO se puede mandar como parámetro ($1) en SQL:
 * solo los valores admiten eso. Como hay que pegarlo dentro del texto de la
 * consulta, se valida contra una lista blanca. Si llega cualquier otra cosa
 * —incluido un intento de inyección— se ignora y se usa la de por defecto.
 */
function orden(sortBy, permitidas, porDefecto, sortDir) {
  const columna = permitidas.includes(sortBy) ? sortBy : porDefecto;
  const direccion = String(sortDir).toLowerCase() === "desc" ? "DESC" : "ASC";
  return { columna, direccion };
}

/**
 * Convierte ?status=active|inactive|all al booleano de la columna `estado`.
 * Devuelve null cuando no hay que filtrar.
 */
function filtroEstado(status) {
  if (status === "active") return true;
  if (status === "inactive") return false;
  return null;
}

/** Arma la respuesta de un listado, igual para las cuatro entidades. */
function respuestaListado(filas, total, { pagina, porPagina }) {
  return {
    ok: true,
    datos: filas,
    paginacion: {
      total,
      pagina,
      porPagina,
      totalPaginas: Math.max(1, Math.ceil(total / porPagina))
    }
  };
}

export { paginacion, orden, filtroEstado, respuestaListado };
