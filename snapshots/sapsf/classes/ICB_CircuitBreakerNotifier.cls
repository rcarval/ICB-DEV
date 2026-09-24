/**********************************************************************************
 * ICB_CircuitBreakerNotifier
 * Envia la alerta por correo cuando un Circuit_Breaker__c pasa de Cerrado a Abierto.
 * Se llama una sola vez por apertura desde ICB_CircuitBreakerService.
 * Patron de envio (OrgWideEmailAddress + Messaging.sendEmail) tomado de
 * ICBFS_QR_SendCampaignQueue. Nunca lanza excepcion ni revierte el estado ya guardado.
 **********************************************************************************/
public with sharing class ICB_CircuitBreakerNotifier {

    public static void enviarAlertaApertura(Circuit_Breaker__c breaker) {
        if (breaker == null) {
            return;
        }
        try {
            List<String> destinatarios = parsearDestinatarios(breaker.Destinatarios_Correo__c);
            if (destinatarios.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[ICB_CircuitBreakerNotifier] Sin destinatarios configurados para ' + breaker.Nombre_Proceso__c);
                return;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            Id orgWideId = resolveOrgWideEmail(breaker.Remitente_OrgWideEmail__c);
            if (orgWideId != null) {
                mail.setOrgWideEmailAddressId(orgWideId);
            }
            mail.setToAddresses(destinatarios);
            mail.setSubject('Control de Flujos SAP ABIERTO: ' + breaker.Nombre_Proceso__c);
            mail.setPlainTextBody(construirCuerpo(breaker));
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerNotifier] Error enviando alerta para ' + breaker.Nombre_Proceso__c + ': ' + e.getMessage());
        }
    }

    public static void enviarAlertaCierre(Circuit_Breaker__c breaker, Integer totalBloqueados) {
        if (breaker == null) {
            return;
        }
        try {
            List<String> destinatarios = parsearDestinatarios(breaker.Destinatarios_Correo__c);
            if (destinatarios.isEmpty()) {
                System.debug(LoggingLevel.WARN, '[ICB_CircuitBreakerNotifier] Sin destinatarios configurados para ' + breaker.Nombre_Proceso__c);
                return;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            Id orgWideId = resolveOrgWideEmail(breaker.Remitente_OrgWideEmail__c);
            if (orgWideId != null) {
                mail.setOrgWideEmailAddressId(orgWideId);
            }
            mail.setToAddresses(destinatarios);
            mail.setSubject('Control de Flujos SAP CERRADO: ' + breaker.Nombre_Proceso__c);
            mail.setPlainTextBody(construirCuerpoCierre(breaker, totalBloqueados));
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerNotifier] Error enviando alerta de cierre para ' + breaker.Nombre_Proceso__c + ': ' + e.getMessage());
        }
    }

    @TestVisible
    private static String construirCuerpoCierre(Circuit_Breaker__c breaker, Integer totalBloqueados) {
        return 'El Control de Flujos del proceso "' + breaker.Nombre_Proceso__c + '" se cerro automaticamente (termino el enfriamiento).\n\n'
            + 'Total de intentos rechazados durante este corte: ' + (totalBloqueados == null ? 0 : totalBloqueados) + '\n\n'
            + 'El proceso vuelve a operar normal (los envios a SAP se reanudan), salvo que una nueva rafaga lo abra de nuevo.';
    }

    @TestVisible
    private static List<String> parsearDestinatarios(String raw) {
        List<String> resultado = new List<String>();
        if (String.isBlank(raw)) {
            return resultado;
        }
        for (String parte : raw.split('[;,]')) {
            String limpio = parte.trim();
            if (!String.isBlank(limpio)) {
                resultado.add(limpio);
            }
        }
        return resultado;
    }

    private static Id resolveOrgWideEmail(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        List<OrgWideEmailAddress> owa = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :address.trim() LIMIT 1
        ];
        return owa.isEmpty() ? null : owa[0].Id;
    }

    @TestVisible
    private static String construirCuerpo(Circuit_Breaker__c breaker) {
        Integer enfriamientoMin = breaker.Enfriamiento_Minutos__c != null ? breaker.Enfriamiento_Minutos__c.intValue() : 15;
        String cierreEstimado = breaker.Fecha_Apertura__c != null
            ? String.valueOf(breaker.Fecha_Apertura__c.addMinutes(enfriamientoMin))
            : 'desconocido';

        return 'El Control de Flujos del proceso "' + breaker.Nombre_Proceso__c + '" se abrio automaticamente.\n\n'
            + 'Intentos detectados en la ventana: ' + breaker.Contador_Ventana__c + '\n'
            + 'Umbral configurado: ' + breaker.Umbral_Intentos__c + ' intentos / ' + breaker.Ventana_Segundos__c + ' segundo(s)\n'
            + 'Hora de apertura: ' + String.valueOf(breaker.Fecha_Apertura__c) + '\n'
            + 'Minutos de enfriamiento configurados: ' + enfriamientoMin + '\n'
            + 'Cierre automatico estimado: ' + cierreEstimado + '\n\n'
            + 'Mientras el Control de Flujos este abierto, los intentos de envio a SAP de este proceso se bloquean automaticamente (sin llamar a SAP).\n'
            + 'Si la carga masiva que origino esto ya fue detenida, puedes forzar el cierre manualmente desde el panel "Control de Flujos SAP" (opcion "Reactivar ahora").';
    }
}