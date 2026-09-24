public with sharing class ICBFS_FlowLookupContactoCuentaController {

    public class LookupResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
        @AuraEnabled public String email;
        @AuraEnabled public String mobilePhone;

        public LookupResult(Id id, String label, String name, String role, String email, String mobilePhone) {
            this.id = id;
            this.label = label;
            this.name = name;
            this.role = role;
            this.email = email;
            this.mobilePhone = mobilePhone;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchContactsByAccount(Id accountId, String searchText, Integer maxResults) {
        if (accountId == null) {
            return new List<LookupResult>();
        }

        String q = (searchText == null) ? '' : searchText.trim();
        Integer lim = (maxResults == null || maxResults <= 0 || maxResults > 200) ? 50 : maxResults;

        String likeValue = '%' + q + '%';
        List<Contact> contacts;

        if (String.isBlank(q)) {
            contacts = [
                SELECT Id, Name, Cargo_en_la_Empresa__c, Email, MobilePhone
                FROM Contact
                WHERE AccountId = :accountId
                ORDER BY Name
                LIMIT :lim
            ];
        } else {
            contacts = [
                SELECT Id, Name, Cargo_en_la_Empresa__c, Email, MobilePhone
                FROM Contact
                WHERE AccountId = :accountId
                AND Name LIKE :likeValue
                ORDER BY Name
                LIMIT :lim
            ];
        }

        List<LookupResult> results = new List<LookupResult>();
        for (Contact contactRecord : contacts) {
            String label = contactRecord.Name;
            if (!String.isBlank(contactRecord.Cargo_en_la_Empresa__c)) {
                label += ' - ' + contactRecord.Cargo_en_la_Empresa__c;
            }
            results.add(new LookupResult(
                contactRecord.Id,
                label,
                contactRecord.Name,
                contactRecord.Cargo_en_la_Empresa__c,
                contactRecord.Email,
                contactRecord.MobilePhone
            ));
        }
        return results;
    }
}