/**
 * Controller para el LWC selectorMultiMaquina.
 * Busca productos por nombre filtrados por Tipo_Equipo__c.
 */
public with sharing class SelectorMultiMaquinaController {

    @AuraEnabled(cacheable=true)
    public static List<Product2> searchMachines(String searchTerm, String tipoEquipo) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Product2>();
        }

        String likePattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';

        return [
            SELECT Id, Name, TextoCategoria__c, ProductCode, IsActive
            FROM Product2
            WHERE Name LIKE :likePattern
            AND Tipo_Equipo__c = :tipoEquipo
            AND IsActive = true
            ORDER BY Name
            LIMIT 20
        ];
    }
}