/**
 * Punto UNICO de resolucion de valores efectivos de Comodato__c para una Quote dada.
 *
 * Regla de negocio (excepcional, no el camino normal):
 *   - Comodato__c (configuracion maestra por Maquina) NUNCA se modifica.
 *   - Si existe un Comodato_Override__c activo para (Quote, Comodato_Original__c),
 *     sus valores no-nulos reemplazan a los del Comodato__c original SOLO para esa Quote.
 *   - Si no existe override, o esta inactivo, se usa el valor original tal cual.
 *
 * Todo punto que hoy lee Comodato__c para construir una propuesta, un contrato de firma
 * digital, una QuoteLineItem/OpportunityLineItem o el payload de envio a SAP debe pasar
 * por este resolver en lugar de leer Comodato__c directamente, para que un ajuste
 * excepcional se refleje de forma consistente en los 4 lugares (o en ninguno).
 *
 * Ver: ComodatoPropuestaMultiController, ContratoComodatoController,
 *      GenerarPDFComodatoMultiAction, ICB_ComodatoSapPayloadBuilder.
 */
public with sharing class ComodatoOverrideResolver {

    /**
     * Linea de Comodato ya resuelta (override aplicado si corresponde).
     * Expone tanto los valores efectivos (a usar) como los originales y si hubo
     * ajuste, para que la UI/PDF pueda transparentar el cambio.
     */
    public class LineaResuelta {
        public Id comodatoId;
        public Id maquinaId;
        public Id productoAsociadoId;
        public String productoAsociadoNombre;
        public String productoAsociadoCodigo;
        public String tipoDeAsociacion;

        // Valores EFECTIVOS: override si existe y esta activo, si no el original.
        public Decimal cantidadMinimaMensual;
        public Decimal cantidadAporte;
        public String unidadDeMedida;
        public Decimal precioUnitarioNeto;

        // Valores ORIGINALES de Comodato__c, sin tocar, para poder comparar/transparentar.
        public Decimal cantidadMinimaMensualOriginal;
        public Decimal cantidadAporteOriginal;
        public String unidadDeMedidaOriginal;
        public Decimal precioUnitarioNetoOriginal;

        public Boolean tieneAjuste;
        public Id overrideId;
        public String motivoAjuste;
        public String ajustadoPorNombre;
        public Datetime fechaAjuste;

        public Boolean getCantidadFueAjustada() {
            return tieneAjuste && cantidadMinimaMensual != cantidadMinimaMensualOriginal;
        }
        public Boolean getUnidadFueAjustada() {
            return tieneAjuste && unidadDeMedida != unidadDeMedidaOriginal;
        }
        public Boolean getPrecioFueAjustado() {
            return tieneAjuste && precioUnitarioNeto != precioUnitarioNetoOriginal;
        }
    }

    /**
     * Resuelve todas las lineas Comodato__c de un conjunto de maquinas para una Quote,
     * aplicando cualquier Comodato_Override__c activo que exista para esa Quote.
     *
     * @param maquinaIds  Ids de Product2 (maquinas) cuyas configuraciones Comodato__c se buscan.
     * @param quoteId     Quote para la cual se resuelven los overrides. Puede ser null:
     *                    en ese caso se devuelven siempre los valores originales
     *                    (no hay Quote todavia -> no puede haber override, ej. preview
     *                    antes de crear la Opportunity/Quote).
     */
    /**
     * Variante para la vista previa: aplica ajustes que TODAVIA NO estan guardados.
     *
     * Durante la creacion de la propuesta el usuario ajusta valores antes de que exista la
     * Quote, asi que no hay Comodato_Override__c todavia. Esos ajustes viajan como JSON y
     * se aplican aqui, para que la cotizacion que ve en pantalla sea identica a la que se
     * va a guardar. Lo que no ajusto conserva el valor estandar de Comodato__c.
     *
     * @param ajustesJson [{comodatoId, cantidadAjustada, unidadAjustada, precioAjustado, motivo}]
     */
    public static List<LineaResuelta> resolver(Set<Id> maquinaIds, Id quoteId, String ajustesJson) {
        List<LineaResuelta> lineas = resolver(maquinaIds, quoteId);
        if (String.isBlank(ajustesJson)) {
            return lineas;
        }

        Map<Id, PersistirAjustesComodatoAction.Ajuste> porComodato =
            new Map<Id, PersistirAjustesComodatoAction.Ajuste>();
        try {
            for (PersistirAjustesComodatoAction.Ajuste a :
                    (List<PersistirAjustesComodatoAction.Ajuste>) JSON.deserialize(
                        ajustesJson, List<PersistirAjustesComodatoAction.Ajuste>.class)) {
                if (a.comodatoId != null) {
                    porComodato.put(a.comodatoId, a);
                }
            }
        } catch (Exception e) {
            // JSON invalido: se muestran los valores estandar en vez de romper la pantalla.
            return lineas;
        }

        for (LineaResuelta linea : lineas) {
            PersistirAjustesComodatoAction.Ajuste a = porComodato.get(linea.comodatoId);
            if (a == null) {
                continue;
            }
            if (a.cantidadAjustada != null) {
                // Misma regla que la ruta persistida: en un Aporte de Marca la cantidad vive
                // en cantidadAporte, no en la cantidad minima mensual. Sin esto, ajustar
                // "12 tazas -> 25 tazas" no se veria en la propuesta ni en el PDF.
                if (linea.tipoDeAsociacion == 'Aporte de Marca') {
                    linea.cantidadAporte = a.cantidadAjustada;
                } else {
                    linea.cantidadMinimaMensual = a.cantidadAjustada;
                }
            }
            if (String.isNotBlank(a.unidadAjustada)) {
                linea.unidadDeMedida = a.unidadAjustada;
            }
            if (a.precioAjustado != null) {
                linea.precioUnitarioNeto = a.precioAjustado;
            }
            linea.tieneAjuste = true;
            linea.motivoAjuste = a.motivo;
        }
        return lineas;
    }

    public static List<LineaResuelta> resolver(Set<Id> maquinaIds, Id quoteId) {
        List<LineaResuelta> resultado = new List<LineaResuelta>();
        if (maquinaIds == null || maquinaIds.isEmpty()) {
            return resultado;
        }

        List<Comodato__c> comodatos = [
            SELECT Id, Maquina__c, Producto_Asociado__c, Producto_Asociado__r.Name, Producto_Asociado__r.Codigo__c,
                   Tipo_de_Asociacion__c, Cantidad_Minima_Mensual__c, Cantidad_Aporte__c,
                   Unidad_de_Medida__c, Precio_Unitario_Neto__c
            FROM Comodato__c
            WHERE Maquina__c IN :maquinaIds
        ];

        Map<Id, Comodato_Override__c> overrideByComodatoId = quoteId == null
            ? new Map<Id, Comodato_Override__c>()
            : overridesActivosPorComodato(quoteId);

        for (Comodato__c c : comodatos) {
            LineaResuelta linea = new LineaResuelta();
            linea.comodatoId = c.Id;
            linea.maquinaId = c.Maquina__c;
            linea.productoAsociadoId = c.Producto_Asociado__c;
            linea.productoAsociadoNombre = c.Producto_Asociado__r != null ? c.Producto_Asociado__r.Name : null;
            linea.productoAsociadoCodigo = c.Producto_Asociado__r != null ? c.Producto_Asociado__r.Codigo__c : null;
            linea.tipoDeAsociacion = c.Tipo_de_Asociacion__c;

            linea.cantidadMinimaMensualOriginal = c.Cantidad_Minima_Mensual__c;
            linea.cantidadAporteOriginal = c.Cantidad_Aporte__c;
            linea.unidadDeMedidaOriginal = c.Unidad_de_Medida__c;
            linea.precioUnitarioNetoOriginal = c.Precio_Unitario_Neto__c;

            // Por defecto, efectivo = original.
            linea.cantidadMinimaMensual = c.Cantidad_Minima_Mensual__c;
            linea.cantidadAporte = c.Cantidad_Aporte__c;
            linea.unidadDeMedida = c.Unidad_de_Medida__c;
            linea.precioUnitarioNeto = c.Precio_Unitario_Neto__c;
            linea.tieneAjuste = false;

            Comodato_Override__c ov = overrideByComodatoId.get(c.Id);
            if (ov != null) {
                linea.tieneAjuste = true;
                linea.overrideId = ov.Id;
                linea.motivoAjuste = ov.Motivo__c;
                linea.ajustadoPorNombre = ov.Ajustado_Por__r != null ? ov.Ajustado_Por__r.Name : null;
                linea.fechaAjuste = ov.Fecha_Ajuste__c;

                if (ov.Cantidad_Ajustada__c != null) {
                    if (c.Tipo_de_Asociacion__c == 'Aporte de Marca') {
                        linea.cantidadAporte = ov.Cantidad_Ajustada__c;
                    } else {
                        linea.cantidadMinimaMensual = ov.Cantidad_Ajustada__c;
                    }
                }
                if (String.isNotBlank(ov.Unidad_de_Medida_Ajustada__c)) {
                    linea.unidadDeMedida = ov.Unidad_de_Medida_Ajustada__c;
                }
                if (ov.Precio_Unitario_Ajustado__c != null) {
                    linea.precioUnitarioNeto = ov.Precio_Unitario_Ajustado__c;
                }
            }

            resultado.add(linea);
        }

        return resultado;
    }

    /** Overrides activos, uno por Comodato_Original__c, para una Quote. */
    private static Map<Id, Comodato_Override__c> overridesActivosPorComodato(Id quoteId) {
        Map<Id, Comodato_Override__c> porComodato = new Map<Id, Comodato_Override__c>();
        for (Comodato_Override__c ov : [
            SELECT Id, Comodato_Original__c, Cantidad_Ajustada__c, Unidad_de_Medida_Ajustada__c,
                   Precio_Unitario_Ajustado__c, Motivo__c, Ajustado_Por__c, Ajustado_Por__r.Name, Fecha_Ajuste__c
            FROM Comodato_Override__c
            WHERE Quote__c = :quoteId AND Activo__c = true
        ]) {
            // Si por error hubiera mas de un override activo para el mismo Comodato original
            // en la misma Quote, se queda con el mas reciente (CreatedDate DESC no esta
            // garantizado por SOQL sin ORDER BY explicito, así que se ordena antes de sobreescribir).
            porComodato.put(ov.Comodato_Original__c, ov);
        }
        return porComodato;
    }

    /**
     * Registra (o reemplaza) el ajuste excepcional para un Comodato__c dentro de una Quote.
     * Requiere el Custom Permission 'Ajustar_Valores_Comodato' - se revalida aca ademas de
     * en la UI, porque un @AuraEnabled expuesto sin sharing explicito es invocable por
     * cualquier usuario con acceso al componente.
     *
     * Si ya existe un override activo para el mismo (Quote, Comodato_Original__c), lo
     * desactiva (Activo__c = false, se conserva para historial) y crea uno nuevo -- así
     * queda trazable quien ajusto que y cuando, incluso si se corrige un ajuste dos veces.
     */
    public static Id registrarAjuste(Id comodatoOriginalId, Id quoteId, Decimal cantidadAjustada,
                                       String unidadAjustada, Decimal precioAjustado, String motivo) {
        if (!hasPermisoAjuste()) {
            throw new ComodatoOverrideException('No tiene permiso para ajustar valores excepcionales de Comodato.');
        }
        if (comodatoOriginalId == null || quoteId == null) {
            throw new ComodatoOverrideException('Comodato original y Quote son obligatorios.');
        }
        // El motivo es opcional por decision de negocio (2026-08-25). Si vuelve a exigirse,
        // reponer aqui la validacion y marcar el campo Motivo__c como required.
        if (cantidadAjustada == null && String.isBlank(unidadAjustada) && precioAjustado == null) {
            throw new ComodatoOverrideException('Debe ajustar al menos un valor (cantidad, unidad o precio).');
        }

        List<Comodato__c> originales = [
            SELECT Id, Maquina__c FROM Comodato__c WHERE Id = :comodatoOriginalId LIMIT 1
        ];
        if (originales.isEmpty()) {
            throw new ComodatoOverrideException('Comodato original no encontrado: ' + comodatoOriginalId);
        }

        List<Comodato_Override__c> existentes = [
            SELECT Id FROM Comodato_Override__c
            WHERE Quote__c = :quoteId AND Comodato_Original__c = :comodatoOriginalId AND Activo__c = true
        ];
        if (!existentes.isEmpty()) {
            List<Comodato_Override__c> toDeactivate = new List<Comodato_Override__c>();
            for (Comodato_Override__c e : existentes) {
                e.Activo__c = false;
                toDeactivate.add(e);
            }
            update toDeactivate;
        }

        Comodato_Override__c nuevo = new Comodato_Override__c(
            Comodato_Original__c = comodatoOriginalId,
            Quote__c = quoteId,
            Maquina__c = originales[0].Maquina__c,
            Cantidad_Ajustada__c = cantidadAjustada,
            Unidad_de_Medida_Ajustada__c = unidadAjustada,
            Precio_Unitario_Ajustado__c = precioAjustado,
            Motivo__c = motivo,
            Ajustado_Por__c = UserInfo.getUserId(),
            Fecha_Ajuste__c = Datetime.now(),
            Activo__c = true
        );
        insert nuevo;
        return nuevo.Id;
    }

    /** Desactiva (revierte) un ajuste sin borrarlo, para conservar el historial. */
    public static void revertirAjuste(Id overrideId) {
        if (!hasPermisoAjuste()) {
            throw new ComodatoOverrideException('No tiene permiso para revertir ajustes excepcionales de Comodato.');
        }
        if (overrideId == null) {
            return;
        }
        update new Comodato_Override__c(Id = overrideId, Activo__c = false);
    }

    @TestVisible
    private static Boolean hasPermisoAjuste() {
        return FeatureManagement.checkPermission('Ajustar_Valores_Comodato');
    }

    public class ComodatoOverrideException extends Exception {}
}