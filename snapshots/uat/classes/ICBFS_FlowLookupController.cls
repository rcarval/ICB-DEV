/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-12
Descripción : Controller para lookup custom (Flow) con búsqueda por nombre.
**********************************************************************************/
public with sharing class ICBFS_FlowLookupController {

    public class LookupResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        public LookupResult(Id id, String label) {
            this.id = id;
            this.label = label;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<LookupResult> searchMarcas(String searchText, Integer maxResults) {
        String q = (searchText == null) ? '' : searchText.trim();
        if (q.length() < 2) {
            return new List<LookupResult>();
        }

        Integer lim = (maxResults == null || maxResults <= 0 || maxResults > 20) ? 10 : maxResults;

        // Ajusta el objeto si no es Marca__c
        List<Marca__c> marcas = [
            SELECT Id, Name
            FROM Marca__c
            WHERE Name LIKE :('%' + q + '%')
            ORDER BY Name
            LIMIT :lim
        ];

        List<LookupResult> out = new List<LookupResult>();
        for (Marca__c m : marcas) {
            out.add(new LookupResult(m.Id, m.Name));
        }
        return out;
    }
}