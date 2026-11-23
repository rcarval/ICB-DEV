/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Integracion SII Leads
Descripcion: Proceso asincrono queueable para consultar SII y persistir evaluacion
Test: Pendiente

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripcion
------ ---------- ---------------------------------------------------------------
1.0 05-05-2026            RCG                Creacion de la clase.
**********************************************************************************/
public with sharing class ICB_LeadsSII_IntegrationQueueable implements Queueable, Database.AllowsCallouts {
    private static final String LOG_PREFIX = '[ICB_LeadsSII_IntegrationQueueable]';

    private final List<Id> leadIds;

    /**
    * Constructor queueable.
    * @author Rodrigo Carvallo
    * @param List<Id> leadIds - IDs de Leads a procesar
    **/
    public ICB_LeadsSII_IntegrationQueueable(List<Id> leadIds) {
        this.leadIds = leadIds != null ? leadIds : new List<Id>();
    }

    /**
    * Ejecuta el flujo asincrono: consulta Lead, consume SII y aplica resultado.
    * @author Rodrigo Carvallo
    * @param QueueableContext context - Contexto de ejecucion del job
    **/
    public void execute(QueueableContext context) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Inicio queueable. inputLeadIds=' + leadIds.size());
        Set<Id> idSet = new Set<Id>();
        idSet.addAll(leadIds);
        idSet.remove(null);
        if (idSet.isEmpty()) {
            System.debug(LoggingLevel.WARN, LOG_PREFIX + ' Sin IDs validos para procesar.');
            return;
        }

        List<Lead> leads = ICB_LeadsSII_IntegrationService.queryLeadsForSII(idSet);
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Leads consultados=' + leads.size());
        if (leads.isEmpty()) {
            System.debug(LoggingLevel.WARN, LOG_PREFIX + ' No se encontraron Leads para procesar.');
            return;
        }

        for (Lead ld : leads) {
            System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Procesando leadId=' + ld.Id);
            String rut = ICB_LeadsSII_IntegrationService.extractRut(ld);
            System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Ejecutando consulta SII para leadId=' + ld.Id + ' rut=' + rut);
            try {
                ICB_CalloutAPI_SII.SituacionTributariaDataDto data = ICB_CalloutAPI_SII.consultarSituacionTributariaTercero(rut);
                ICB_LeadsSII_ResponseHandler.applySIIResult(ld, data, rut);
            } catch (Exception ex) {
                ICB_LeadsSII_ResponseHandler.applyException(ld.Id, ex, rut);
            }
        }
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Fin queueable. processed=' + leads.size());
    }
}