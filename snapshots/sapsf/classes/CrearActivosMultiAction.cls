/**
 * Invocable Action que crea un Asset por cada máquina/dispensador
 * en los OpportunityLineItems de una Opportunity.
 * Nombre del activo: "{Nombre Producto} {Fecha hoy}"
 * Vincula todos al Contrato Digital firmado.
 */
public with sharing class CrearActivosMultiAction {

    public class Input {
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;

        @InvocableVariable(required=true label='Account Id')
        public Id accountId;

        @InvocableVariable(label='Contact Id')
        public Id contactId;

        @InvocableVariable(label='Contrato Digital Id')
        public Id contratoDigitalId;
    }

    public class Output {
        @InvocableVariable public List<Id> assetIds;
        /**
         * Primer activo creado, para los campos de tipo Buscar que admiten un solo valor.
         * Opportunity.Activo_Asignado__c es uno de esos: asignarle assetIds completo hace
         * fallar el guardado con INVALID_TYPE_ON_FIELD_IN_RECORD en cuanto la cotizacion
         * lleva mas de una maquina. Es el mismo criterio que ya se usa para Contract.Activo__c.
         */
        @InvocableVariable public Id primerAssetId;
        @InvocableVariable public Integer cantidadActivos;
        @InvocableVariable public Id contractId;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
    }

    @InvocableMethod(label='Crear Activos Multi-Máquina' description='Crea un Asset por cada máquina en los OLI de la Opportunity y un Contract vinculado')
    public static List<Output> crearActivos(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(procesarUno(inp));
        }
        return results;
    }

    private static Output procesarUno(Input inp) {
        Output out = new Output();
        out.success = false;
        out.assetIds = new List<Id>();

        try {
            // Obtener todas las partidas de máquinas de la Opportunity
            List<OpportunityLineItem> lineItems = [
                SELECT Product2Id, Product2.Name, Product2.Tipo_Equipo__c, Quantity
                FROM OpportunityLineItem
                WHERE OpportunityId = :inp.opportunityId
                AND (Product2.Tipo_Equipo__c = 'Máquina Café' OR Product2.Tipo_Equipo__c = 'Dispensador')
            ];

            if (lineItems.isEmpty()) {
                // Fallback: buscar cualquier OpportunityLineItem
                lineItems = [
                    SELECT Product2Id, Product2.Name, Quantity
                    FROM OpportunityLineItem
                    WHERE OpportunityId = :inp.opportunityId
                    LIMIT 1
                ];
            }

            String fechaHoy = Date.today().format();
            List<Asset> assetsToCreate = new List<Asset>();

            // Un activo por equipo, con la cantidad en Quantity. No uno por unidad: en PROD
            // ninguna pasada creo mas de un activo del mismo equipo, y los 92 activos que
            // llevan Quantity la usan para eso (las maquinas en 1, un insumo en 24).
            for (OpportunityLineItem oli : lineItems) {
                Asset a = new Asset();
                a.Name = oli.Product2.Name + ' ' + fechaHoy;
                a.AccountId = inp.accountId;
                a.ContactId = inp.contactId;
                a.Product2Id = oli.Product2Id;
                a.Quantity = oli.Quantity;
                a.Status = 'En espera de Número de Serie';
                assetsToCreate.add(a);
            }

            if (!assetsToCreate.isEmpty()) {
                insert assetsToCreate;
                for (Asset a : assetsToCreate) {
                    out.assetIds.add(a.Id);
                }
                out.primerAssetId = out.assetIds[0];
            }
            out.cantidadActivos = out.assetIds.size();

            // Crear Contract vinculado al primer activo y al Contrato Digital
            if (!assetsToCreate.isEmpty()) {
                Contract c = new Contract();
                c.AccountId = inp.accountId;
                c.Status = 'Firmado';
                c.Activo__c = assetsToCreate[0].Id;
                if (inp.contratoDigitalId != null) {
                    c.Contrato_Digital__c = inp.contratoDigitalId;
                }
                insert c;
                out.contractId = c.Id;
            }

            out.success = true;
        } catch (Exception e) {
            out.errorMessage = e.getMessage();
        }

        return out;
    }
}