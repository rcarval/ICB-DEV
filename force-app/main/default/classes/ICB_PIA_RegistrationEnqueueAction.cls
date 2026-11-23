/**********************************************************************************
 * ICB_PIA_RegistrationEnqueueAction
 * Encola registro PIA desde record-triggered flows (sin callout síncrono).
 * SEIDOR - Ticket 00026565
 **********************************************************************************/
public with sharing class ICB_PIA_RegistrationEnqueueAction {

    public class InvocableInput {
        @InvocableVariable(required=true label='Id de Cuenta')
        public Id accountId;

        @InvocableVariable(label='Forzar reintento')
        public Boolean forceRetry;
    }

    public class InvocableOutput {
        @InvocableVariable(label='Encolado')
        public Boolean queued;

        @InvocableVariable(label='Mensaje')
        public String mensaje;
    }

    @InvocableMethod(
        label='Encolar registro Cuenta en PIA'
        description='Encola el proceso asíncrono de registro PIA post-SAP.'
        category='PIA'
    )
    public static List<InvocableOutput> encolarRegistroPia(List<InvocableInput> inputs) {
        List<InvocableOutput> outputs = new List<InvocableOutput>();

        if (inputs == null) {
            return outputs;
        }

        Set<Id> accountIds = new Set<Id>();
        for (InvocableInput input : inputs) {
            if (input != null && input.accountId != null) {
                accountIds.add(input.accountId);
            }
        }

        Map<Id, Account> accountsById = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountsById = new Map<Id, Account>([
                SELECT Id, PIA_ID_Externo__c, PIA_Estado_Solicitud__c, PIA_Error_Log__c
                FROM Account
                WHERE Id IN :accountIds
                FOR UPDATE
            ]);
        }

        Set<Id> claimedAccountIds = new Set<Id>();
        Map<Id, Account> previousStateById = new Map<Id, Account>();

        for (InvocableInput input : inputs) {
            InvocableOutput output = new InvocableOutput();
            output.queued = false;
            output.mensaje = null;

            if (input == null || input.accountId == null) {
                output.mensaje = 'Id de Cuenta es obligatorio.';
                outputs.add(output);
                continue;
            }

            Account accountRecord = accountsById.get(input.accountId);
            if (accountRecord == null) {
                output.mensaje = 'No se encontró la Cuenta.';
                outputs.add(output);
                continue;
            }

            if (claimedAccountIds.contains(input.accountId)) {
                output.mensaje = 'La Cuenta ya fue considerada en esta solicitud.';
                outputs.add(output);
                continue;
            }

            Boolean forceRetry = input.forceRetry == true;
            String currentStatus = accountRecord.PIA_Estado_Solicitud__c;
            if (String.isNotBlank(accountRecord.PIA_ID_Externo__c) ||
                currentStatus == ICB_PIA_RegistrationService.ESTADO_CREADO ||
                currentStatus == ICB_PIA_RegistrationService.ESTADO_DUPLICADO) {
                output.mensaje = 'La Cuenta ya fue procesada en PIA. No se genera otro registro.';
                outputs.add(output);
                continue;
            }

            if (currentStatus == ICB_PIA_RegistrationService.ESTADO_EN_PROCESO) {
                output.mensaje = 'La Cuenta ya tiene una solicitud PIA en proceso.';
                outputs.add(output);
                continue;
            }

            if (forceRetry && currentStatus != ICB_PIA_RegistrationService.ESTADO_ERROR) {
                output.mensaje = 'El reintento manual solo está permitido desde Error_Reintentar.';
                outputs.add(output);
                continue;
            }

            try {
                previousStateById.put(input.accountId, new Account(
                    Id = accountRecord.Id,
                    PIA_Estado_Solicitud__c = accountRecord.PIA_Estado_Solicitud__c,
                    PIA_Error_Log__c = accountRecord.PIA_Error_Log__c
                ));
                update new Account(
                    Id = input.accountId,
                    PIA_Estado_Solicitud__c = ICB_PIA_RegistrationService.ESTADO_EN_PROCESO,
                    PIA_Error_Log__c = null
                );
                System.enqueueJob(new ICB_PIA_RegistrationQueueable(input.accountId, forceRetry));
                claimedAccountIds.add(input.accountId);
                output.queued = true;
                output.mensaje = 'Registro PIA encolado correctamente.';
            } catch (Exception ex) {
                Account previousState = previousStateById.get(input.accountId);
                if (previousState != null) {
                    update previousState;
                }
                output.mensaje = ex.getMessage();
            }

            outputs.add(output);
        }

        return outputs;
    }
}