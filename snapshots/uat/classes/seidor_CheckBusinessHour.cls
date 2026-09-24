global with sharing class seidor_CheckBusinessHour {

    global class Output {

        @InvocableVariable(
            label='Dentro de Horario'
            description='Retorna true si la fecha y hora actual está dentro del horario de atención.'
        )
        global Boolean isBusinessHours;
    }

    @InvocableMethod(
        label='Validar Horario de Atención'
        description='Valida si la fecha y hora actual está dentro del Business Hours predeterminado. Si está fuera de horario, marca Fuera_de_horario__c = true en la MessagingSession activa.'
    )
    global static List<Output> checkBusinessHours(List<String> requests) {

        List<Output> results = new List<Output>();

        Output response = new Output();

        try {
            BusinessHours bh = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = true
                LIMIT 1
            ];

            response.isBusinessHours = BusinessHours.isWithin(
                bh.Id,
                System.now()
            );

        } catch (Exception e) {
            System.debug('Error al validar Business Hours: ' + e.getMessage());
            response.isBusinessHours = false;
        }

        // Si está fuera de horario → buscar y marcar la MessagingSession activa
        if (!response.isBusinessHours) {
            String phone = (!requests.isEmpty() && requests[0] != null)
                ? requests[0]
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
     *   → En el Bot Builder pasar el teléfono del cliente como primer elemento de requests.
     * Estrategia 2 (fallback) : sesión Active creada en los últimos 2 minutos.
     *   → Funciona sin ningún input desde el Bot.
     */
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

        // Fallback: sesión Active más reciente dentro de la ventana de 2 minutos
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
}