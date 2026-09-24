public with sharing class seidor_WhatsAppCloudService {

    private static final Integer MAX_IMAGE_BYTES = 5 * 1024 * 1024;
    private static final Set<String> ALLOWED_MIME = new Set<String>{'image/png', 'image/jpeg'};

    public class UploadResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String error;
        @AuraEnabled public String publicUrl;
    }

    public class CloudException extends Exception {}

    @AuraEnabled(cacheable=false)
    public static UploadResult uploadImage(
        Id messagingSessionId,
        String base64Data,
        String fileName,
        String mimeType
    ) {
        UploadResult r = new UploadResult();
        try {
            validate(base64Data, mimeType);

            MessagingSession session = querySession(messagingSessionId);

            Id cvId = createContentVersion(base64Data, fileName, mimeType, session.Id);

            String publicUrl = createDistributionUrl(cvId);

            r.success = true;
            r.publicUrl = publicUrl;

        } catch (CloudException e) {
            r.success = false;
            r.error = e.getMessage();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '[seidor_WhatsAppCloudService.uploadImage] ' + e.getMessage());
            r.success = false;
            r.error = 'Error inesperado: ' + e.getMessage();
        }
        return r;
    }

    // ─── Validación ──────────────────────────────────────────────────────────────

    private static void validate(String base64Data, String mimeType) {
        if (String.isBlank(base64Data)) {
            throw new CloudException('No se recibió contenido de imagen.');
        }
        if (!ALLOWED_MIME.contains(mimeType)) {
            throw new CloudException('Tipo de archivo no soportado: ' + mimeType);
        }
        Integer approxBytes = (base64Data.length() * 3) / 4;
        if (approxBytes > MAX_IMAGE_BYTES) {
            throw new CloudException('La imagen supera el tamaño máximo de 5 MB.');
        }
    }

    // ─── Session ─────────────────────────────────────────────────────────────────

    private static MessagingSession querySession(Id sessionId) {
        List<MessagingSession> sessions = [
            SELECT Id, Status
            FROM MessagingSession
            WHERE Id = :sessionId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new CloudException('Sesión de mensajería no encontrada.');
        }
        if (sessions[0].Status == 'Ended') {
            throw new CloudException('La sesión ya está cerrada.');
        }
        return sessions[0];
    }

    // ─── ContentVersion + Distribution ──────────────────────────────────────────

    private static Id createContentVersion(
        String base64Data, String fileName, String mimeType, Id relatedId
    ) {
        String safeName = String.isNotBlank(fileName)
            ? fileName
            : 'whatsapp-' + Datetime.now().getTime() + '.' + (mimeType == 'image/png' ? 'png' : 'jpg');

        ContentVersion cv = new ContentVersion(
            Title = safeName,
            PathOnClient = safeName,
            VersionData = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = relatedId
        );

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE, new List<ContentVersion>{ cv }
        );
        insert decision.getRecords();

        return [SELECT Id FROM ContentVersion WHERE Id = :decision.getRecords()[0].Id LIMIT 1].Id;
    }

    private static String createDistributionUrl(Id cvId) {
        ContentDistribution dist = new ContentDistribution(
            Name = 'WhatsAppImage-' + cvId,
            ContentVersionId = cvId,
            PreferencesAllowViewInBrowser = true,
            PreferencesAllowOriginalDownload = false,
            PreferencesLinkLatestVersion = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false
        );
        insert dist;

        ContentDistribution result = [
            SELECT DistributionPublicUrl
            FROM ContentDistribution
            WHERE Id = :dist.Id LIMIT 1
        ];
        if (result == null || String.isBlank(result.DistributionPublicUrl)) {
            throw new CloudException('No se pudo generar la URL pública de la imagen.');
        }
        return result.DistributionPublicUrl;
    }
}