global class seidor_CheckBusinessHoursExt {

    global class CheckBusinessHoursRequest {
        @InvocableVariable(label='Business Hours Name' required=true)
        global String businessHoursName;

        @InvocableVariable(label='Messaging Session ID')
        global Id messagingSessionId;
    }

    @InvocableMethod(
        label='Check Business Hours with Survey Pending Validation'
        description='Si la sesión tiene Esperando_encuesta__c = false, valida el horario laboral. Si es true o no tiene sesión, retorna false.'
    )
    global static List<Boolean> checkBusinessHoursWithSurveyCheck(
        List<CheckBusinessHoursRequest> requests
    ) {
        Set<Id> sessionIds = new Set<Id>();
        for (CheckBusinessHoursRequest req : requests) {
            if (req.messagingSessionId != null) {
                sessionIds.add(req.messagingSessionId);
            }
        }

        Map<Id, Boolean> sessionEsperaMap = new Map<Id, Boolean>();
        if (!sessionIds.isEmpty()) {
            Map<Id, Id> sessionToEndUser = new Map<Id, Id>();
            Set<Id> endUserIds = new Set<Id>();

            for (MessagingSession ms : [
                SELECT Id, MessagingEndUserId
                FROM MessagingSession
                WHERE Id IN :sessionIds
            ]) {
                sessionToEndUser.put(ms.Id, ms.MessagingEndUserId);
                if (ms.MessagingEndUserId != null) {
                    endUserIds.add(ms.MessagingEndUserId);
                }
            }

            Map<Id, MessagingEndUser> endUsers = new Map<Id, MessagingEndUser>();
            if (!endUserIds.isEmpty()) {
                endUsers = new Map<Id, MessagingEndUser>([
                    SELECT Id, Esperando_encuesta__c
                    FROM MessagingEndUser
                    WHERE Id IN :endUserIds
                ]);
            }

            for (Id sid : sessionIds) {
                Id euid = sessionToEndUser.get(sid);
                if (euid != null && endUsers.containsKey(euid)) {
                    sessionEsperaMap.put(sid, endUsers.get(euid).Esperando_encuesta__c);
                } else {
                    sessionEsperaMap.put(sid, null);
                }
            }
        }

        List<Boolean> results = new List<Boolean>();
        for (CheckBusinessHoursRequest req : requests) {
            Boolean esperando = sessionEsperaMap.get(req.messagingSessionId);

            if (req.messagingSessionId == null || esperando == false) {
                if (req.businessHoursName != null) {
                    List<BusinessHours> businessHours = [
                        SELECT Id, Name
                        FROM BusinessHours
                        WHERE Name = :req.businessHoursName
                        AND IsActive = true
                    ];

                    if (businessHours.size() == 1) {
                        results.add(
                            seidor_CheckBusinessHours.checkBusinessHoursById(businessHours[0].Id)
                        );
                    } else {
                        results.add(false);
                    }
                } else {
                    results.add(false);
                }
            } else {
                results.add(false);
            }
        }

        return results;
    }
}