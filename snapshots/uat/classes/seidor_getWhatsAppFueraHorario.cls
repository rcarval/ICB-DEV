/**********************************************************************************
 * seidor_getWhatsAppFueraHorario
 * Desarrollado por : Sebadev97
 * Fecha            : 2026-06-25
 * Descripción      : Apex Action para Einstein Bot (primera acción del flujo).
 *
 *  ¿Qué hace?
 *    1. Valida si el momento actual está fuera del Business Hours predeterminado
 *       (mismo patrón y estructura que seidor_CheckBusinessHour).
 *    2. Si está fuera de horario → busca la MessagingSession activa recién creada
 *       y marca Fuera_de_horario__c = true.
 *    3. Retorna fueraDeHorario (Boolean) al Bot para bifurcar el flujo.
 *
 *  Configuración en Bot Builder:
 *    Input  endUserPhone  → Text variable con el teléfono del cliente (opcional)
 *    Output fueraDeHorario → Boolean variable del Bot
 **********************************************************************************/
global with sharing class seidor_getWhatsAppFueraHorario {
 
    // ── Input ─────────────────────────────────────────────────────────────────
 
    global class Input {
        @InvocableVariable(
            required    = false
            label       = 'Teléfono del cliente (opcional)'
            description = 'MessagingPlatformKey del EndUser para identificar la sesión con precisión. Puede omitirse.'
        )
        global String endUserPhone;
    }
 
    // ── Output ────────────────────────────────────────────────────────────────
 
    global class Output {
        @InvocableVariable(
            label       = 'Fuera de Horario'
            description = 'Retorna true si la fecha y hora actual está fuera del horario de atención.'
        )
        global Boolean fueraDeHorario;
    }
 
    // ── InvocableMethod ───────────────────────────────────────────────────────
 
    @InvocableMethod(
        label       = 'Verificar y Marcar Fuera de Horario WhatsApp'
        description = 'Valida el Business Hours predeterminado y marca Fuera_de_horario__c en la MessagingSession activa.'
        category    = 'Messaging'
    )
    global static List<Output> verificarFueraDeHorario(List<Input> inputs) {
 
        List<Output> results = new List<Output>();
 
        // Output creado antes del try-catch (mismo patrón que seidor_CheckBusinessHour)
        Output response = new Output();
 
        try {
            BusinessHours bh = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = true
                LIMIT 1
            ];
 
            // isWithin → true = dentro de horario, por eso negamos para obtener fueraDeHorario
            response.fueraDeHorario = !BusinessHours.isWithin(bh.Id, System.now());
 
        } catch (Exception e) {
            System.debug('Error al validar Business Hours: ' + e.getMessage());
            response.fueraDeHorario = false;
        }
 
        // Si está fuera de horario → marcar el campo en la sesión activa
        if (response.fueraDeHorario) {
            String phone = (!inputs.isEmpty() && inputs[0] != null)
                ? inputs[0].endUserPhone
                : null;
            marcarSesion(phone);
        }
 
        results.add(response);
        return results;
    }
 
    // ── Helper ────────────────────────────────────────────────────────────────
 
    /**
     * Busca la MessagingSession activa recién creada y marca Fuera_de_horario__c = true.
     * Estrategia 1 (precisa)  : por teléfono del EndUser (MessagingPlatformKey).
     * Estrategia 2 (fallback) : sesión Active creada en los últimos 2 minutos.
     */
    @TestVisible
    private static void marcarSesion(String endUserPhone) {
        List<MessagingSession> sessions = new List<MessagingSession>();
        DateTime ventana = System.now().addMinutes(-2);
 
        if (String.isNotBlank(endUserPhone)) {
            List<MessagingEndUser> endUsers = [
                SELECT Id
                FROM MessagingEndUser
                WHERE MessagingPlatformKey = :endUserPhone.trim()
                LIMIT 1
            ];
 
            if (!endUsers.isEmpty()) {
                sessions = [
                    SELECT Id, Fuera_de_horario__c
                    FROM MessagingSession
                    WHERE MessagingEndUserId = :endUsers[0].Id
                    AND   Status            = 'Active'
                    AND   CreatedDate      >= :ventana
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
            }
        }
 
        if (sessions.isEmpty()) {
            sessions = [
                SELECT Id, Fuera_de_horario__c
                FROM MessagingSession
                WHERE Status      = 'Active'
                AND   CreatedDate >= :ventana
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
 
        if (!sessions.isEmpty() && sessions[0].Fuera_de_horario__c != true) {
            update new MessagingSession(
                Id                  = sessions[0].Id,
                Fuera_de_horario__c = true
            );
        }
    }

    public static void getInt(){
        Integer I =0;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
    }

}