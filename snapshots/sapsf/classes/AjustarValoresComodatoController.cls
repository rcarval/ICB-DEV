/**
 * Controller @AuraEnabled para el LWC ajustarValoresComodato.
 * Expone el ajuste EXCEPCIONAL de valores de Comodato__c (cantidad, unidad, precio)
 * para una Quote puntual, sin modificar nunca la configuracion maestra.
 *
 * Requiere el Custom Permission 'Ajustar_Valores_Comodato' (asignado hoy solo via el
 * Permission Set ADMIN_COMODATO). El LWC ya oculta la opcion si el usuario no tiene el
 * permiso, pero la validacion real esta en ComodatoOverrideResolver -- nunca confiar
 * solo en que la UI no muestre el boton.
 */
public with sharing class AjustarValoresComodatoController {

    public class LineaAjusteDto {
        @AuraEnabled public Id comodatoId;
        @AuraEnabled public Id maquinaId;
        @AuraEnabled public String maquinaNombre;
        @AuraEnabled public Id productoAsociadoId;
        @AuraEnabled public String productoAsociadoNombre;
        @AuraEnabled public String tipoDeAsociacion;

        @AuraEnabled public Decimal cantidadOriginal;
        @AuraEnabled public String unidadOriginal;
        @AuraEnabled public Decimal precioOriginal;

        @AuraEnabled public Decimal cantidadEfectiva;
        @AuraEnabled public String unidadEfectiva;
        @AuraEnabled public Decimal precioEfectivo;

        @AuraEnabled public Boolean tieneAjuste;
        @AuraEnabled public Id overrideId;
        @AuraEnabled public String motivoAjuste;
        @AuraEnabled public String ajustadoPorNombre;
    }

    /**
     * Trae, por cada maquina seleccionada, sus lineas Comodato__c (Comodatos_Maquina__r)
     * ya resueltas (con override activo aplicado si existe para la Quote indicada).
     * quoteId puede ser null si todavia no existe la Quote (ej. antes del primer guardado);
     * en ese caso siempre se devuelven los valores originales, sin overrides.
     */
    @AuraEnabled(cacheable=true)
    public static List<LineaAjusteDto> obtenerLineasParaAjuste(List<Id> maquinaIds, Id quoteId) {
        if (maquinaIds == null || maquinaIds.isEmpty()) {
            return new List<LineaAjusteDto>();
        }
        Set<Id> ids = new Set<Id>(maquinaIds);

        Map<Id, String> nombreMaquinaPorId = new Map<Id, String>();
        for (Product2 p : [SELECT Id, Name FROM Product2 WHERE Id IN :ids]) {
            nombreMaquinaPorId.put(p.Id, p.Name);
        }

        List<ComodatoOverrideResolver.LineaResuelta> resueltas = ComodatoOverrideResolver.resolver(ids, quoteId);

        List<LineaAjusteDto> resultado = new List<LineaAjusteDto>();
        for (ComodatoOverrideResolver.LineaResuelta r : resueltas) {
            // Solo interesan las lineas con producto asociado (insumo/servicio/aporte);
            // la maquina en si (Producto_Asociado__c = null) no es ajustable aca.
            if (r.productoAsociadoId == null) {
                continue;
            }
            LineaAjusteDto dto = new LineaAjusteDto();
            dto.comodatoId = r.comodatoId;
            dto.maquinaId = r.maquinaId;
            dto.maquinaNombre = nombreMaquinaPorId.get(r.maquinaId);
            dto.productoAsociadoId = r.productoAsociadoId;
            dto.productoAsociadoNombre = r.productoAsociadoNombre;
            dto.tipoDeAsociacion = r.tipoDeAsociacion;

            Boolean esAporte = r.tipoDeAsociacion == 'Aporte de Marca';
            dto.cantidadOriginal = esAporte ? r.cantidadAporteOriginal : r.cantidadMinimaMensualOriginal;
            dto.unidadOriginal = r.unidadDeMedidaOriginal;
            dto.precioOriginal = r.precioUnitarioNetoOriginal;

            dto.cantidadEfectiva = esAporte ? r.cantidadAporte : r.cantidadMinimaMensual;
            dto.unidadEfectiva = r.unidadDeMedida;
            dto.precioEfectivo = r.precioUnitarioNeto;

            dto.tieneAjuste = r.tieneAjuste;
            dto.overrideId = r.overrideId;
            dto.motivoAjuste = r.motivoAjuste;
            dto.ajustadoPorNombre = r.ajustadoPorNombre;

            resultado.add(dto);
        }
        return resultado;
    }

    /** Guarda (o reemplaza) el ajuste excepcional de una linea para una Quote. */
    @AuraEnabled
    public static Id guardarAjuste(Id comodatoId, Id quoteId, Decimal cantidadAjustada,
                                     String unidadAjustada, Decimal precioAjustado, String motivo) {
        try {
            return ComodatoOverrideResolver.registrarAjuste(
                comodatoId, quoteId, cantidadAjustada, unidadAjustada, precioAjustado, motivo
            );
        } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Revierte (desactiva) un ajuste excepcional, volviendo al valor original de Comodato__c. */
    @AuraEnabled
    public static void revertirAjuste(Id overrideId) {
        try {
            ComodatoOverrideResolver.revertirAjuste(overrideId);
        } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Expone al LWC si el usuario actual tiene el Custom Permission de ajuste. */
    @AuraEnabled(cacheable=true)
    public static Boolean puedeAjustarValores() {
        return FeatureManagement.checkPermission('Ajustar_Valores_Comodato');
    }
}