public with sharing class seidor_CaseMonthlyReportController {

    @AuraEnabled(cacheable=false)
    public static seidor_CaseMonthlyReportDTO.ReportResult getReport() {
        return seidor_CaseMonthlyReportService.getReport();
    }

    @AuraEnabled(cacheable=false)
    public static seidor_CaseMonthlyReportDTO.CaseWrapper getCaseDetail(Id caseId) {
        return seidor_CaseMonthlyReportService.getCaseById(caseId);
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchUsers(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<User> users = [
            SELECT Name, Email FROM User
            WHERE Name LIKE :term AND IsActive = true AND Email != null
            ORDER BY Name
            LIMIT 10
        ];
        List<Map<String, String>> results = new List<Map<String, String>>();
        for (User u : users) {
            results.add(new Map<String, String>{ 'name' => u.Name, 'email' => u.Email });
        }
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static void sendCaseReportEmail(
        List<String> toAddresses,
        List<String> ccAddresses,
        String subject,
        String htmlBody,
        String attachmentName,
        String attachmentBase64
    ) {
        if (toAddresses == null || toAddresses.isEmpty()) {
            throw new AuraHandledException('Debe especificar al menos un destinatario.');
        }
        if (String.isBlank(subject)) {
            throw new AuraHandledException('El asunto es obligatorio.');
        }
        if (String.isBlank(htmlBody)) {
            throw new AuraHandledException('El cuerpo del correo no puede estar vacío.');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        if (ccAddresses != null && !ccAddresses.isEmpty()) {
            mail.setCcAddresses(ccAddresses);
        }
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false);

        if (String.isNotBlank(attachmentName) && String.isNotBlank(attachmentBase64)) {
            Messaging.EmailFileAttachment fileAttachment = new Messaging.EmailFileAttachment();
            fileAttachment.setFileName(attachmentName);
            fileAttachment.setContentType('application/vnd.ms-excel');
            fileAttachment.setBody(EncodingUtil.base64Decode(attachmentBase64));
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ fileAttachment });
        }

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }
}