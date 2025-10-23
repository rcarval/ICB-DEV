public with sharing class ICBFS_QuicksightEmbedController {
    public String embedUrl { get; private set; }
    public String errorMessage { get; private set; }
    @AuraEnabled public String url1 { get; set; }
    @AuraEnabled public String url2 { get; set; }
    @AuraEnabled public String url3 { get; set; }

    private String dashboardId;
    private String endpointUrl;
    private String x_api_key;

    // Wrapper Class para retornar múltiples URLs
    public class EmbedUrlsWrapper {
        @AuraEnabled public String url1 { get; set; }
        @AuraEnabled public String url2 { get; set; }
        @AuraEnabled public String url3 { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static EmbedUrlsWrapper getEmbedUrlsForThreeDashboards(String dashboardId1, String dashboardId2, String dashboardId3) {
        ICBFS_QuicksightEmbedController controller = new ICBFS_QuicksightEmbedController();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error de configuración inicial: ' + controller.errorMessage);
        }
        EmbedUrlsWrapper wrapper = new EmbedUrlsWrapper();
        // Primero dashboard 1
        controller.dashboardId = '77dc125a-ae4d-4306-8f73-6e212809c065'; //dashboardId1;
        controller.callGenerateEmbedUrl();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error al generar URL1: ' + controller.errorMessage);
        }
        wrapper.url1 = controller.embedUrl;
        // Luego dashboard 2
        controller.dashboardId = '7278a5e5-4249-416a-8635-aed79c4918d9	'; //dashboardId2;
        controller.callGenerateEmbedUrl();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error al generar URL2: ' + controller.errorMessage);
        }
        wrapper.url2 = controller.embedUrl;
        // Luego dashboard 3
        controller.dashboardId = '5954f5c2-2bbd-4eb1-987b-941f92a023bd'; //dashboardId3;
        controller.callGenerateEmbedUrl();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error al generar URL3: ' + controller.errorMessage);
        }
        wrapper.url3 = controller.embedUrl;

        return wrapper;
    }

    @AuraEnabled(cacheable=true)
    public static String getEmbedUrl() {
        ICBFS_QuicksightEmbedController controller = new ICBFS_QuicksightEmbedController();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error de configuración inicial: ' + controller.errorMessage);
        }
        return controller.embedUrl;
    }

    public ICBFS_QuicksightEmbedController() {
        try {
            aws_quicksight__mdt config = [SELECT cod_dashboard_id__c, endpoiny_aws__c, x_api_key__c FROM aws_quicksight__mdt LIMIT 1];
            this.dashboardId = config.cod_dashboard_id__c;
            this.endpointUrl = config.endpoiny_aws__c;
            this.x_api_key = config.x_api_key__c;
            this.callGenerateEmbedUrl();
        } catch (Exception ex) {
            this.errorMessage = ex.getMessage();
        }
    }

    private void callGenerateEmbedUrl() {
        String userEmail = 'jsilvac@icbfs.cl';
        // String userEmail = UserInfo.getUserEmail();
        // String userEmail = 'bmiranda@icbfs.cl';
        Map<String, Object> payload = new Map<String, Object>{
            'email' => userEmail,
            'dashboardId' => this.dashboardId
        };
        String body = JSON.serialize(payload);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(this.endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-API-Key', this.x_api_key);
        req.setBody(body);
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse resp = http.send(req);

        if (resp.getStatusCode() == 200) {
            QuickSightResponse qr = (QuickSightResponse) JSON.deserialize(resp.getBody(), QuickSightResponse.class);
            if (qr != null && qr.embedUrl != null) {
                this.embedUrl = qr.embedUrl;
            } else {
                this.errorMessage = 'Respuesta no tiene embedUrl';
            }
        } else {
            this.errorMessage = 'Callout fallido: ' + resp.getStatusCode() + ' – ' + resp.getBody();
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<LabelValue> getDashboardOptions() {
        List<Dashboard_quickSight__mdt> mdtList = [
            SELECT Nombre_dashboard__c, id_dashboard__c
            FROM Dashboard_quickSight__mdt
            ORDER BY Nombre_dashboard__c
        ];
        List<LabelValue> options = new List<LabelValue>();
        for (Dashboard_quickSight__mdt d : mdtList) {
            if (d.Nombre_dashboard__c != null && d.id_dashboard__c != null) {
                options.add(new LabelValue(d.Nombre_dashboard__c, d.id_dashboard__c));
            }
        }
        return options;
    }

    public class LabelValue {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public LabelValue(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled
    public static String getEmbedUrlForDashboard(String dashboardId) {
        ICBFS_QuicksightEmbedController controller = new ICBFS_QuicksightEmbedController();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error de configuración inicial: ' + controller.errorMessage);
        }
        controller.dashboardId = dashboardId;
        controller.callGenerateEmbedUrl();
        if (controller.errorMessage != null) {
            throw new AuraHandledException('Error al generar embed URL: ' + controller.errorMessage);
        }
        return controller.embedUrl;
    }

    private class QuickSightResponse {
        public String embedUrl;
        public String username;
        public String dashboardId;
        public String expiresAt;
        public String creationTime;
        public Integer sessionLifetime;
        public String requestId;
        public Integer status;
    }
}

// public with sharing class ICBFS_QuicksightEmbedController {
//     public String embedUrl { get; private set; }
//     public String errorMessage { get; private set; }

//     private String dashboardId;
//     private String endpointUrl;
//     private String x_api_key;

//     @AuraEnabled
//     public static String getEmbedUrl() {
//         ICBFS_QuicksightEmbedController controller = new ICBFS_QuicksightEmbedController();
//         if (controller.errorMessage != null) {
//             throw new AuraHandledException('Error al generar embedUrl: ' + controller.errorMessage);
//         }
//         return controller.embedUrl;
//     }

//     public ICBFS_QuicksightEmbedController() {
//         try {
//             aws_quicksight__mdt config = [SELECT cod_dashboard_id__c, endpoiny_aws__c, x_api_key__c FROM aws_quicksight__mdt LIMIT 1];
//             this.dashboardId = config.cod_dashboard_id__c;
//             this.endpointUrl = config.endpoiny_aws__c;
//             this.x_api_key = config.x_api_key__c;
//             this.callGenerateEmbedUrl();
//         } catch (Exception ex) {
//             this.errorMessage = ex.getMessage();
//         }
//     }

//     private void callGenerateEmbedUrl() {
//         String userEmail = 'jsilvac@icbfs.cl';
//         // String userEmail = UserInfo.getUserEmail();

//         Map<String, Object> payload = new Map<String, Object>{
//             'email' => userEmail,
//             'dashboardId' => this.dashboardId
//         };
//         String body = JSON.serialize(payload);

//         HttpRequest req = new HttpRequest();
//         req.setEndpoint(this.endpointUrl);
//         req.setMethod('POST');
//         req.setHeader('Content-Type', 'application/json');
//         req.setHeader('X-API-Key', this.x_api_key);
//         req.setBody(body);
//         req.setTimeout(120000);

//         Http http = new Http();
//         HttpResponse resp = http.send(req);

//         if (resp.getStatusCode() == 200) {
//             QuickSightResponse qr = (QuickSightResponse) JSON.deserialize(resp.getBody(), QuickSightResponse.class);
//             if (qr != null && qr.embedUrl != null) {
//                 this.embedUrl = qr.embedUrl;
//             } else {
//                 this.errorMessage = 'Respuesta no tiene embedUrl';
//             }
//         } else {
//             this.errorMessage = 'Callout fallido: ' + resp.getStatusCode() + ' – ' + resp.getBody();
//         }
//     }

//       /**
//      * Método que trae los dashboards disponibles desde la metadata Dashboard_quickSight__mdt
//      * para poblar el campo de selección en el LWC.
//      * @return List<LabelValue> lista de pares label/valor donde label es el nombre visible y value el id del dashboard
//      */
//     @AuraEnabled(cacheable=true)
//     public static List<LabelValue> getDashboardOptions() {
//         List<Dashboard_quickSight__mdt> mdtList = [
//             SELECT Nombre_dashboard__c, id_dashboard__c
//             FROM Dashboard_quickSight__mdt
//             ORDER BY Nombre_dashboard__c
//         ];
//         List<LabelValue> options = new List<LabelValue>();
//         for (Dashboard_quickSight__mdt d : mdtList) {
//             // Validar que los campos no sean nulos
//             if (d.Nombre_dashboard__c != null && d.id_dashboard__c != null) {
//                 options.add(new LabelValue(d.Nombre_dashboard__c, d.id_dashboard__c));
//             }
//         }
//         return options;
//     }

//     // Clase auxiliar para representar label / value: Tipos de dashboard
//     public class LabelValue {
//         @AuraEnabled public String label { get; set; }
//         @AuraEnabled public String value { get; set; }
//         public LabelValue(String label, String value) {
//             this.label = label;
//             this.value = value;
//         }
//     }

//     // --- Nuevo método  ---
//     @AuraEnabled
//     public static String getEmbedUrlForDashboard(String dashboardId) {
//         ICBFS_QuicksightEmbedController controller = new ICBFS_QuicksightEmbedController();
//         if (controller.errorMessage != null) {
//             throw new AuraHandledException('Error de configuración inicial: ' + controller.errorMessage);
//         }
//         // Cambiar el dashboardId de la instancia antes de llamar al callout
//         controller.dashboardId = dashboardId;
//         controller.callGenerateEmbedUrl();
//         if (controller.errorMessage != null) {
//             throw new AuraHandledException('Error al generar embed URL: ' + controller.errorMessage);
//         }
//         return controller.embedUrl;
//     }

//     private class QuickSightResponse {
//         public String embedUrl;
//         public String username;
//         public String dashboardId;
//         public String expiresAt;
//         public String creationTime;
//         public Integer sessionLifetime;
//         public String requestId;
//         public Integer status;
//     }
// }