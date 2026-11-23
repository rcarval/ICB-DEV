public with sharing class EnviarSAPGateController {
    public Id accountId { get; private set; }
    public Account accountRecord { get; private set; }
    public List<String> missingFields { get; private set; }
    public String errorMessage { get; private set; }

    public EnviarSAPGateController() {
        missingFields = new List<String>();
    }

    @TestVisible
    private EnviarSAPGateController(Id testAccountId, Account testAccountRecord) {
        this();
        accountId = testAccountId;
        accountRecord = testAccountRecord;
    }

    public PageReference init() {
        String rawId = ApexPages.currentPage().getParameters().get('id');
        if (String.isBlank(rawId)) {
            errorMessage = 'No se recibio el Id de la cuenta.';
            return null;
        }

        try {
            accountId = Id.valueOf(rawId);
            loadData();
            return maybeRedirect();
        } catch (Exception ex) {
            errorMessage = 'No se pudo validar la cuenta para el envio a SAP.';
            return null;
        }
    }

    public String getAccountName() {
        return accountRecord != null && String.isNotBlank(accountRecord.Name)
            ? accountRecord.Name
            : 'Cuenta';
    }

    public Boolean getHasMissingFields() {
        return missingFields != null && !missingFields.isEmpty();
    }

    public Boolean getHasError() {
        return String.isNotBlank(errorMessage);
    }

    @TestVisible
    private void loadData() {
        accountRecord = [
            SELECT Id,
                   Name,
                   Nombre_de_Fantasia__c,
                   RUT__c,
                   ShippingStreet,
                   ShippingCity,
                   BillingStreet,
                   Phone,
                   Email__c,
                   Centro_de_Abastecimiento__c,
                   Sucursal__c,
                   Region_Despacho__c,
                   Region__c,
                   Gerencia__c,
                   Owner.Id_SAP_Ref_Cr_ditos__c,
                   Comuna_Despacho__r.Name,
                   Comuna_Despacho__r.Condici_n_de_expedici_n__c,
                   Comuna_Facturaci_n__r.Name
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
    }

    @TestVisible
    private PageReference maybeRedirect() {
        missingFields = collectMissingFields(accountRecord);
        if (!missingFields.isEmpty()) {
            return null;
        }

        PageReference nextPage = new PageReference('/flow/Auto_crear_cliente_full_v1?varAccountId=' + accountId);
        nextPage.setRedirect(true);
        return nextPage;
    }

    @TestVisible
    private static EnviarSAPGateController forTest(Id testAccountId, Account testAccountRecord) {
        return new EnviarSAPGateController(testAccountId, testAccountRecord);
    }

    @TestVisible
    private static List<String> collectMissingFields(Account accountRow) {
        List<String> issues = new List<String>();
        if (accountRow == null) {
            issues.add('No se pudo cargar la cuenta.');
            return issues;
        }

        addIfMissing(issues, isBlankField(accountRow, 'Name'), 'Nombre de la cuenta');
        addIfMissing(issues, isBlankField(accountRow, 'Nombre_de_Fantasia__c'), 'Nombre de fantasia');
        addIfMissing(issues, isBlankField(accountRow, 'RUT__c'), 'RUT');
        addIfMissing(issues, isBlankField(accountRow, 'ShippingStreet'), 'Direccion de despacho');
        addIfMissing(issues, isBlankField(accountRow, 'ShippingCity'), 'Distrito o ciudad de despacho');
        addIfMissing(issues, isBlankField(accountRow, 'Centro_de_Abastecimiento__c'), 'Centro de abastecimiento');
        addIfMissing(issues, isBlankRelatedField(accountRow, 'Comuna_Despacho__r', 'Name'), 'Comuna de despacho');
        addIfMissing(issues, isBlankRelatedField(accountRow, 'Comuna_Despacho__r', 'Condici_n_de_expedici_n__c'), 'Condicion de expedicion de la comuna de despacho');
        addIfMissing(issues, isBlankField(accountRow, 'Sucursal__c'), 'Sucursal');
        addIfMissing(issues, isBlankField(accountRow, 'Region_Despacho__c'), 'Region de despacho');
        addIfMissing(issues, isBlankField(accountRow, 'Gerencia__c'), 'Gerencia');
        addIfMissing(issues, isBlankField(accountRow, 'BillingStreet'), 'Direccion de facturacion');
        addIfMissing(issues, isBlankRelatedField(accountRow, 'Comuna_Facturaci_n__r', 'Name'), 'Comuna de facturacion');
        addIfMissing(issues, isBlankField(accountRow, 'Region__c'), 'Region de facturacion');
        addIfMissing(issues, isBlankField(accountRow, 'Phone'), 'Telefono');
        addIfMissing(issues, isBlankField(accountRow, 'Email__c'), 'Email');
        addIfMissing(issues, isBlankRelatedField(accountRow, 'Owner', 'Id_SAP_Ref_Cr_ditos__c'), 'Id SAP ref creditos del propietario de la cuenta');

        return issues;
    }

    private static void addIfMissing(List<String> issues, Boolean isMissing, String label) {
        if (isMissing) {
            issues.add(label);
        }
    }

    private static Boolean isBlankField(SObject row, String fieldApiName) {
        return String.isBlank(readFieldValue(row, fieldApiName));
    }

    private static Boolean isBlankRelatedField(SObject row, String relationshipName, String fieldApiName) {
        return String.isBlank(readFieldValue(readRelatedRecord(row, relationshipName), fieldApiName));
    }

    private static SObject readRelatedRecord(SObject row, String relationshipName) {
        if (row == null) {
            return null;
        }

        try {
            return row.getSObject(relationshipName);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String readFieldValue(SObject row, String fieldApiName) {
        if (row == null) {
            return null;
        }

        try {
            Object value = row.get(fieldApiName);
            return value == null ? null : String.valueOf(value).trim();
        } catch (Exception ex) {
            return null;
        }
    }
}