public with sharing class ICB_LeadConversionFlowAction {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;
    }

    public class Response {
        @InvocableVariable
        public Id leadId;

        @InvocableVariable
        public Id accountId;

        @InvocableVariable
        public Id contactId;

        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='ICB Lead Conversion Flow Action'
        description='Convierte Lead (si aplica) y ejecuta mapeo post-conversión de Account/Contact/Lead.'
    )
    public static List<Response> convertAndMap(List<Request> requests) {
        Set<Id> leadIds = new Set<Id>();
        if (requests != null) {
            for (Request requestItem : requests) {
                if (requestItem != null && requestItem.leadId != null) {
                    leadIds.add(requestItem.leadId);
                }
            }
        }

        List<ICB_LeadConversionService.ConversionResult> serviceResults =
            ICB_LeadConversionService.convertAndMapLeads(leadIds);

        List<Response> outputs = new List<Response>();
        for (ICB_LeadConversionService.ConversionResult serviceResult : serviceResults) {
            Response output = new Response();
            output.leadId = serviceResult.leadId;
            output.accountId = serviceResult.accountId;
            output.contactId = serviceResult.contactId;
            output.success = serviceResult.success;
            output.message = serviceResult.message;
            outputs.add(output);
        }
        return outputs;
    }
}