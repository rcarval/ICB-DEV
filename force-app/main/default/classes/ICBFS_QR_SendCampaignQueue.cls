/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-25
Descripción : Queueable que envía correos con QR por CampaignMember.
              Token viene de CampaignMember.QR_Token__c.
              Destinatario puede ser Lead, Contact o Account (campo email dinámico).
              Header/Footer por URL pública (Outlook safe).
              Además:
                - Marca QR_Enviado__c = true SOLO si el email se envió OK.
**********************************************************************************/
public with sharing class ICBFS_QR_SendCampaignQueue implements Queueable {

    // ✅ Defaults (si no los mandas desde Flow/Invocable)
    private static final String DEFAULT_OPENDAY_HEADER_URL =
        'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_HEADER.png';
    private static final String DEFAULT_OPENDAY_FOOTER_URL =
        'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_FOOTER.png';

    // Remitente deseado (requiere Org-Wide Email Address configurada con este correo).
    private static final String ORG_WIDE_EMAIL = 'info@icbfs.cl';
    private static Id cachedOrgWideEmailId;

    private Id campaignId;
    private String accountEmailFieldApi;
    private String landingBaseUrl;
    private String subject;

    // ✅ configurables desde Flow (vía Invocable)
    private String headerUrlInput;
    private String footerUrlInput;

    // ✅ Constructor legacy (compatibilidad con tests/flows viejos de 4 params)
    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject
    ) {
        this(
            campaignId,
            accountEmailFieldApi,
            landingBaseUrl,
            subject,
            null, // headerUrl -> usa default
            null  // footerUrl -> usa default
        );
    }

    // ✅ Constructor nuevo (6 params) para permitir header/footer desde Flow
    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl
    ) {
        this.campaignId = campaignId;
        this.accountEmailFieldApi = accountEmailFieldApi;
        this.landingBaseUrl = landingBaseUrl;
        this.subject = subject;
        this.headerUrlInput = headerUrl;
        this.footerUrlInput = footerUrl;
    }

    public void execute(QueueableContext context) {

        if (campaignId == null) return;

        String finalSubject = String.isBlank(subject)
            ? 'ICB Food Service OPENDAY'
            : subject.trim();

        String landing = String.isBlank(landingBaseUrl)
            ? 'https://energy-saas-7178.my.site.com/openday'
            : landingBaseUrl.trim();

        // normalizamos landing con slash final
        if (!landing.endsWith('/')) landing += '/';

        Id orgWideId = resolveOrgWideEmail();

        List<CampaignMember> cms = [
            SELECT Id, QR_Token__c, QR_Enviado__c,
                   LeadId, Lead.Email,
                   ContactId, Contact.Email,
                   AccountId
            FROM CampaignMember
            WHERE CampaignId = :campaignId
        ];

        if (cms.isEmpty()) return;

        // Accounts con campo email dinámico
        Set<Id> accIds = new Set<Id>();
        for (CampaignMember cm : cms) {
            if (cm.AccountId != null) accIds.add(cm.AccountId);
        }

        Map<Id, Account> accMap = new Map<Id, Account>();
        if (!accIds.isEmpty()) {

            if (String.isBlank(accountEmailFieldApi)) {
                throw new AuraHandledException('Debes indicar el API Name del campo Email en Account (por ejemplo Email__c).');
            }

            String fieldApi = accountEmailFieldApi.trim();
            String soql = 'SELECT Id, ' + fieldApi + ' FROM Account WHERE Id IN :accIds';

            for (SObject sob : Database.query(soql)) {
                accMap.put((Id)sob.get('Id'), (Account)sob);
            }
        }

        // Header/Footer: usa lo que venga; si viene vacío, usa default.
        String headerUrl = sanitizeUrl(String.isBlank(headerUrlInput) ? DEFAULT_OPENDAY_HEADER_URL : headerUrlInput);
        String footerUrl = sanitizeUrl(String.isBlank(footerUrlInput) ? DEFAULT_OPENDAY_FOOTER_URL : footerUrlInput);

        List<Messaging.SingleEmailMessage> batchEmails = new List<Messaging.SingleEmailMessage>();
        List<Id> batchCmIds = new List<Id>();

        for (CampaignMember cm : cms) {

            // Candado anti reenvío
            if (cm.QR_Enviado__c == true) continue;

            if (String.isBlank(cm.QR_Token__c)) continue;

            String toEmail = resolveEmail(cm, accMap, accountEmailFieldApi);
            if (String.isBlank(toEmail)) continue;

            String token = cm.QR_Token__c.trim();

            // landing/?token=...
            String landingWithToken =
                landing + '?token=' + EncodingUtil.urlEncode(token, 'UTF-8');

            // QR externo
            String qrImg =
                'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=' +
                EncodingUtil.urlEncode(landingWithToken, 'UTF-8');

            String htmlBody = buildHtml(qrImg, token, headerUrl, footerUrl);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            if (orgWideId != null) {
                mail.setOrgWideEmailAddressId(orgWideId);
            }
            mail.setToAddresses(new List<String>{ toEmail.trim() });
            mail.setSubject(finalSubject);
            mail.setHtmlBody(htmlBody);
            mail.setSaveAsActivity(false);

            batchEmails.add(mail);
            batchCmIds.add(cm.Id);

            if (batchEmails.size() == 50) {
                sendAndMark(batchEmails, batchCmIds);
                batchEmails.clear();
                batchCmIds.clear();
            }
        }

        if (!batchEmails.isEmpty()) {
            sendAndMark(batchEmails, batchCmIds);
        }
    }

    private static void sendAndMark(
        List<Messaging.SingleEmailMessage> emails,
        List<Id> cmIdsInSameOrder
    ) {
        if (emails == null || emails.isEmpty()) return;

        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

        List<CampaignMember> toUpdate = new List<CampaignMember>();
        Integer n = Math.min(results.size(), cmIdsInSameOrder.size());

        for (Integer i = 0; i < n; i++) {
            Messaging.SendEmailResult r = results[i];
            if (r != null && r.isSuccess()) {
                toUpdate.add(new CampaignMember(
                    Id = cmIdsInSameOrder[i],
                    QR_Enviado__c = true
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static String resolveEmail(
        CampaignMember cm,
        Map<Id, Account> accMap,
        String accountEmailFieldApi
    ) {
        if (cm.LeadId != null && cm.Lead != null) return cm.Lead.Email;
        if (cm.ContactId != null && cm.Contact != null) return cm.Contact.Email;

        if (cm.AccountId != null) {
            Account a = accMap.get(cm.AccountId);
            if (a != null && !String.isBlank(accountEmailFieldApi)) {
                Object val = a.get(accountEmailFieldApi.trim());
                if (val != null) return String.valueOf(val);
            }
        }
        return null;
    }

    private static String buildHtml(String qrImgUrl, String token, String headerUrl, String footerUrl) {

        String headerTag = String.isBlank(headerUrl)
            ? ''
            : '<img src="' + escapeHtml(headerUrl) + '" alt="OPENDAY Header" width="100%" style="display:block; margin:0 0 20px 0;" />';

        String footerTag = String.isBlank(footerUrl)
            ? ''
            : '<img src="' + escapeHtml(footerUrl) + '" alt="OPENDAY Footer" width="100%" style="display:block; margin:20px 0 0 0;" />';

        return ''
            + '<html>'
            + '<body style="margin:0; padding:0; font-family: Arial, sans-serif; color: white; background-color: #1a1a1a;">'
            + '<div style="max-width: 900px; margin: 0 auto; padding: 20px; text-align: center;">'
            + headerTag
            + '<p style="margin:0 0 12px 0; font-size:16px;">Presenta el código QR al llegar 👇</p>'
            + '<img src="' + escapeHtml(qrImgUrl) + '" alt="Código QR" width="300" height="300" style="border:1px solid #fff; border-radius:8px;" />'
            + '<p style="margin:12px 0 0 0; font-size:12px; color:#cfcfcf;">Token: ' + escapeHtml(token) + '</p>'
            + footerTag
            + '</div>'
            + '</body>'
            + '</html>';
    }

    private static Id resolveOrgWideEmail() {
        if (cachedOrgWideEmailId != null) return cachedOrgWideEmailId;

        List<OrgWideEmailAddress> ow = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL
            LIMIT 1
        ];
        if (!ow.isEmpty()) {
            cachedOrgWideEmailId = ow[0].Id;
        }
        return cachedOrgWideEmailId;
    }

    private static String sanitizeUrl(String url) {
        if (String.isBlank(url)) return null;

        String u = url.trim();

        // arregla typos típicos
        if (u.startsWith('hhttps://')) {
            u = 'https://' + u.substring('hhttps://'.length());
        }

        // evita terminar con '?' (typo típico en resource)
        while (u.endsWith('?')) {
            u = u.substring(0, u.length() - 1);
        }

        return u;
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        return s.replace('&','&amp;')
                .replace('<','&lt;')
                .replace('>','&gt;')
                .replace('"','&quot;')
                .replace('\'','&#39;');
    }
}