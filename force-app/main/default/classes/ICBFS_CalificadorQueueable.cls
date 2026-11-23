public with sharing class ICBFS_CalificadorQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer CHUNK_SIZE = 50;
    private final List<Id> requestIds;

    public ICBFS_CalificadorQueueable(List<Id> requestIds) {
        this.requestIds = new List<Id>();
        if (requestIds != null) this.requestIds.addAll(requestIds);
    }

    public void execute(QueueableContext context) {
        if (requestIds.isEmpty()) return;
        List<Id> currentIds = new List<Id>();
        List<Id> remainingIds = new List<Id>();
        for (Integer i = 0; i < requestIds.size(); i++) {
            if (i < CHUNK_SIZE) currentIds.add(requestIds[i]);
            else remainingIds.add(requestIds[i]);
        }
        Map<Id, ICBFS_Calificacion_Request__c> requests = new Map<Id, ICBFS_Calificacion_Request__c>([
            SELECT Id, Account__c, Correlation_Id__c, Estado__c, Intento__c,
                   Account__r.Id, Account__r.Name, Account__r.RUT__c, Account__r.C_digo_de_cliente__c,
                   Account__r.Website, Account__r.Email__c, Account__r.Especialidad__c,
                   Account__r.BillingStreet, Account__r.BillingCity, Account__r.Comuna__r.Name,
                   Account__r.Nombre_de_Fantasia__c, Account__r.Comuna_Facturaci_n__r.Name,
                   Account__r.Owner.Username, Account__r.RecordType.DeveloperName
            FROM ICBFS_Calificacion_Request__c WHERE Id IN :currentIds
        ]);
        ICBFS_CalificadorConfig.Values config = ICBFS_CalificadorConfig.getValues();
        List<ICBFS_Calificacion_Request__c> requestUpdates = new List<ICBFS_Calificacion_Request__c>();
        List<Account> accountUpdates = new List<Account>();
        for (Id requestId : currentIds) {
            ICBFS_Calificacion_Request__c request = requests.get(requestId);
            if (request == null) continue;
            Decimal attempt = request.Intento__c == null ? 0 : request.Intento__c;
            try {
                if (config.enabled != true) throw new ICBFS_CalificadorService.CalificadorException('Integración deshabilitada por configuración');
                if (!ICBFS_CalificadorConfig.isEligible(request.Account__r, config)) {
                    requestUpdates.add(new ICBFS_Calificacion_Request__c(Id=request.Id, Estado__c='No aplica', Intento__c=attempt + 1));
                    accountUpdates.add(new Account(Id=request.Account__c, ICBFS_Calificador_Estado__c='No aplica'));
                    continue;
                }
                ICBFS_CalificadorService.AsyncResponse response = ICBFS_CalificadorService.send(
                    request.Account__r, config.webhookUrl, request.Correlation_Id__c, config.callbackToken
                );
                requestUpdates.add(new ICBFS_Calificacion_Request__c(
                    Id=request.Id, Estado__c='En proceso', Execution_Arn__c=response.executionArn,
                    Intento__c=attempt + 1, Ultimo_Error__c=null
                ));
                accountUpdates.add(new Account(
                    Id=request.Account__c, ICBFS_Calificador_Estado__c='En proceso',
                    ICBFS_Calificador_ExecutionArn__c=response.executionArn, ICBFS_Calificador_Ultimo_Error__c=null
                ));
            } catch (Exception error) {
                String message = truncate(error.getMessage(), 32768);
                requestUpdates.add(new ICBFS_Calificacion_Request__c(Id=request.Id, Estado__c='Error', Intento__c=attempt + 1, Ultimo_Error__c=message));
                accountUpdates.add(new Account(Id=request.Account__c, ICBFS_Calificador_Estado__c='Error', ICBFS_Calificador_Ultimo_Error__c=message));
            }
        }
        if (!requestUpdates.isEmpty()) Database.update(requestUpdates, false);
        if (!accountUpdates.isEmpty()) Database.update(accountUpdates, false);
        ICB_LogIntegracionService.publicarLogsOutboundPendientes();
        if (!remainingIds.isEmpty()) System.enqueueJob(new ICBFS_CalificadorQueueable(remainingIds));
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}