/**
 * Acción invocable desde Flow para encolar el envío async de un Contrato_Digital__c
 * firmado a SAP. Mismo patrón que ICBFS_CondPagoSAPAsyncInvoker (ya activo en PROD):
 * el Flow no espera el callout, solo encola el Queueable después de commit.
 *
 * Uso previsto (sección 7 de la memoria): invocar desde el Flow existente
 * Automatizacion_Comodato_Firmado cuando Contrato_Digital__c.Estado__c pase a 'Firmado'
 * y existan Fecha_Firma__c y PDF_Firmado_URL__c.
 */
public with sharing class ICB_ComodatoSapAction {

    public class Input {
        @InvocableVariable(required=true label='ID del Contrato Digital')
        public Id contratoDigitalId;
    }

    @InvocableMethod(label='ICB Comodato SAP - Encolar Envío' description='Encola el envío async del contrato de comodato a SAP.')
    public static void enqueue(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        for (Input inp : inputs) {
            if (inp != null && inp.contratoDigitalId != null) {
                System.enqueueJob(new ICB_ComodatoSapQueueable(inp.contratoDigitalId));
            }
        }
    }
}