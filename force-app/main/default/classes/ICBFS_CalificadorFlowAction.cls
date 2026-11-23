public with sharing class ICBFS_CalificadorFlowAction {
    public class Input {
        @InvocableVariable(required=true label='Account Id') public Id accountId;
    }
    public class Output {
        @InvocableVariable(label='Encolado') public Boolean queued;
        @InvocableVariable(label='Solicitud Id') public Id requestId;
        @InvocableVariable(label='Mensaje') public String message;
    }

    @InvocableMethod(label='Encolar Calificación ICBFS' description='Registra y encola la calificación asíncrona del Account')
    public static List<Output> enqueue(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        Set<Id> accountIds = new Set<Id>();
        if (inputs != null) for (Input input : inputs) if (input != null && input.accountId != null) accountIds.add(input.accountId);
        Map<Id, ICBFS_Calificacion_Request__c> requestByAccount = new Map<Id, ICBFS_Calificacion_Request__c>();
        Long nowValue = DateTime.now().getTime();
        for (Id accountId : accountIds) {
            ICBFS_Calificacion_Request__c request = new ICBFS_Calificacion_Request__c(
                Account__c = accountId,
                Correlation_Id__c = String.valueOf(accountId) + '-' + String.valueOf(nowValue) + '-' + randomSuffix(),
                Estado__c = 'Pendiente', Intento__c = 0, Fecha_Solicitud__c = System.now()
            );
            requestByAccount.put(accountId, request);
        }
        if (!requestByAccount.isEmpty()) {
            insert requestByAccount.values();
            List<Account> accounts = new List<Account>();
            for (Id accountId : requestByAccount.keySet()) accounts.add(new Account(
                Id = accountId, ICBFS_Calificador_Estado__c = 'Pendiente',
                ICBFS_Calificador_Fecha_Solicitud__c = System.now(), ICBFS_Calificador_Ultimo_Error__c = null
            ));
            update accounts;
            System.enqueueJob(new ICBFS_CalificadorQueueable(new List<Id>(new Map<Id, ICBFS_Calificacion_Request__c>(requestByAccount.values()).keySet())));
        }
        for (Input input : inputs == null ? new List<Input>() : inputs) {
            Output output = new Output();
            ICBFS_Calificacion_Request__c request = input == null ? null : requestByAccount.get(input.accountId);
            output.queued = request != null;
            output.requestId = request == null ? null : request.Id;
            output.message = request == null ? 'Account Id inválido' : 'Solicitud encolada';
            outputs.add(output);
        }
        return outputs;
    }

    private static String randomSuffix() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
    }
}