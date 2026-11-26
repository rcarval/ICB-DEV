/**********************************************************************************
ICB Food Service — Tickets 00028198 / 00028201
Checklist de datos mínimos para FDR / Crear Caso (nombre de fantasía + contacto completo).
Usado por LWC checklistDatosFdr y como gate invocable en Caso_Ingreso_de_Caso_mejorado.
**********************************************************************************/
public with sharing class ChecklistDatosFdrController {

    public class ChecklistItem {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean ok;
        @AuraEnabled public String detail;

        public ChecklistItem(String key, String label, Boolean ok, String detail) {
            this.key = key;
            this.label = label;
            this.ok = ok;
            this.detail = detail;
        }
    }

    public class ChecklistResult {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public Boolean canCreateCase;
        @AuraEnabled public String profileName;
        @AuraEnabled public String summaryMessage;
        @AuraEnabled public List<ChecklistItem> items;
        @AuraEnabled public List<String> missingLabels;
    }

    public class FlowRequest {
        @InvocableVariable(required=true label='Account Id')
        public Id accountId;
    }

    public class FlowResponse {
        @InvocableVariable(label='Checklist completo')
        public Boolean isComplete;
        @InvocableVariable(label='Mensaje')
        public String message;
        @InvocableVariable(label='Labels faltantes')
        public String missingLabelsCsv;
    }

    /** Custom Permission que habilita el CTA Crear Caso (permission set Crear_Caso_FDR). */
    @TestVisible
    private static final String CREATE_CASE_CUSTOM_PERMISSION = 'Crear_Caso_FDR';

    /** Solo para tests: FeatureManagement no refleja PSA creada en la misma transacción. */
    @TestVisible
    private static Boolean testCanCreateCaseOverride;

    @AuraEnabled(cacheable=false)
    public static ChecklistResult evaluate(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Se requiere el Id de la cuenta.');
        }
        return buildResult(accountId);
    }

    @InvocableMethod(
        label='Validar checklist datos FDR'
        description='Valida Nombre de Fantasía y contacto completo (Name, Email, Phone/Mobile) en la cuenta.'
        category='ICB Service'
    )
    public static List<FlowResponse> validateForFlow(List<FlowRequest> requests) {
        List<FlowResponse> responses = new List<FlowResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }
        for (FlowRequest req : requests) {
            ChecklistResult result = buildResult(req.accountId);
            FlowResponse resp = new FlowResponse();
            resp.isComplete = result.isComplete;
            resp.message = result.summaryMessage;
            resp.missingLabelsCsv = result.missingLabels == null
                ? null
                : String.join(result.missingLabels, '; ');
            responses.add(resp);
        }
        return responses;
    }

    @TestVisible
    private static ChecklistResult buildResult(Id accountId) {
        ChecklistResult result = new ChecklistResult();
        result.accountId = accountId;
        result.items = new List<ChecklistItem>();
        result.missingLabels = new List<String>();
        result.profileName = UserInfo.getProfileId() == null
            ? null
            : [
                SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1
              ].Name;
        // Gobernado por conjunto de permisos (Custom Permission), no por nombre de perfil.
        result.canCreateCase = resolveCanCreateCase();

        Account acc = [
            SELECT Id, Name, Nombre_de_Fantasia__c,
                (SELECT Id, Name, Email, Phone, MobilePhone
                 FROM Contacts
                 ORDER BY LastModifiedDate DESC
                 LIMIT 50)
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        Boolean hasFantasia = String.isNotBlank(acc.Nombre_de_Fantasia__c);
        result.items.add(new ChecklistItem(
            'fantasia',
            'Nombre de fantasía',
            hasFantasia,
            hasFantasia ? acc.Nombre_de_Fantasia__c : 'Falta Nombre de fantasía en la cuenta'
        ));
        if (!hasFantasia) {
            result.missingLabels.add('Nombre de fantasía');
        }

        Contact completeContact = findCompleteContact(acc.Contacts);
        Boolean hasContact = completeContact != null;
        String contactDetail = hasContact
            ? completeContact.Name
            : 'Se requiere un contacto de la cuenta con Nombre, Email y Teléfono (Phone o Mobile)';
        result.items.add(new ChecklistItem(
            'contacto',
            'Contacto completo (nombre, email y teléfono)',
            hasContact,
            contactDetail
        ));
        if (!hasContact) {
            result.missingLabels.add('Contacto completo (nombre, email y teléfono)');
        }

        result.isComplete = hasFantasia && hasContact;
        result.summaryMessage = result.isComplete
            ? 'Datos listos para crear el caso.'
            : 'Completa los datos faltantes antes de crear el caso: '
                + String.join(result.missingLabels, '; ');
        return result;
    }

    @TestVisible
    private static Boolean resolveCanCreateCase() {
        if (Test.isRunningTest() && testCanCreateCaseOverride != null) {
            return testCanCreateCaseOverride;
        }
        return FeatureManagement.checkPermission(CREATE_CASE_CUSTOM_PERMISSION);
    }

    private static Contact findCompleteContact(List<Contact> contacts) {
        if (contacts == null) {
            return null;
        }
        for (Contact c : contacts) {
            Boolean hasName = String.isNotBlank(c.Name);
            Boolean hasEmail = String.isNotBlank(c.Email);
            Boolean hasPhone = String.isNotBlank(c.MobilePhone) || String.isNotBlank(c.Phone);
            if (hasName && hasEmail && hasPhone) {
                return c;
            }
        }
        return null;
    }
}
