/**********************************************************************************
Desarrollado por: SEIDOR
Autor: Rodrigo Carvallo (RCG)
Proyecto: Integracion SII Leads
Descripcion: Accion invocable desde Flow para encolar integracion SII de Leads
Test: Pendiente

---------------------------------------------------------------------------------
No. Fecha                Autor                     Descripcion
------ ---------- ---------------------------------------------------------------
1.0 05-05-2026            RCG                Creacion de la clase.
**********************************************************************************/
public with sharing class ICB_LeadsSII_IntegrationAction {
    private static final String LOG_PREFIX = '[ICB_LeadsSII_IntegrationAction]';

    /**
    * Wrapper de entrada para el Invocable Method desde Flow.
    * @author Rodrigo Carvallo
    * @param String leadId - ID de Lead en formato String
    **/
    public class InvocableInput {
        @InvocableVariable(label='Id de Lead' description='Id de Lead a integrar')
        public String leadId;
    }

    /**
    * Wrapper de salida para devolver estado de encolamiento al Flow.
    * @author Rodrigo Carvallo
    * @param Boolean queued - Indica si se encolo el proceso
    * @param String asyncJobId - ID del Queueable encolado
    * @param String message - Mensaje de resultado para el Flow
    **/
    public class InvocableOutput {
        @InvocableVariable(label='Trabajo encolado')
        public Boolean queued;
        @InvocableVariable(label='Id del job asincrono (Queueable)')
        public String asyncJobId;
        @InvocableVariable(label='Mensaje')
        public String message;
    }

    @InvocableMethod(
        label='Integrar Leads con SII (encolar)'
        description='Consulta leads por Id y encola el proceso asincrono hacia el servicio SII.'
        category='Leads'
    )
    /**
    * Metodo invocable que recibe IDs de Lead, valida formato y encola integracion.
    * @author Rodrigo Carvallo
    * @param List<InvocableInput> inputs - Coleccion de filas de entrada del Flow
    * @return List<InvocableOutput> - Resultado por cada fila de entrada
    **/
    public static List<InvocableOutput> enqueueLeadsSIIIntegration(List<InvocableInput> inputs) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Inicio invocable. inputs=' + (inputs == null ? 0 : inputs.size()));
        List<InvocableOutput> outputs = new List<InvocableOutput>();
        if (inputs == null || inputs.isEmpty()) {
            System.debug(LoggingLevel.WARN, LOG_PREFIX + ' Sin entradas para procesar.');
            return outputs;
        }

        Set<String> allIds = new Set<String>();
        for (InvocableInput row : inputs) {
            if (row == null || String.isBlank(row.leadId)) {
                continue;
            }
            System.debug(LoggingLevel.INFO, LOG_PREFIX + ' leadId recibido en fila=' + row.leadId);
            allIds.add(row.leadId.trim());
        }
        allIds.remove(null);
        allIds.remove('');
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' IDs de Lead recibidos consolidados=' + allIds);
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' IDs de Lead detectados=' + allIds.size());

        String jobIdStr;
        Boolean queued = false;
        String message;
        if (allIds.isEmpty()) {
            message = 'No se recibieron Ids de Lead validos.';
            System.debug(LoggingLevel.WARN, LOG_PREFIX + ' No hay IDs validos luego de parsear input.');
        } else {
            List<Lead> found = ICB_LeadsSII_IntegrationService.queryLeadsForSII(allIds);
            System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Leads encontrados=' + found.size());
            if (found.isEmpty()) {
                message = 'No existen registros de Lead para los Ids indicados.';
            } else {
                List<Id> toQueue = new List<Id>();
                for (Lead ld : found) {
                    toQueue.add(ld.Id);
                }
                jobIdStr = System.enqueueJob(new ICB_LeadsSII_IntegrationQueueable(toQueue));
                queued = true;
                message = 'Integracion encolada.';
                System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Queueable encolado. jobId=' + jobIdStr + ' leadCount=' + toQueue.size());
            }
        }

        for (Integer i = 0; i < inputs.size(); i++) {
            InvocableOutput o = new InvocableOutput();
            o.queued = queued;
            o.asyncJobId = jobIdStr;
            o.message = message;
            outputs.add(o);
        }
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Fin invocable. queued=' + queued + ' outputs=' + outputs.size());
        return outputs;
    }
}