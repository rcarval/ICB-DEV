/**
 * @description Obtiene los detalles de producto (Detalle_Factura__c) de una factura para el
 *              flujo "Caso - Ingreso de Caso mejorado".
 *              Se expone de dos formas:
 *                - @InvocableMethod: para usarse como Acción dentro de un Flow.
 *                - @AuraEnabled: consumido por el LWC seidorDetalleFacturaSelector.
 *
 *              Lógica de resolución de la factura:
 *                1. Si viene facturaId, se usa esa factura.
 *                2. Si no, y viene caseId, se usa Case.Factura__c.
 *                3. Si viene accountId, la factura debe pertenecer a esa cuenta
 *                   (Cliente__c, Sucursal__c, padre de la sucursal o padre del cliente).
 *                4. Si viene sucursalId, la factura debe pertenecer a esa sucursal
 *                   (Sucursal__c o Cliente__c).
 *              Si no se puede resolver una factura válida, se informa un mensaje de error.
 *
 *              Seguridad: la clase respeta el sharing del usuario y elimina los campos sin
 *              permiso de lectura (Security.stripInaccessible) en lugar de fallar.
 */
public with sharing class seidor_DetalleFacturaSelector {

    @TestVisible
    private static final String MSG_SIN_FACTURA = 'No se indicó una factura (ni un Caso con factura asociada).';
    @TestVisible
    private static final String MSG_FACTURA_NO_EXISTE = 'La factura indicada no existe o no tiene acceso a ella.';
    @TestVisible
    private static final String MSG_FACTURA_OTRA_CUENTA = 'La factura seleccionada no pertenece a la cuenta indicada.';
    @TestVisible
    private static final String MSG_FACTURA_OTRA_SUCURSAL = 'La factura seleccionada no pertenece a la sucursal indicada.';

    // ---------------------------------------------------------------------------------
    // Invocable (Flow)
    // ---------------------------------------------------------------------------------

    public class Request {
        @InvocableVariable(label='Id del Caso' description='Opcional. Se usa Case.Factura__c si no se indica factura.')
        public Id caseId;

        @InvocableVariable(label='Id de la Factura (Facturas__c)' description='Factura seleccionada en la pantalla anterior.')
        public Id facturaId;

        @InvocableVariable(label='Id de la Cuenta (Account)' description='Opcional. Valida que la factura pertenezca a la cuenta.')
        public Id accountId;

        @InvocableVariable(label='Id de la Sucursal (Account RT Sucursal)' description='Opcional. Valida que la factura pertenezca a la sucursal.')
        public Id sucursalId;
    }

    public class Result {
        @InvocableVariable(label='Detalles de la factura')
        @AuraEnabled
        public List<Detalle_Factura__c> detalles = new List<Detalle_Factura__c>();

        @InvocableVariable(label='Id de la factura resuelta')
        @AuraEnabled
        public Id facturaId;

        @InvocableVariable(label='Cantidad de detalles')
        @AuraEnabled
        public Integer cantidadDetalles = 0;

        @InvocableVariable(label='Tiene detalles')
        @AuraEnabled
        public Boolean tieneDetalles = false;

        @InvocableVariable(label='Mensaje de error')
        @AuraEnabled
        public String mensajeError;
    }

    @InvocableMethod(
        label='Obtener detalles de factura'
        description='Devuelve los Detalle_Factura__c de la factura indicada (o la del Caso), validando cuenta/sucursal.'
        category='Casos'
    )
    public static List<Result> obtenerDetallesInvocable(List<Request> requests) {
        List<Result> resultados = new List<Result>();
        for (Request req : requests) {
            resultados.add(resolver(req.caseId, req.facturaId, req.accountId, req.sucursalId));
        }
        return resultados;
    }

    // ---------------------------------------------------------------------------------
    // LWC
    // ---------------------------------------------------------------------------------

    @AuraEnabled
    public static Result obtenerDetalles(Id caseId, Id facturaId, Id accountId, Id sucursalId) {
        Result res = resolver(caseId, facturaId, accountId, sucursalId);
        if (String.isNotBlank(res.mensajeError)) {
            throw newAuraException(res.mensajeError);
        }
        return res;
    }

    // ---------------------------------------------------------------------------------
    // Lógica común
    // ---------------------------------------------------------------------------------

    @TestVisible
    private static Result resolver(Id caseId, Id facturaId, Id accountId, Id sucursalId) {
        Result res = new Result();
        try {
            Id idFactura = facturaId;

            if (idFactura == null && caseId != null) {
                List<Case> casos = [SELECT Id, Factura__c FROM Case WHERE Id = :caseId LIMIT 1];
                if (!casos.isEmpty()) {
                    idFactura = casos[0].Factura__c;
                }
            }

            if (idFactura == null) {
                res.mensajeError = MSG_SIN_FACTURA;
                return res;
            }

            List<Facturas__c> facturas = [
                SELECT Id, Cliente__c, Cliente__r.ParentId, Sucursal__c, Sucursal__r.ParentId
                FROM Facturas__c
                WHERE Id = :idFactura
                LIMIT 1
            ];
            if (facturas.isEmpty()) {
                res.mensajeError = MSG_FACTURA_NO_EXISTE;
                return res;
            }

            Facturas__c factura = facturas[0];
            if (accountId != null && !perteneceACuenta(factura, accountId)) {
                res.mensajeError = MSG_FACTURA_OTRA_CUENTA;
                return res;
            }
            if (sucursalId != null && factura.Sucursal__c != sucursalId && factura.Cliente__c != sucursalId) {
                res.mensajeError = MSG_FACTURA_OTRA_SUCURSAL;
                return res;
            }

            res.facturaId = factura.Id;
            res.detalles = consultarDetalles(factura.Id);
            res.cantidadDetalles = res.detalles.size();
            res.tieneDetalles = !res.detalles.isEmpty();
        } catch (Exception e) {
            res.mensajeError = 'Error al obtener los detalles de la factura: ' + e.getMessage();
        }
        return res;
    }

    private static Boolean perteneceACuenta(Facturas__c factura, Id accountId) {
        return factura.Cliente__c == accountId ||
            factura.Sucursal__c == accountId ||
            (factura.Sucursal__r != null && factura.Sucursal__r.ParentId == accountId) ||
            (factura.Cliente__r != null && factura.Cliente__r.ParentId == accountId);
    }

    /**
     * Incluye los campos y relaciones que el flujo consume desde outputSelectedRow
     * (Product__r, Factura__r.Cliente__r, Factura__r.Sucursal__r, etc.).
     */
    private static List<Detalle_Factura__c> consultarDetalles(Id facturaId) {
        List<Detalle_Factura__c> detalles = [
            SELECT Id, Name, SKU__c, Nombre_producto__c, Descripcion__c, Posicion__c,
                   Cantidad__c, Peso_neto__c, Conversion_UM__c, Cantidad_Unidad__c, Unidad_de_Medida__c,
                   Valor_Neto__c, valore_Rappel__c, Total_con_Rapel__c, Costo_Total__c,
                   Proceso_de_reclamo__c, Caso__c,
                   Product__c, Product__r.Id, Product__r.Name,
                   Factura__c, Factura__r.Id, Factura__r.Name, Factura__r.Numero_de_Factura__c,
                   Factura__r.Direccion_calle__c, Factura__r.Fecha_de_Documento__c,
                   Factura__r.Cliente__c, Factura__r.Cliente__r.Id, Factura__r.Cliente__r.Name,
                   Factura__r.Cliente__r.Comuna_Despacho__c, Factura__r.Cliente__r.Comuna_Despacho__r.Name,
                   Factura__r.Sucursal__c, Factura__r.Sucursal__r.Id, Factura__r.Sucursal__r.Name,
                   Factura__r.Sucursal__r.Centro_de_Abastecimiento__c
            FROM Detalle_Factura__c
            WHERE Factura__c = :facturaId
            ORDER BY Posicion__c ASC NULLS LAST, Name ASC
            LIMIT 2000
        ];
        return (List<Detalle_Factura__c>) Security.stripInaccessible(AccessType.READABLE, detalles).getRecords();
    }

    private static AuraHandledException newAuraException(String mensaje) {
        AuraHandledException ex = new AuraHandledException(mensaje);
        ex.setMessage(mensaje);
        return ex;
    }
}