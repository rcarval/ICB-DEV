/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Integracion SII Leads
Descripcion: Servicio de consulta y utilitarios para integracion SII sobre Lead
Test: Pendiente

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripcion
------ ---------- ---------------------------------------------------------------
1.0 05-05-2026            RCG                Creacion de la clase.
**********************************************************************************/
public with sharing class ICB_LeadsSII_IntegrationService {

    /**
    * DTO simple para representar resultados de validaciones tecnicas.
    * @author Rodrigo Carvallo
    **/
    public class ValidationResult {
        public Boolean isComplete;
        public List<String> missingFields;

        public ValidationResult() {
            this.isComplete = true;
            this.missingFields = new List<String>();
        }
    }

    /**
    * Obtiene los Leads necesarios para la integracion SII.
    * @author Rodrigo Carvallo
    * @param Set<Id> leadIds - IDs de Lead a consultar
    * @return List<Lead> - Leads con campos requeridos para evaluacion y update
    **/
    public static List<Lead> queryLeadsForSII(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Company, RUT__c, Aprobado_SII__c, Observaciones_SII__c, Codigo_Actividad_SII__c
            FROM Lead
            WHERE Id IN :leadIds
        ];
    }

    /**
    * Obtiene los Leads necesarios para la integracion SII usando IDs String.
    * @author Rodrigo Carvallo
    * @param Set<String> leadIds - IDs de Lead en texto
    * @return List<Lead> - Leads con campos requeridos para evaluacion y update
    **/
    public static List<Lead> queryLeadsForSII(Set<String> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return new List<Lead>();
        }
        return [
            SELECT Id, Name, Company, RUT__c, Aprobado_SII__c, Observaciones_SII__c, Codigo_Actividad_SII__c
            FROM Lead
            WHERE Id IN :leadIds
        ];
    }

    /**
    * Obtiene el RUT desde Lead y lo normaliza para consumo del endpoint.
    * @author Rodrigo Carvallo
    * @param Lead ld - Lead origen
    * @return String - RUT limpio (sin puntos/espacios) o null si no existe
    **/
    public static String extractRut(Lead ld) {
        if (ld == null) {
            return null;
        }
        if (String.isBlank(ld.RUT__c)) {
            return null;
        }
        return sanitizeRut(ld.RUT__c);
    }

    /**
    * Limpia y estandariza formato del RUT.
    * @author Rodrigo Carvallo
    * @param String rut - RUT de entrada
    * @return String - RUT saneado para consulta SII
    **/
    private static String sanitizeRut(String rut) {
        if (String.isBlank(rut)) {
            return null;
        }
        String cleaned = rut.replace('.', '').replace(' ', '').toUpperCase();
        return cleaned;
    }
}