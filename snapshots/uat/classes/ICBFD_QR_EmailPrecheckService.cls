/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-12
Descripción : Servicio Invocable para Flow: calcula cuántos correos se enviarán
              y devuelve límites/capacidad estimada para control antes del envío.
**********************************************************************************/
public with sharing class ICBFD_QR_EmailPrecheckService {

    public class Request {
        @InvocableVariable(required=true)
        public Id campaignId;

        @InvocableVariable(required=true)
        public String accountEmailFieldApi;
    }

    public class Response {
        @InvocableVariable public Integer totalCampaignMembersNoEnviados;
        @InvocableVariable public Integer totalConToken;
        @InvocableVariable public Integer totalConEmailResoluble;
        @InvocableVariable public Integer totalAEnviar;
        @InvocableVariable public Integer limiteDiarioConfigurado; // estimado (default 5000)
        @InvocableVariable public String alerta;
    }

    @InvocableMethod(label='ICBFD QR - Precheck Envío Correos' description='Calcula volumen de envío y alerta por límite diario.')
    public static List<Response> run(List<Request> requests) {

        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) return out;

        for (Request req : requests) {
            Response r = new Response();
            r.limiteDiarioConfigurado = 5000; // baseline típico (prod). Ajustable.

            if (req == null || req.campaignId == null) {
                r.alerta = 'Falta campaignId.';
                out.add(r);
                continue;
            }

            List<CampaignMember> cms = [
                SELECT Id, QR_Token__c, QR_Enviado__c,
                       LeadId, Lead.Email,
                       ContactId, Contact.Email,
                       AccountId
                FROM CampaignMember
                WHERE CampaignId = :req.campaignId
                AND QR_Enviado__c = false
            ];

            r.totalCampaignMembersNoEnviados = cms.size();

            // Accounts con campo email dinámico
            Set<Id> accIds = new Set<Id>();
            for (CampaignMember cm : cms) if (cm.AccountId != null) accIds.add(cm.AccountId);

            Map<Id, Account> accMap = new Map<Id, Account>();
            if (!accIds.isEmpty() && !String.isBlank(req.accountEmailFieldApi)) {
                String soql = 'SELECT Id, ' + req.accountEmailFieldApi + ' FROM Account WHERE Id IN :accIds';
                for (SObject sob : Database.query(soql)) {
                    accMap.put((Id)sob.get('Id'), (Account)sob);
                }
            }

            Integer conToken = 0, conEmail = 0, aEnviar = 0;

            for (CampaignMember cm : cms) {
                if (!String.isBlank(cm.QR_Token__c)) conToken++;

                String email = resolveEmail(cm, accMap, req.accountEmailFieldApi);
                if (!String.isBlank(email)) conEmail++;

                if (!String.isBlank(cm.QR_Token__c) && !String.isBlank(email)) {
                    aEnviar++;
                }
            }

            r.totalConToken = conToken;
            r.totalConEmailResoluble = conEmail;
            r.totalAEnviar = aEnviar;

            if (aEnviar > r.limiteDiarioConfigurado) {
                r.alerta = 'ALERTA: El envío (' + aEnviar + ') supera el límite diario configurado (' + r.limiteDiarioConfigurado + ').';
            } else if (aEnviar == 0) {
                r.alerta = 'No hay destinatarios válidos (sin token o sin email).';
            } else {
                r.alerta = 'OK para enviar.';
            }

            out.add(r);
        }

        return out;
    }

    private static String resolveEmail(CampaignMember cm, Map<Id, Account> accMap, String accountEmailFieldApi) {
        if (cm.LeadId != null && cm.Lead != null) return cm.Lead.Email;
        if (cm.ContactId != null && cm.Contact != null) return cm.Contact.Email;

        if (cm.AccountId != null && accMap != null) {
            Account a = accMap.get(cm.AccountId);
            if (a != null && !String.isBlank(accountEmailFieldApi)) {
                Object val = a.get(accountEmailFieldApi);
                if (val != null) return String.valueOf(val);
            }
        }
        return null;
    }
}