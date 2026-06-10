@isTest
public class ICB_LeadsSII_TestFactory {
    public static Lead createLeadBase() {
        Lead ld = new Lead();
        ld.FirstName = 'CASA PARAISO';
        ld.LastName = 'RESTAURANTE';
        ld.Company = 'ABAST Y SERV DE LOS IND DE LA MADERA DE VALPO Y ACON LTDA';
        ld.Status = 'Validación SII';
        ld.RUT__c = '81482800-K';
        ld.Cliente_Contactado__c = 'SI';
        insert ld;
        return ld;
    }

    public static ICB_CalloutAPI_SII.SituacionTributariaDataDto buildApprovedResponse() {
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = new ICB_CalloutAPI_SII.SituacionTributariaDataDto();
        dto.rut = 81482800L;
        dto.dv = 'K';
        dto.razon_social = 'ABAST Y SERV DE LOS IND DE LA MADERA DE VALPO Y ACON LTDA';
        dto.inicio_actividades = true;

        ICB_CalloutAPI_SII.ActividadDto actividad = new ICB_CalloutAPI_SII.ActividadDto();
        actividad.codigo = '475201';
        dto.actividades = new List<ICB_CalloutAPI_SII.ActividadDto>{ actividad };

        ICB_CalloutAPI_SII.ObservacionesDto obs = new ICB_CalloutAPI_SII.ObservacionesDto();
        obs.inconcurrente = false;
        obs.suplantado = false;
        obs.no_ubicado = false;
        obs.termino_giro = false;
        obs.domicilio_inexistente = false;
        obs.actividad_esporadica = false;
        obs.no_habido_domicilio = false;
        obs.termino_giro_obligatorio = false;
        dto.observaciones = obs;

        return dto;
    }

    public static ICB_CalloutAPI_SII.SituacionTributariaDataDto buildRejectedResponse() {
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = new ICB_CalloutAPI_SII.SituacionTributariaDataDto();
        dto.rut = 81482800L;
        dto.dv = 'K';
        dto.razon_social = 'RAZON SOCIAL COMPLETAMENTE DISTINTA';

        ICB_CalloutAPI_SII.ActividadDto actividad = new ICB_CalloutAPI_SII.ActividadDto();
        actividad.codigo = '620200';
        dto.actividades = new List<ICB_CalloutAPI_SII.ActividadDto>{ actividad };

        ICB_CalloutAPI_SII.ObservacionesDto obs = new ICB_CalloutAPI_SII.ObservacionesDto();
        obs.inconcurrente = true;
        obs.suplantado = false;
        obs.no_ubicado = false;
        obs.termino_giro = false;
        obs.domicilio_inexistente = false;
        obs.actividad_esporadica = false;
        obs.no_habido_domicilio = false;
        obs.termino_giro_obligatorio = false;
        dto.observaciones = obs;

        return dto;
    }

    /** Respuesta SII sin inicio de actividades (inicio_actividades = false). */
    public static ICB_CalloutAPI_SII.SituacionTributariaDataDto buildSinInicioActividadesResponse() {
        ICB_CalloutAPI_SII.SituacionTributariaDataDto dto = new ICB_CalloutAPI_SII.SituacionTributariaDataDto();
        dto.rut = 78426336L;
        dto.dv = '3';
        dto.razon_social = 'CALMA & CAFE SPA';
        dto.inicio_actividades = false;
        return dto;
    }

    public class SiiHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String status;
        private String body;

        public SiiHttpMock(Integer statusCode, String status, String body) {
            this.statusCode = statusCode;
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus(status);
            res.setBody(body);
            return res;
        }
    }
}