/**********************************************************************************
 * ICB_FirmaDigitalServiceImpl
 * Servicio API Firma Digital: upload, PUT S3, status, download. Named Credential ICB_FirmaDigital.
 * SEIDOR - RCG
 **********************************************************************************/
public with sharing class ICB_FirmaDigitalServiceImpl {

    private static final String NAMED_CREDENTIAL = 'ICB_FirmaDigital';
    private static final String PATH_UPLOAD = '/v1/firma/upload';
    private static final String PATH_DOWNLOAD = '/v1/firma/download';
    private static final String PATH_STATUS = '/v1/firma/status/';
    private static final Integer TIMEOUT_MS = 120000;
    private static final String LOG_PREFIX = '[ICB_FirmaDigital]';
    private static final Integer LOG_BODY_MAX_LENGTH = 500;

    public class FirmanteDto {
        public String nombre;
        public String email;
        public String rut;
        public String telefono;
    }

    public class SignatureConfigDto {
        public String nombre;
        public List<FirmanteDto> firmantes;
    }

    public class UploadRequestDto {
        public String contratoId;
        public String fileName;
        public SignatureConfigDto signatureConfig;
    }

    public class UploadResponseDto {
        public Boolean success;
        public String contratoId;
        public String uploadUrl;
        public String expiresAt;
    }

    public class StatusResponseDto {
        public Boolean success;
        public StatusDataDto data;
        public String error;
    }

    public class StatusDataDto {
        public String contratoId;
        public String status;
        public String tufirmaDocumentId;
        public String uploadUrl;
        public String signedDocumentUrl;
        public String fileName;
        public String createdAt;
        public String updatedAt;
    }

    public class DownloadRequestDto {
        public String contratoId;
    }

    public class DownloadResponseDto {
        public Boolean success;
        public String contratoId;
        public String downloadUrl;
        public String expiresAt;
        public String error;
    }

    public static UploadResponseDto solicitarUploadUrl(UploadRequestDto request) {
        logInfo('solicitarUploadUrl | inicio');
        validarUploadRequest(request);
        String body = JSON.serialize(request);
        HttpResponse res = ejecutarCalloutApi(PATH_UPLOAD, 'POST', body);
        validarRespuestaExito(res, 'solicitarUploadUrl');
        UploadResponseDto dto = (UploadResponseDto) JSON.deserialize(res.getBody(), UploadResponseDto.class);
        logInfo('solicitarUploadUrl | ok | contratoId=' + dto.contratoId);
        return dto;
    }

    public static void subirPdfAUploadUrl(String uploadUrl, Blob pdfBody) {
        logInfo('subirPdfAUploadUrl | inicio');
        validarUploadUrlYPdf(uploadUrl, pdfBody);
        HttpResponse res = ejecutarPutBinario(uploadUrl, pdfBody);
        validarRespuestaExito(res, 'subirPdfAUploadUrl');
        logInfo('subirPdfAUploadUrl | ok');
    }

    public static StatusResponseDto consultarEstado(String contratoId) {
        logInfo('consultarEstado | inicio | contratoId=' + contratoId);
        validarContratoId(contratoId);
        String path = PATH_STATUS + EncodingUtil.urlEncode(contratoId, 'UTF-8');
        HttpResponse res = ejecutarCalloutApi(path, 'GET', null);
        validarRespuestaExito(res, 'consultarEstado');
        StatusResponseDto dto = (StatusResponseDto) JSON.deserialize(res.getBody(), StatusResponseDto.class);
        logInfo('consultarEstado | ok | status=' + (dto.data != null ? dto.data.status : ''));
        return dto;
    }

    public static DownloadResponseDto solicitarUrlDescarga(String contratoId) {
        logInfo('solicitarUrlDescarga | inicio | contratoId=' + contratoId);
        validarContratoId(contratoId);
        DownloadRequestDto bodyDto = new DownloadRequestDto();
        bodyDto.contratoId = contratoId;
        String body = JSON.serialize(bodyDto);
        HttpResponse res = ejecutarCalloutApi(PATH_DOWNLOAD, 'POST', body);
        validarRespuestaExito(res, 'solicitarUrlDescarga');
        DownloadResponseDto dto = (DownloadResponseDto) JSON.deserialize(res.getBody(), DownloadResponseDto.class);
        logInfo('solicitarUrlDescarga | ok');
        return dto;
    }

    private static void validarUploadRequest(UploadRequestDto request) {
        if (request == null || String.isBlank(request.contratoId) || String.isBlank(request.fileName)) {
            throw new ICB_FirmaDigitalException('contratoId y fileName son obligatorios');
        }
    }

    private static void validarContratoId(String contratoId) {
        if (String.isBlank(contratoId)) {
            throw new ICB_FirmaDigitalException('contratoId es obligatorio');
        }
    }

    private static void validarUploadUrlYPdf(String uploadUrl, Blob pdfBody) {
        if (String.isBlank(uploadUrl) || pdfBody == null || pdfBody.size() == 0) {
            throw new ICB_FirmaDigitalException('uploadUrl y pdfBody son obligatorios');
        }
    }

    private static HttpResponse ejecutarCalloutApi(String path, String method, String requestBody) {
        String endpoint = 'callout:' + NAMED_CREDENTIAL + path;
        logInfo('ejecutarCalloutApi | endpoint=' + endpoint + ' | method=' + method);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setTimeout(TIMEOUT_MS);
        if (requestBody != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(requestBody);
        }
        Http http = new Http();
        HttpResponse res = http.send(req);
        logInfo('ejecutarCalloutApi | response status=' + res.getStatusCode() + ' ' + res.getStatus());
        return res;
    }

    private static HttpResponse ejecutarPutBinario(String uploadUrl, Blob pdfBody) {
        logInfo('ejecutarPutBinario | url length=' + uploadUrl.length());
        HttpRequest req = new HttpRequest();
        req.setEndpoint(uploadUrl);
        req.setMethod('PUT');
        req.setHeader('Content-Type', 'application/pdf');
        req.setBodyAsBlob(pdfBody);
        req.setTimeout(TIMEOUT_MS);
        Http http = new Http();
        return http.send(req);
    }

    private static void validarRespuestaExito(HttpResponse res, String operacion) {
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            String body = res.getBody();
            String bodySnippet = body != null && body.length() > LOG_BODY_MAX_LENGTH
                ? body.substring(0, LOG_BODY_MAX_LENGTH) + '...'
                : body;
            logError(operacion + ' | status=' + status + ' | body=' + bodySnippet);
            throw new ICB_FirmaDigitalException(operacion + ' fallido: ' + status + ' ' + res.getStatus() + (body != null ? ' | ' + bodySnippet : ''));
        }
    }

    private static void logInfo(String message) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' ' + message);
    }

    private static void logError(String message) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + message);
    }

    public class ICB_FirmaDigitalException extends Exception {
    }
}
