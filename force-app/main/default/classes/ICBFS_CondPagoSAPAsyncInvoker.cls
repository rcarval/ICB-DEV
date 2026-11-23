public with sharing class ICBFS_CondPagoSAPAsyncInvoker {
    public class Input {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    @InvocableMethod(label='ICBFS CondPago SAP Async' description='Encola la integración SAP de condición de pago en segundo plano.')
    public static void enqueue(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Input req : inputs) {
            if (req != null && req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }

        for (Id accountId : accountIds) {
            System.enqueueJob(new RunFlowQueueable((String) accountId));
        }
    }

    public class RunFlowQueueable implements Queueable {
        private final String accountId;

        public RunFlowQueueable(String accountId) {
            this.accountId = accountId;
        }

        public void execute(QueueableContext qc) {
            if (String.isBlank(accountId)) {
                return;
            }

            try {
                Map<String, Object> inputs = new Map<String, Object>{
                    'recordId' => accountId
                };
                Flow.Interview flowInterview = Flow.Interview.createInterview('SF_Integrar_CondPago_SAP', inputs);
                flowInterview.start();
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Error ejecutando SF_Integrar_CondPago_SAP async: ' + ex.getMessage());
            }
        }
    }
}