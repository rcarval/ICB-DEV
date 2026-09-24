/**
 * Orquesta el envío async de un Contrato_Digital__c firmado a SAP: arma el payload
 * (ICB_ComodatoSapPayloadBuilder), hace el callout (ICB_ComodatoSapHttpClient) y
 * registra el resultado en los campos de control de Contrato_Digital__c.
 *
 * BLOQUEANTE — esta clase NO COMPILARÁ hasta que existan en Contrato_Digital__c:
 *   Estado_Envio_SAP__c (picklist: Pendiente/En proceso/Enviado/Error),
 *   Clave_Envio_SAP__c (texto único, Bukrs|Contrato|Anexo|Accion),
 *   Fecha_Envio_SAP__c, Codigo_HTTP_SAP__c, Intentos_Envio_SAP__c,
 *   Ultimo_Error_SAP__c, Respuesta_SAP__c.
 * Ver docs/MEMORIA_INTEGRACION_SAP_COMODATO_FIRMADO.md sección 7.
 *
 * Idempotencia: si Estado_Envio_SAP__c ya es 'Enviado' para este registro, no reenvía
 * (SAP no rechaza duplicados por sí solo — el control es 100% de Salesforce).
 */
public with sharing class ICB_ComodatoSapQueueable implements Queueable, Database.AllowsCallouts {

    private final Id contratoDigitalId;

    public ICB_ComodatoSapQueueable(Id contratoDigitalId) {
        this.contratoDigitalId = contratoDigitalId;
    }

    public void execute(QueueableContext ctx) {
        Contrato_Digital__c estado = [
            SELECT Id, Estado_Envio_SAP__c, Intentos_Envio_SAP__c
            FROM Contrato_Digital__c
            WHERE Id = :contratoDigitalId
            LIMIT 1
        ];

        if (estado.Estado_Envio_SAP__c == 'Enviado') {
            return;
        }

        Integer intentos = (estado.Intentos_Envio_SAP__c == null ? 0 : estado.Intentos_Envio_SAP__c.intValue()) + 1;

        try {
            Map<String, Object> payload = ICB_ComodatoSapPayloadBuilder.build(contratoDigitalId);
            String jsonBody = JSON.serialize(payload);
            String clave = String.valueOf(payload.get('Bukrs')) + '|' + payload.get('Contrato') + '|' + payload.get('Anexo') + '|' + payload.get('Accion');

            ICB_ComodatoSapHttpClient.SapResponse res = ICB_ComodatoSapHttpClient.post(jsonBody);

            Boolean ok = res.statusCode == 200 || res.statusCode == 201;
            update new Contrato_Digital__c(
                Id = contratoDigitalId,
                Estado_Envio_SAP__c = ok ? 'Enviado' : 'Error',
                Clave_Envio_SAP__c = clave,
                Fecha_Envio_SAP__c = Datetime.now(),
                Codigo_HTTP_SAP__c = res.statusCode,
                Intentos_Envio_SAP__c = intentos,
                Ultimo_Error_SAP__c = ok ? null : ('[SAP] Rechazado con HTTP ' + res.statusCode
                    + (String.isNotBlank(res.body) ? '. Respuesta: ' + res.body.abbreviate(2000) : '')),
                Respuesta_SAP__c = res.body != null ? res.body.left(131072) : null
            );

        } catch (ICB_ComodatoSapPayloadBuilder.ValidationException ve) {
            update new Contrato_Digital__c(
                Id = contratoDigitalId,
                Estado_Envio_SAP__c = 'Error',
                Fecha_Envio_SAP__c = Datetime.now(),
                Intentos_Envio_SAP__c = intentos,
                // El envio ni siquiera salio del org: falta un dato en Salesforce.
                Ultimo_Error_SAP__c = '[SALESFORCE] Falta un dato antes de enviar: ' + ve.getMessage()
            );
        } catch (Exception ex) {
            update new Contrato_Digital__c(
                Id = contratoDigitalId,
                Estado_Envio_SAP__c = 'Error',
                Fecha_Envio_SAP__c = Datetime.now(),
                Intentos_Envio_SAP__c = intentos,
                Ultimo_Error_SAP__c = ('[SALESFORCE] Error inesperado (' + ex.getTypeName() + '): ' + ex.getMessage() + '\n' + ex.getStackTraceString()).left(32768)
            );
        }
    }
}