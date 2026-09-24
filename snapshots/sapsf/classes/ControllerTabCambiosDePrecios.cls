/**
 * Controlador del LWC cambiosDePrecios: entrega Información Producto paginada,
 * ordenada por última modificación descendente y filtrada por zona, categoría, familia,
 * marca, estado, texto de búsqueda (código o descripción) y rango de fechas de última modificación.
 * También entrega los valores únicos de cada filtro, al estilo del autofiltro de Excel.
 * La paginación es por cursor (LastModifiedDate + Id) porque OFFSET no admite más de 2000 filas.
 * Versión: v4 - 2026-09-24
 */
public with sharing class ControllerTabCambiosDePrecios {

    private static final Integer TAMANO_PAGINA_DEFECTO = 50;
    private static final Integer TAMANO_PAGINA_MAXIMO = 200;

    private static final String CAMPOS_CONSULTA =
        'Id, Producto__c, Producto__r.Name, Category__c, Jefe_Categoria__c, Categoria__c, UMB__c, Estado__c, Codigo__c, UMV__c,' +
        'Precio__c, Precio_UN__c, FEE_Apertura__c,Descripcion_UMV__c, Ventas_Por_Unidad__c, Precio_UN_FEE__c, Familia__c, ' +
        'Descuento_Autonomo__c, Producto_Foco__c, tipo__c, Zona__c, Marca__c, LastModifiedDate';

    private static final String CAMPOS_FILTRO = 'Categoria__c, Familia__c, Marca__c, Estado__c';

    /**
     * Devuelve una página de Información Producto.
     * @param tamanoPagina cantidad de registros por página (se limita a TAMANO_PAGINA_MAXIMO)
     * @param zonas zonas a filtrar; vacía o nula devuelve todas
     * @param categoria valor exacto de Categoria__c; vacío no filtra
     * @param familia valor exacto de Familia__c; vacío no filtra
     * @param marca valor exacto de Marca__c; vacío no filtra
     * @param estado valor exacto de Estado__c; vacío no filtra
     * @param textoBusqueda texto contenido en el código o la descripción del producto; vacío no filtra
     * @param fechaDesde primer día (incluido) de última modificación; nulo no limita
     * @param fechaHasta último día (incluido) de última modificación; nulo no limita
     * @param cursorFecha LastModifiedDate del último registro de la página anterior; nulo para la primera página
     * @param cursorId Id del último registro de la página anterior; nulo para la primera página
     */
    @AuraEnabled
    public static ProductosPaginadosDTO getInformacionProductos(
        Integer tamanoPagina,
        List<String> zonas,
        String categoria,
        String familia,
        String marca,
        String estado,
        String textoBusqueda,
        Date fechaDesde,
        Date fechaHasta,
        Datetime cursorFecha,
        Id cursorId
    ) {
        try {
            Map<String, Object> bindsConteo = new Map<String, Object>();
            List<String> condicionesConteo = new List<String>();

            agregarFiltroZona(condicionesConteo, bindsConteo, zonas);
            agregarFiltroBusqueda(condicionesConteo, bindsConteo, textoBusqueda);
            agregarFiltroFechas(condicionesConteo, bindsConteo, fechaDesde, fechaHasta);
            agregarFiltroIgual(condicionesConteo, bindsConteo, 'Categoria__c', 'categoria', categoria);
            agregarFiltroIgual(condicionesConteo, bindsConteo, 'Familia__c', 'familia', familia);
            agregarFiltroIgual(condicionesConteo, bindsConteo, 'Marca__c', 'marca', marca);
            agregarFiltroIgual(condicionesConteo, bindsConteo, 'Estado__c', 'estado', estado);

            Map<String, Object> bindsPagina = new Map<String, Object>(bindsConteo);
            List<String> condicionesPagina = new List<String>(condicionesConteo);

            bindsPagina.put('limite', normalizarTamanoPagina(tamanoPagina));

            if (cursorFecha != null && cursorId != null) {
                bindsPagina.put('cursorFecha', cursorFecha);
                bindsPagina.put('cursorId', cursorId);
                condicionesPagina.add(
                    '(LastModifiedDate < :cursorFecha OR (LastModifiedDate = :cursorFecha AND Id < :cursorId))'
                );
            }

            String consultaPagina =
                'SELECT ' + CAMPOS_CONSULTA +
                ' FROM Informacion_Producto__c' +
                construirWhere(condicionesPagina) +
                ' ORDER BY LastModifiedDate DESC, Id DESC LIMIT :limite';

            String consultaConteo =
                'SELECT COUNT() FROM Informacion_Producto__c' +
                construirWhere(condicionesConteo);

            ProductosPaginadosDTO resultado = new ProductosPaginadosDTO();
            resultado.registros = Database.queryWithBinds(consultaPagina, bindsPagina, AccessLevel.SYSTEM_MODE);
            resultado.totalRegistros = Database.countQueryWithBinds(consultaConteo, bindsConteo, AccessLevel.SYSTEM_MODE);

            return resultado;
        } catch (Exception e) {
            throw new AuraHandledException('Error obteniendo productos: ' + e.getMessage());
        }
    }

    /**
     * Devuelve los valores únicos de Categoría, Familia, Marca y Estado, ordenados alfabéticamente.
     * Igual que el autofiltro de Excel, la lista de cada filtro considera los demás filtros
     * seleccionados, pero no el propio (así se puede cambiar de valor sin limpiar primero).
     * Zona, búsqueda y rango de fechas se aplican a todas las listas.
     * Los registros se recorren con un QueryLocator para no cargarlos todos en el heap;
     * el límite de 50.000 filas consultadas por transacción sigue aplicando.
     */
    @AuraEnabled
    public static OpcionesFiltrosDTO getOpcionesFiltros(
        List<String> zonas,
        String categoria,
        String familia,
        String marca,
        String estado,
        String textoBusqueda,
        Date fechaDesde,
        Date fechaHasta
    ) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> condiciones = new List<String>();

            agregarFiltroZona(condiciones, binds, zonas);
            agregarFiltroBusqueda(condiciones, binds, textoBusqueda);
            agregarFiltroFechas(condiciones, binds, fechaDesde, fechaHasta);

            String consulta =
                'SELECT ' + CAMPOS_FILTRO +
                ' FROM Informacion_Producto__c' +
                construirWhere(condiciones);

            Set<String> categorias = new Set<String>();
            Set<String> familias = new Set<String>();
            Set<String> marcas = new Set<String>();
            Set<String> estados = new Set<String>();

            Database.QueryLocatorIterator iterador =
                Database.getQueryLocatorWithBinds(consulta, binds, AccessLevel.SYSTEM_MODE).iterator();

            while (iterador.hasNext()) {
                Informacion_Producto__c registro = (Informacion_Producto__c) iterador.next();

                Boolean cumpleCategoria = cumpleFiltro(registro.Categoria__c, categoria);
                Boolean cumpleFamilia = cumpleFiltro(registro.Familia__c, familia);
                Boolean cumpleMarca = cumpleFiltro(registro.Marca__c, marca);
                Boolean cumpleEstado = cumpleFiltro(registro.Estado__c, estado);

                if (cumpleFamilia && cumpleMarca && cumpleEstado) {
                    agregarValor(categorias, registro.Categoria__c);
                }
                if (cumpleCategoria && cumpleMarca && cumpleEstado) {
                    agregarValor(familias, registro.Familia__c);
                }
                if (cumpleCategoria && cumpleFamilia && cumpleEstado) {
                    agregarValor(marcas, registro.Marca__c);
                }
                if (cumpleCategoria && cumpleFamilia && cumpleMarca) {
                    agregarValor(estados, registro.Estado__c);
                }
            }

            OpcionesFiltrosDTO resultado = new OpcionesFiltrosDTO();
            resultado.categorias = ordenar(categorias);
            resultado.familias = ordenar(familias);
            resultado.marcas = ordenar(marcas);
            resultado.estados = ordenar(estados);

            return resultado;
        } catch (Exception e) {
            throw new AuraHandledException('Error obteniendo opciones de filtros: ' + e.getMessage());
        }
    }

    private static void agregarFiltroZona(List<String> condiciones, Map<String, Object> binds, List<String> zonas) {
        if (zonas != null && !zonas.isEmpty()) {
            binds.put('zonas', zonas);
            condiciones.add('Zona__c IN :zonas');
        }
    }

    private static void agregarFiltroBusqueda(List<String> condiciones, Map<String, Object> binds, String textoBusqueda) {
        if (String.isNotBlank(textoBusqueda)) {
            binds.put('busqueda', '%' + textoBusqueda.trim() + '%');
            condiciones.add('(Codigo__c LIKE :busqueda OR Producto__r.Name LIKE :busqueda)');
        }
    }

    // Los días se interpretan en la zona horaria del usuario; "hasta" incluye el día completo
    private static void agregarFiltroFechas(
        List<String> condiciones,
        Map<String, Object> binds,
        Date fechaDesde,
        Date fechaHasta
    ) {
        if (fechaDesde != null) {
            binds.put('fechaDesde', Datetime.newInstance(fechaDesde, Time.newInstance(0, 0, 0, 0)));
            condiciones.add('LastModifiedDate >= :fechaDesde');
        }
        if (fechaHasta != null) {
            binds.put('fechaHastaExclusiva', Datetime.newInstance(fechaHasta.addDays(1), Time.newInstance(0, 0, 0, 0)));
            condiciones.add('LastModifiedDate < :fechaHastaExclusiva');
        }
    }

    // El campo viene de una constante del código; el valor del usuario siempre va como bind
    private static void agregarFiltroIgual(
        List<String> condiciones,
        Map<String, Object> binds,
        String campo,
        String nombreBind,
        String valor
    ) {
        if (String.isNotBlank(valor)) {
            binds.put(nombreBind, valor);
            condiciones.add(campo + ' = :' + nombreBind);
        }
    }

    private static Boolean cumpleFiltro(String valorRegistro, String valorFiltro) {
        return String.isBlank(valorFiltro) || valorRegistro == valorFiltro;
    }

    private static void agregarValor(Set<String> valores, String valor) {
        if (String.isNotBlank(valor)) {
            valores.add(valor);
        }
    }

    private static List<String> ordenar(Set<String> valores) {
        List<String> lista = new List<String>(valores);
        lista.sort();
        return lista;
    }

    private static Integer normalizarTamanoPagina(Integer tamanoPagina) {
        if (tamanoPagina == null || tamanoPagina <= 0) {
            return TAMANO_PAGINA_DEFECTO;
        }
        return Math.min(tamanoPagina, TAMANO_PAGINA_MAXIMO);
    }

    private static String construirWhere(List<String> condiciones) {
        return condiciones.isEmpty() ? '' : ' WHERE ' + String.join(condiciones, ' AND ');
    }

    /**
     * Página de resultados con el total de registros que cumplen los filtros.
     */
    public class ProductosPaginadosDTO {
        @AuraEnabled public List<Informacion_Producto__c> registros;
        @AuraEnabled public Integer totalRegistros;
    }

    /**
     * Valores únicos disponibles para cada lista de filtro.
     */
    public class OpcionesFiltrosDTO {
        @AuraEnabled public List<String> categorias;
        @AuraEnabled public List<String> familias;
        @AuraEnabled public List<String> marcas;
        @AuraEnabled public List<String> estados;
    }
}