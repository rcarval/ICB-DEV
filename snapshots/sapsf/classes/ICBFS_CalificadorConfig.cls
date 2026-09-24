public with sharing class ICBFS_CalificadorConfig {
    public class Values {
        public Boolean enabled;
        public String webhookUrl;
        public String ownerUsernameBase;
        public String codePrefix;
        public String excludedRecordType;
        public String callbackToken;
    }

    @TestVisible private static Values testValues;

    public static Values getValues() {
        if (Test.isRunningTest() && testValues != null) return testValues;
        ICBFS_Calificador_Config__mdt row = ICBFS_Calificador_Config__mdt.getInstance('Default');
        Values value = new Values();
        value.enabled = row != null && row.Habilitado__c;
        value.webhookUrl = row == null ? null : row.Webhook_URL__c;
        value.ownerUsernameBase = row == null ? null : row.Owner_Username_Base__c;
        value.codePrefix = row == null ? null : row.Prefijo_Codigo__c;
        value.excludedRecordType = row == null ? null : row.RecordType_Excluido__c;
        ICBFS_Calificador_Secret__c secret = ICBFS_Calificador_Secret__c.getValues('Default');
        value.callbackToken = secret == null ? null : secret.Callback_Token__c;
        return value;
    }

    public static Boolean isEligible(Account account, Values config) {
        if (account == null || config == null) return false;
        String customerCode = account.C_digo_de_cliente__c;
        String ownerUsername = account.Owner == null ? null : account.Owner.Username;
        String recordTypeName = account.RecordType == null ? null : account.RecordType.DeveloperName;
        Boolean codeMatches = String.isNotBlank(customerCode) && String.isNotBlank(config.codePrefix)
            && customerCode.toUpperCase().contains(config.codePrefix.toUpperCase());
        Boolean ownerMatches = String.isNotBlank(ownerUsername) && String.isNotBlank(config.ownerUsernameBase)
            && (ownerUsername.equalsIgnoreCase(config.ownerUsernameBase)
                || ownerUsername.toLowerCase().startsWith(config.ownerUsernameBase.toLowerCase() + '.'));
        Boolean recordTypeAllowed = String.isBlank(config.excludedRecordType)
            || !config.excludedRecordType.equalsIgnoreCase(recordTypeName);
        return codeMatches && ownerMatches && recordTypeAllowed && String.isNotBlank(account.RUT__c);
    }
}