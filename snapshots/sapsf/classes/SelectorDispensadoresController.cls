/**
 * Controller del selector de dispensadores (LWC selectorDispensadores).
 *
 * Diferencia central con el selector de cafe: alli el asesor elige la maquina y los insumos
 * quedan implicitos en la configuracion. En dispensadores la pregunta llega al reves --el
 * cliente quiere ofrecer ketchup y de ahi se deduce el equipo-- asi que cada dispensador se
 * devuelve YA RESUELTO con los insumos, aportes y servicios que trae asociados. Eso permite
 * mostrarlos en pantalla y buscar por insumo.
 *
 * No comparte codigo con el flujo de cafe: es una clase aparte para que ningun cambio aqui
 * pueda afectar ese proceso, que esta en produccion.
 */
public with sharing class SelectorDispensadoresController {

    /** Valor de Product2.Tipo_Equipo__c que identifica a un dispensador. */
    private static final String TIPO_DISPENSADOR = 'Dispensador';

    /** Linea asociada a un dispensador: insumo mensual, aporte de marca o servicio. */
    public class LineaDto {
        @AuraEnabled public Id productoId;
        @AuraEnabled public String nombre;
        @AuraEnabled public String tipo;         // Insumo Mensual | Aporte de Marca | Servicio
        @AuraEnabled public Decimal cantidad;
        @AuraEnabled public String unidad;
        @AuraEnabled public Decimal precio;
    }

    public class DispensadorDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String nombre;
        @AuraEnabled public String codigo;
        @AuraEnabled public String descripcion;
        @AuraEnabled public String imagen;
        @AuraEnabled public String tipoNegocio;

        /** Lineas separadas por tipo, para poder presentarlas distinto en pantalla. */
        @AuraEnabled public List<LineaDto> insumos;
        @AuraEnabled public List<LineaDto> aportes;
        @AuraEnabled public List<LineaDto> servicios;

        /**
         * Un dispensador sin configuracion de comodato no puede proponerse: el resolver no
         * tendria de donde sacar cantidades ni precios. Se devuelve igual, marcado, para que
         * la pantalla lo muestre como no disponible en vez de ocultarlo sin explicacion.
         */
        @AuraEnabled public Boolean configurado;

        /** Texto plano con los insumos, para que el LWC pueda buscar sin recorrer listas. */
        @AuraEnabled public String textoBusqueda;
    }

    /**
     * Dispensadores con entrada activa en la lista de precios indicada, ya resueltos con sus
     * lineas de comodato.
     *
     * @param pricebookId Lista de precios del flujo. Si viene vacia se devuelven todos los
     *                    dispensadores activos, para no dejar la pantalla en blanco.
     */
    @AuraEnabled(cacheable=true)
    public static List<DispensadorDto> obtenerDispensadores(String pricebookId) {
        Map<Id, Product2> porId = new Map<Id, Product2>(consultarDispensadores(pricebookId));
        if (porId.isEmpty()) {
            return new List<DispensadorDto>();
        }

        // Una sola consulta para todas las configuraciones: nunca dentro del loop.
        Map<Id, List<LineaDto>> lineasPorDispensador = new Map<Id, List<LineaDto>>();
        for (Comodato__c c : [
            SELECT Maquina__c, Producto_Asociado__c, Producto_Asociado__r.Name,
                   Tipo_de_Asociacion__c, Cantidad_Minima_Mensual__c, Cantidad_Aporte__c,
                   Unidad_de_Medida__c, Precio_Unitario_Neto__c
            FROM Comodato__c
            WHERE Maquina__c IN :porId.keySet() AND Producto_Asociado__c != null
            ORDER BY Tipo_de_Asociacion__c, Producto_Asociado__r.Name
        ]) {
            LineaDto l = new LineaDto();
            l.productoId = c.Producto_Asociado__c;
            l.nombre = c.Producto_Asociado__r.Name;
            l.tipo = c.Tipo_de_Asociacion__c;
            // En un aporte de marca la cantidad vive en Cantidad_Aporte__c, no en la mensual.
            l.cantidad = (c.Tipo_de_Asociacion__c == 'Aporte de Marca')
                ? c.Cantidad_Aporte__c
                : c.Cantidad_Minima_Mensual__c;
            l.unidad = c.Unidad_de_Medida__c;
            l.precio = c.Precio_Unitario_Neto__c;

            if (!lineasPorDispensador.containsKey(c.Maquina__c)) {
                lineasPorDispensador.put(c.Maquina__c, new List<LineaDto>());
            }
            lineasPorDispensador.get(c.Maquina__c).add(l);
        }

        List<DispensadorDto> salida = new List<DispensadorDto>();
        for (Product2 p : porId.values()) {
            salida.add(armarDto(p, lineasPorDispensador.get(p.Id)));
        }
        return salida;
    }

    private static List<Product2> consultarDispensadores(String pricebookId) {
        if (String.isBlank(pricebookId)) {
            return [
                SELECT Id, Name, Codigo__c, Description, Descripci_n_Larga__c,
                       Imagen_Propuesta__c, Tipo_de_Negocio_Recomendado__c
                FROM Product2
                WHERE Tipo_Equipo__c = :TIPO_DISPENSADOR AND IsActive = true
                ORDER BY Name ASC
            ];
        }

        Id pbId = (Id) pricebookId;
        List<Product2> prods = new List<Product2>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, Product2.Name, Product2.Codigo__c, Product2.Description,
                   Product2.Descripci_n_Larga__c, Product2.Imagen_Propuesta__c,
                   Product2.Tipo_de_Negocio_Recomendado__c
            FROM PricebookEntry
            WHERE Pricebook2Id = :pbId
              AND IsActive = true
              AND Product2.IsActive = true
              AND Product2.Tipo_Equipo__c = :TIPO_DISPENSADOR
            ORDER BY Product2.Name ASC
        ]) {
            prods.add(pbe.Product2);
        }
        return prods;
    }

    private static DispensadorDto armarDto(Product2 p, List<LineaDto> lineas) {
        DispensadorDto d = new DispensadorDto();
        d.id = p.Id;
        d.nombre = p.Name;
        d.codigo = p.Codigo__c;
        d.descripcion = String.isNotBlank(p.Descripci_n_Larga__c) ? p.Descripci_n_Larga__c : p.Description;
        d.imagen = p.Imagen_Propuesta__c;
        d.tipoNegocio = p.Tipo_de_Negocio_Recomendado__c;
        d.insumos = new List<LineaDto>();
        d.aportes = new List<LineaDto>();
        d.servicios = new List<LineaDto>();

        List<String> terminos = new List<String>{ p.Name == null ? '' : p.Name.toLowerCase() };

        if (lineas != null) {
            for (LineaDto l : lineas) {
                if (l.tipo == 'Insumo Mensual') {
                    d.insumos.add(l);
                } else if (l.tipo == 'Aporte de Marca') {
                    d.aportes.add(l);
                } else {
                    d.servicios.add(l);
                }
                if (String.isNotBlank(l.nombre)) {
                    terminos.add(l.nombre.toLowerCase());
                }
            }
        }

        // Se considera configurado si tiene al menos un insumo mensual: es lo que sostiene
        // el compromiso de compra y lo que el resolver necesita para armar la propuesta.
        d.configurado = !d.insumos.isEmpty();
        d.textoBusqueda = String.join(terminos, ' ');
        return d;
    }
}