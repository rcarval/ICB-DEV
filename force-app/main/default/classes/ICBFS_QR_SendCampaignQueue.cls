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
                - Llama Messaging.sendEmail() UNA SOLA VEZ por ejecución para
                  respetar el límite de 10 invocaciones por transacción.
**********************************************************************************/
public with sharing class ICBFS_QR_SendCampaignQueue implements Queueable {

    public static final String SEND_MODE_MASSIVE = 'massive';
    public static final String SEND_MODE_REMINDER = 'reminder';

    private static final String DEFAULT_OPENDAY_HEADER_URL =
        'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_HEADER.png';
    private static final String DEFAULT_OPENDAY_FOOTER_URL =
        'https://cdn.jsdelivr.net/gh/tron0110/icbfs-openday-assets/ICBFS_OPENDAY_FOOTER.png';

    private static final String ORG_WIDE_EMAIL = 'info@icbfs.cl';
    private static final String ACCOUNT_CONTACT_FALLBACK_FIELD = 'Datos_de_Contacto_Principal__c';
    private static final String EMAIL_PATTERN = '^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$';
    private static Id cachedOrgWideEmailId;

    private Id campaignId;
    private String accountEmailFieldApi;
    private String landingBaseUrl;
    private String subject;
    private String headerUrlInput;
    private String footerUrlInput;
    private String mapsUrlInput;
    private String sendMode;
    private Set<Id> campaignMemberIds;

    // Constructor legacy (4 params)
    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject
    ) {
        this(campaignId, accountEmailFieldApi, landingBaseUrl, subject, null, null);
    }

    // Constructor completo (6 params)
    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl
    ) {
        this(campaignId, accountEmailFieldApi, landingBaseUrl, subject, headerUrl, footerUrl, null, SEND_MODE_MASSIVE);
    }

    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl,
        String sendMode
    ) {
        this(campaignId, accountEmailFieldApi, landingBaseUrl, subject, headerUrl, footerUrl, null, sendMode, null);
    }

    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl,
        String mapsUrl,
        String sendMode
    ) {
        this(campaignId, accountEmailFieldApi, landingBaseUrl, subject, headerUrl, footerUrl, mapsUrl, sendMode, null);
    }

    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl,
        String sendMode,
        Set<Id> campaignMemberIds
    ) {
        this(campaignId, accountEmailFieldApi, landingBaseUrl, subject, headerUrl, footerUrl, null, sendMode, campaignMemberIds);
    }

    public ICBFS_QR_SendCampaignQueue(
        Id campaignId,
        String accountEmailFieldApi,
        String landingBaseUrl,
        String subject,
        String headerUrl,
        String footerUrl,
        String mapsUrl,
        String sendMode,
        Set<Id> campaignMemberIds
    ) {
        this.campaignId           = campaignId;
        this.accountEmailFieldApi = accountEmailFieldApi;
        this.landingBaseUrl       = landingBaseUrl;
        this.subject              = subject;
        this.headerUrlInput       = headerUrl;
        this.footerUrlInput       = footerUrl;
        this.mapsUrlInput         = mapsUrl;
        this.sendMode             = normalizeSendMode(sendMode);
        this.campaignMemberIds    = campaignMemberIds == null ? null : new Set<Id>(campaignMemberIds);
    }

    public void execute(QueueableContext context) {

        if (campaignId == null) return;

        Boolean isReminder = sendMode == SEND_MODE_REMINDER;
        String finalSubject = String.isBlank(subject) ? 'ICB Food Service OPENDAY' : subject.trim();
        if (isReminder && finalSubject == 'ICB Food Service OPENDAY') {
            finalSubject = 'Recordatorio ICB Food Service OPENDAY';
        }

        String landing = String.isBlank(landingBaseUrl)
            ? 'https://energy-saas-7178.my.site.com/openday'
            : landingBaseUrl.trim();
        if (!landing.endsWith('/')) landing += '/';

        Id orgWideId = resolveOrgWideEmail();

        List<CampaignMember> cms;
        if (campaignMemberIds != null && !campaignMemberIds.isEmpty()) {
            cms = [
                SELECT Id, QR_Token__c, QR_Enviado__c,
                       LeadId, Lead.Email,
                       ContactId, Contact.Email,
                       AccountId
                FROM CampaignMember
                WHERE CampaignId = :campaignId
                AND Id IN :campaignMemberIds
            ];
        } else {
            cms = [
                SELECT Id, QR_Token__c, QR_Enviado__c,
                       LeadId, Lead.Email,
                       ContactId, Contact.Email,
                       AccountId
                FROM CampaignMember
                WHERE CampaignId = :campaignId
            ];
        }

        if (cms.isEmpty()) return;

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
            Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
            if (!accountFields.containsKey(fieldApi)) {
                throw new AuraHandledException('El campo de email configurado no existe en Account: ' + fieldApi);
            }
            Set<String> selectFields = new Set<String>{
                'Id', 'ParentId', fieldApi, ACCOUNT_CONTACT_FALLBACK_FIELD,
                'Parent.' + fieldApi, 'Parent.' + ACCOUNT_CONTACT_FALLBACK_FIELD
            };
            String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
                ' FROM Account WHERE Id IN :accIds';
            for (SObject sob : Database.query(soql)) {
                accMap.put((Id) sob.get('Id'), (Account) sob);
            }
        }

        String headerUrl = sanitizeUrl(String.isBlank(headerUrlInput) ? DEFAULT_OPENDAY_HEADER_URL : headerUrlInput);
        String footerUrl = sanitizeUrl(String.isBlank(footerUrlInput) ? DEFAULT_OPENDAY_FOOTER_URL : footerUrlInput);
        String mapsUrl = sanitizeUrl(mapsUrlInput);

        // Acumula TODOS los correos y llama sendEmail() una sola vez
        List<Messaging.SingleEmailMessage> allEmails = new List<Messaging.SingleEmailMessage>();
        List<Id> allCmIds = new List<Id>();

        for (CampaignMember cm : cms) {

            if (!isReminder && cm.QR_Enviado__c == true) continue;
            if (String.isBlank(cm.QR_Token__c)) continue;

            String toEmail = resolveEmail(cm, accMap, accountEmailFieldApi);
            if (String.isBlank(toEmail)) continue;

            String token = cm.QR_Token__c.trim();
            String landingWithToken = landing + '?token=' + EncodingUtil.urlEncode(token, 'UTF-8');
            String qrImg =
                'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=' +
                EncodingUtil.urlEncode(landingWithToken, 'UTF-8');

            String htmlBody = buildHtml(qrImg, token, headerUrl, footerUrl, mapsUrl);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            if (orgWideId != null) mail.setOrgWideEmailAddressId(orgWideId);
            mail.setToAddresses(new List<String>{ toEmail.trim() });
            mail.setSubject(finalSubject);
            mail.setHtmlBody(htmlBody);
            mail.setSaveAsActivity(false);

            allEmails.add(mail);
            allCmIds.add(cm.Id);
        }

        // Una sola invocación: nunca llega al límite de 10
        if (!allEmails.isEmpty()) {
            sendAndMark(allEmails, allCmIds);
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
            } else {
                logSendFailure(cmIdsInSameOrder[i], r);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    @TestVisible
    private static String resolveEmail(
        CampaignMember cm,
        Map<Id, Account> accMap,
        String accountEmailFieldApi
    ) {
        if (cm.LeadId != null && cm.Lead != null) {
            return firstValidEmail(new List<Object>{ cm.Lead.Email });
        }
        if (cm.ContactId != null && cm.Contact != null) {
            return firstValidEmail(new List<Object>{ cm.Contact.Email });
        }

        if (cm.AccountId != null) {
            Account a = accMap.get(cm.AccountId);
            if (a != null && !String.isBlank(accountEmailFieldApi)) {
                Account parentAccount = (Account) a.getSObject('Parent');
                return firstValidEmail(new List<Object>{
                    a.get(accountEmailFieldApi.trim()),
                    a.get(ACCOUNT_CONTACT_FALLBACK_FIELD),
                    parentAccount == null ? null : parentAccount.get(accountEmailFieldApi.trim()),
                    parentAccount == null ? null : parentAccount.get(ACCOUNT_CONTACT_FALLBACK_FIELD)
                });
            }
        }
        return null;
    }

    @TestVisible
    private static String firstValidEmail(List<Object> candidates) {
        if (candidates == null) return null;
        for (Object candidate : candidates) {
            if (candidate == null) continue;
            String email = String.valueOf(candidate).trim();
            if (!String.isBlank(email) && Pattern.matches(EMAIL_PATTERN, email)) return email;
        }
        return null;
    }

    @TestVisible
    private static String buildHtml(String qrImgUrl, String token, String headerUrl, String footerUrl, String mapsUrl) {

        String headerTag = String.isBlank(headerUrl)
            ? ''
            : '<img src="' + escapeHtml(headerUrl) + '" alt="OPENDAY Header" width="100%" style="display:block; margin:0 0 20px 0;" />';

        String footerTag = String.isBlank(footerUrl)
            ? ''
            : '<img src="' + escapeHtml(footerUrl) + '" alt="OPENDAY Footer" width="100%" style="display:block; margin:20px 0 0 0;" />';

        String mapsButtonTag = String.isBlank(mapsUrl)
            ? ''
            : '<div style="margin:20px 0 0 0;"><a href="' + escapeHtml(mapsUrl) + '" '
                + 'style="display:inline-block; background-color:#ffffff; color:#111111; text-decoration:none; '
                + 'font-weight:bold; font-size:16px; padding:12px 24px; border-radius:999px;">Como llegar</a></div>';

        return ''
            + '<html>'
            + '<body style="margin:0; padding:0; font-family: Arial, sans-serif; color: white; background-color: #1a1a1a;">'
            + '<div style="max-width: 900px; margin: 0 auto; padding: 20px; text-align: center;">'
            + headerTag
            + '<p style="margin:0 0 12px 0; font-size:16px;">Presenta el código QR al llegar 👇</p>'
            + '<img src="' + escapeHtml(qrImgUrl) + '" alt="Código QR" width="300" height="300" style="border:1px solid #fff; border-radius:8px;" />'
            + '<p style="margin:12px 0 0 0; font-size:12px; color:#cfcfcf;">Token: ' + escapeHtml(token) + '</p>'
            + mapsButtonTag
            + footerTag
            + '</div>'
            + '</body>'
            + '</html>';
    }

    private static void logSendFailure(Id campaignMemberId, Messaging.SendEmailResult result) {
        if (result == null) {
            System.debug(LoggingLevel.ERROR, 'ICBFS_QR_SEND_FAIL cmId=' + campaignMemberId + ' result=null');
            return;
        }
        Messaging.SendEmailError[] errors = result.getErrors();
        if (errors == null || errors.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'ICBFS_QR_SEND_FAIL cmId=' + campaignMemberId + ' without error detail');
            return;
        }
        for (Messaging.SendEmailError err : errors) {
            System.debug(LoggingLevel.ERROR, 'ICBFS_QR_SEND_FAIL cmId=' + campaignMemberId
                + ' status=' + err.getStatusCode() + ' message=' + err.getMessage());
        }
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

        if (u.startsWith('hhttps://')) {
            u = 'https://' + u.substring('hhttps://'.length());
        }

        while (u.endsWith('?')) {
            u = u.substring(0, u.length() - 1);
        }

        return u;
    }

    private static String normalizeSendMode(String value) {
        if (String.isBlank(value)) return SEND_MODE_MASSIVE;
        String normalized = value.trim().toLowerCase();
        if (normalized == SEND_MODE_REMINDER || normalized == 'recordatorio') return SEND_MODE_REMINDER;
        return SEND_MODE_MASSIVE;
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;')
                .replace('\'', '&#39;');
    }
}