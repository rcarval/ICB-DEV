/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-11
Descripción : Invocable para iniciar envío masivo de QR por Campaña (CampaignMember).
              Soporta Lead, Contact y Account (usa campo email dinámico en Account).
**********************************************************************************/
public with sharing class ICBFS_QR_SendCampaignInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id campaignId;

        @InvocableVariable(required=true)
        public String accountEmailFieldApi;

        @InvocableVariable(required=false)
        public String landingBaseUrl;

        @InvocableVariable(required=false)
        public String subject;

        // ✅ NUEVO: para ingresarlo desde Flow (como en tu imagen)
        @InvocableVariable(required=false)
        public String headerUrl;

        @InvocableVariable(required=false)
        public String footerUrl;
    }

    @InvocableMethod(
        label='ICBFS - Enviar QR por Campaña (Miembros)'
        description='Envía correo con QR a CampaignMembers (Lead/Contact/Account) usando token CampaignMember.QR_Token__c.'
    )
    public static void enviar(List<Request> requests) {

        if (requests == null || requests.isEmpty()) return;

        Request req = requests[0];
        
        if (req.campaignId == null) {
            throw new AuraHandledException('El campaignId no puede ser nulo.');
        }

        if (String.isBlank(req.accountEmailFieldApi)) {
            throw new AuraHandledException('Debes indicar el API Name del campo Email en Account (por ejemplo Email__c).');
        }

        System.enqueueJob(
            new ICBFS_QR_SendCampaignQueue(
                req.campaignId,
                req.accountEmailFieldApi,
                req.landingBaseUrl,
                req.subject,
                req.headerUrl,   
                req.footerUrl    
            )
        );
    }
}