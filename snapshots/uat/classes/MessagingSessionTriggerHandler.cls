public with sharing class MessagingSessionTriggerHandler {

    private static final String STATUS_ENDED = 'Ended';

    /**
     * Esta versión NO usa addError sobre la transición a Ended.
     * En su lugar, marca un flag o crea una tarea de seguimiento
     * para que el agente vea pendiente la tipificación.
     * La UX la maneja el LWC reactivo.
     */
    public static void registrarPendienteTipificacion(
        List<MessagingSession> nuevas,
        Map<Id, MessagingSession> viejasMap
    ) {
        List<Task> tareasPendientes = new List<Task>();

        for (MessagingSession nueva : nuevas) {
            MessagingSession vieja = viejasMap.get(nueva.Id);

            Boolean cambioAEnded =
                nueva.Status == STATUS_ENDED &&
                vieja.Status != STATUS_ENDED;

            Boolean sinTipificar =
                String.isBlank((String) nueva.Tipificacion__c) ||
                String.isBlank((String) nueva.Sub_tipificacion__c);

            if (cambioAEnded && sinTipificar) {
                // Opción A: solo log, no bloquear
                System.debug(
                    LoggingLevel.WARN,
                    'MessagingSession ' + nueva.Id +
                    ' finalizada sin tipificación.'
                );

                // Opción B (opcional): crear Task de seguimiento
                // tareasPendientes.add(new Task(
                //     WhatId = nueva.Id,
                //     Subject = 'Tipificar sesión de mensajería',
                //     Status = 'Open',
                //     Priority = 'High',
                //     OwnerId = nueva.OwnerId
                // ));
            }
        }

        // if (!tareasPendientes.isEmpty()) insert tareasPendientes;
    }
}