/**********************************************************************************
 * ICB_CircuitBreakerSeed
 * Utilidad de setup: crea los registros base de Circuit_Breaker__c para los
 * procesos protegidos por el circuit breaker de envios masivos a SAP, si no
 * existen aun. Se invoca una vez por entorno via Apex anonimo:
 *   ICB_CircuitBreakerSeed.seedProcesosMVP();
 * Todos quedan con Activo__c=false (kill switch apagado) hasta activarlos
 * manualmente desde el panel de administracion, siguiendo el runbook de deploy.
 **********************************************************************************/
public with sharing class ICB_CircuitBreakerSeed {

    public static void seedProcesosMVP() {
        List<String> procesos = new List<String>{
            'Update_Cliente_Full_Cliente_SAP',
            'Crear_Asociacion',
            'Subflow_Domicilio_adicional_cliente_v3'
        };
        seedProcesos(procesos, 'jillanes@icbfs.cl', 'info@icbfs.cl');
    }

    public static void seedProcesos(List<String> procesos, String destinatariosCorreo, String remitenteOrgWide) {
        List<Circuit_Breaker__c> existentes = [
            SELECT Nombre_Proceso__c FROM Circuit_Breaker__c WHERE Nombre_Proceso__c IN :procesos
        ];
        Set<String> yaExisten = new Set<String>();
        for (Circuit_Breaker__c cb : existentes) {
            yaExisten.add(cb.Nombre_Proceso__c);
        }

        List<Circuit_Breaker__c> nuevos = new List<Circuit_Breaker__c>();
        for (String proceso : procesos) {
            if (yaExisten.contains(proceso)) {
                continue;
            }
            nuevos.add(new Circuit_Breaker__c(
                Name = proceso.left(80),
                Nombre_Proceso__c = proceso,
                Activo__c = false,
                Umbral_Intentos__c = 20,
                Ventana_Segundos__c = 1,
                Enfriamiento_Minutos__c = 15,
                Estado__c = 'Cerrado',
                Contador_Ventana__c = 0,
                Total_Intentos_Bloqueados__c = 0,
                Correo_Enviado__c = false,
                Destinatarios_Correo__c = destinatariosCorreo,
                Remitente_OrgWideEmail__c = remitenteOrgWide
            ));
        }

        if (!nuevos.isEmpty()) {
            insert nuevos;
        }
    }

    public static void marcarObjetoApi(String objetoApi) {
        List<Circuit_Breaker__c> filas = [SELECT Id FROM Circuit_Breaker__c];
        for (Circuit_Breaker__c f : filas) {
            f.Objeto_API__c = objetoApi;
        }
        update filas;
    }
}