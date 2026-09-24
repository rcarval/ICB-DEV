public with sharing class MessagingBotAssignmentValidator {

    public class Request {

        @InvocableVariable(required=true)
        public Id messagingSessionId;
    }

    public class Response {

        @InvocableVariable
        public Boolean asignacionBotActiva;
    }

    @InvocableMethod(
        label='Validate Bot Assignment'
        description='Returns true if Asignacion_bot__c is enabled'
        callout = true
    )
    public static List<Response> validateBotAssignment(
        List<Request> requests
    ) {

        List<Response> responses = new List<Response>();

        if(requests == null || requests.isEmpty()) {
            return responses;
        }

        for(Request req : requests) {

            Response res = new Response();

            try {

                MessagingSession ms = [
                    SELECT Asignaci_n_bot__c
                    FROM MessagingSession
                    WHERE Id = :req.messagingSessionId
                    LIMIT 1
                ];

                res.asignacionBotActiva = ms.Asignaci_n_bot__c;

            } catch(Exception ex) {

                res.asignacionBotActiva = false;
            }

            responses.add(res);
        }

        return responses;
    }
}