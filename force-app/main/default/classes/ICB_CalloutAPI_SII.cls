/**********************************************************************************
 * ICB_CalloutAPI_SII
 * Servicio de integración con API Gateway SII para consulta de contribuyentes.
 * SEIDOR - SMH - Integración API Gateway SII

 **********************************************************************************/
public with sharing class ICB_CalloutAPI_SII {

    /** Constantes de Configuración */
    private static final String NAMED_CREDENTIAL = 'ICB_SII_API';
    private static final String PATH_SITUACION_TRIBUTARIA_TERCERO = '/api/v1/sii/contribuyentes/situacion_tributaria/tercero/{rut}';
    private static final Integer TIMEOUT_MS = 120000;
    private static final String LOG_PREFIX = '[ICB_SII]';
    private static final Integer LOG_BODY_MAX_LENGTH = 1000;

    public class SituacionTributariaDataDto {
        public Long rut;
        public String dv;
        public String razon_social;
        public Boolean inicio_actividades;
        public String fecha_inicio_actividades;
        public Boolean pro_pyme;
        public Boolean moneda_extranjera;
        public Boolean obligacion_dte;
        public List<ActividadDto> actividades;
        public List<DocumentoTimbradoDto> documentos_timbrados;
        public ObservacionesDto observaciones;
    }

    public class ActividadDto {
        public String codigo;
        public String glosa;
        public Integer categoria;
        public Boolean afecta;
        public String fecha;
    }

    public class DocumentoTimbradoDto {
        public String documento;
        public Integer ultimo_timbraje;
    }

    public class ObservacionesDto {
        public Boolean inconcurrente;
        public Boolean suplantado;
        public Boolean no_ubicado;
        public Boolean termino_giro;
        public Boolean domicilio_inexistente;
        public Boolean actividad_esporadica;
        public Boolean no_habido_domicilio;
        public Boolean termino_giro_obligatorio;
    }
    
    /**
     * Realiza la consulta v1 de situacion tributaria y retorna el HttpResponse crudo.
     */
    public static HttpResponse consultarSituacionTributariaTerceroRaw(String rut) {
        String origen = 'ICB_CalloutAPI_SII.consultarSituacionTributariaTerceroRaw';
        logInfo('Iniciando consulta v1 para RUT: ' + rut);

        if (String.isBlank(rut)) {
            throw new ICB_CalloutSIIException('El RUT es obligatorio para realizar la consulta.');
        }

        Long startMs = System.currentTimeMillis();
        String endpoint = 'callout:' + NAMED_CREDENTIAL + PATH_SITUACION_TRIBUTARIA_TERCERO.replace('{rut}', rut);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        HttpResponse res = null;
        try {
            res = (new Http()).send(req);
            Integer statusCode = res != null ? res.getStatusCode() : null;
            Boolean ok = statusCode != null && statusCode >= 200 && statusCode < 300;
            if (!ok) {
                String errorMsg = 'Error en respuesta SII v1. Status: ' + statusCode + ' - ' + (res != null ? res.getStatus() : '');
                ICB_LogIntegracionService.insertarLogOutbound(origen, endpoint, 'GET', null, null, statusCode, null, res != null ? res.getBody() : null, false, errorMsg, System.currentTimeMillis() - startMs, rut);
                throw new ICB_CalloutSIIException(errorMsg);
            }
            ICB_LogIntegracionService.insertarLogOutbound(origen, endpoint, 'GET', null, null, statusCode, null, res.getBody(), true, null, System.currentTimeMillis() - startMs, rut);
            return res;
        } catch (Exception e) {
            logError('Error de integracion v1: ' + e.getMessage());
            ICB_LogIntegracionService.insertarLogOutbound(origen, endpoint, 'GET', null, null, res != null ? res.getStatusCode() : null, null, res != null ? res.getBody() : null, false, e.getMessage(), System.currentTimeMillis() - startMs, rut);
            throw e;
        } finally {
            ICB_LogIntegracionService.publicarLogsOutboundPendientes();
        }
    }

    /**
     * Consulta v1 y deserializa respuesta directa del API Gateway.
     */
    public static SituacionTributariaDataDto consultarSituacionTributariaTercero(String rut) {
        HttpResponse res = consultarSituacionTributariaTerceroRaw(rut);
        if (res == null || String.isBlank(res.getBody())) {
            return null;
        }
        return (SituacionTributariaDataDto) JSON.deserialize(res.getBody(), SituacionTributariaDataDto.class);
    }

    /** Métodos de utilidad privados */

    private static String getBodySnippet(String body) {
        if (String.isBlank(body)) return '';
        return body.length() > LOG_BODY_MAX_LENGTH ? body.substring(0, LOG_BODY_MAX_LENGTH) + '...' : body;
    }

    private static void logInfo(String mensaje) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' ' + mensaje);
    }

    private static void logError(String mensaje) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + mensaje);
    }

    /** Excepción personalizada para la integración */
    public class ICB_CalloutSIIException extends Exception {}
}