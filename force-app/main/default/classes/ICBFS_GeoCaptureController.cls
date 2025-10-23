// public with sharing class ICBFS_GeoCaptureController {
//         public Decimal latitude { get; set; }
//         public Decimal longitude { get; set; }

//     public ICBFS_GeoCaptureController(Id recordId) {

//         // Reemplaza 'NombreDelObjeto' con el nombre de tu objeto personalizado
//     List<Visitas__c> registros = [SELECT Id, Ubicaci_n_Tiempo_Real__Latitude__s, Ubicaci_n_Tiempo_Real__Longitude__s
//                                    FROM Visitas__c
//                                    WHERE Id = :recordId];
//         Double lat = registros[0].Ubicaci_n_Tiempo_Real__Latitude__s;
//         Double longi = registros[0].Ubicaci_n_Tiempo_Real__Longitude__s;

//     }
//     public class GeoCaptureException extends Exception {}
//     public class GeoCaptureRequest {
//         @InvocableVariable(required=true) public Id recordId;
//         @InvocableVariable(required=true) public Decimal latitude;
//         @InvocableVariable(required=true) public Decimal longitude;
//         @InvocableVariable public Id triggeredByUserId;
//         @InvocableVariable public String sObjectApiName;
//     }
//     public class GeoCaptureResult {
//         @InvocableVariable public Boolean success;
//         @InvocableVariable public String message;
//     }

//     // @AuraEnabled
//     public static List<GeoCaptureResult> captureGeoFromLwc(Id recordId, Decimal latitude, Decimal longitude, String sObjectApiName) {
//         GeoCaptureRequest req = new GeoCaptureRequest();
//         req.recordId = recordId;
//         req.latitude = latitude;
//         req.longitude = longitude;
//         req.sObjectApiName = sObjectApiName;
//         req.triggeredByUserId = UserInfo.getUserId();
//         return captureGeo(new List<GeoCaptureRequest>{req});
//     }

//     @InvocableMethod(label='Capture Geolocation + Validate' description='Actualiza lat/long + dirección + url maps embed')
//     public static List<GeoCaptureResult> captureGeo(List<GeoCaptureRequest> requests) {
//         List<GeoCaptureResult> results = new List<GeoCaptureResult>();
//         List<SObject> updates = new List<SObject>();
//         String googleApiKey = 'AIzaSyC4ObJce3_zjgNUXCSC7eSe88Tn9B-Jecs';

//         for (GeoCaptureRequest req : requests) {
//             GeoCaptureResult res = new GeoCaptureResult();
//             try {
//                 if (req.recordId == null) {
//                     throw new GeoCaptureException('recordId es null');
//                 }
//                 Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
//                 Schema.SObjectType sType = gd.get(req.sObjectApiName);
//                 if (sType == null) {
//                     throw new GeoCaptureException('sObjectApiName inválido: ' + req.sObjectApiName);
//                 }
//                 SObject obj = sType.newSObject(req.recordId);

//                 if (req.latitude != null) {
//                     obj.put('Ubicaci_n_Tiempo_Real__Latitude__s', req.latitude);
//                 }
//                 if (req.longitude != null) {
//                     obj.put('Ubicaci_n_Tiempo_Real__Longitude__s', req.longitude);
//                 }

//                 String direccion = reverseGeocode(req.latitude, req.longitude, googleApiKey);
//                 if (direccion != null) {
//                     obj.put('Ubicaci_n_Actual_Asesor__c', direccion);
//                 }

//                 // Solo si tenemos latitud y longitud construimos la URL de embed
//                 if (req.latitude != null && req.longitude != null) {
//                     String embedUrl = 'https://www.google.com/maps/embed/v1/place?key='
//                         + EncodingUtil.urlEncode(googleApiKey, 'UTF-8')
//                         + '&q=' + EncodingUtil.urlEncode(String.valueOf(req.latitude) + ',' + String.valueOf(req.longitude), 'UTF-8');
//                     obj.put('Url_maps__c', embedUrl);
//                 }

//                 updates.add(obj);
//                 res.success = true;
//                 res.message = 'Lat/Long actualizados, dirección y URL embed procesadas';
//             } catch (GeoCaptureException gce) {
//                 res.success = false;
//                 res.message = 'Error personalizado: ' + gce.getMessage();
//             } catch (Exception ex) {
//                 res.success = false;
//                 res.message = 'Error general: ' + ex.getMessage();
//             }
//             results.add(res);
//         }

//         if (!updates.isEmpty()) {
//             update updates;
//         }

//         return results;
//     }

//     private static String reverseGeocode(Decimal latitude, Decimal longitude, String apiKey) {
//         if (latitude == null || longitude == null) {
//             return null;
//         }
//         HttpRequest req = new HttpRequest();
//         req.setMethod('GET');
//         String endpoint = 'https://maps.googleapis.com/maps/api/geocode/json'
//             + '?latlng=' + EncodingUtil.urlEncode(String.valueOf(latitude) + ',' + String.valueOf(longitude), 'UTF-8')
//             + '&key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8');
//         req.setEndpoint(endpoint);

//         HttpResponse resp = new Http().send(req);
//         if (resp.getStatusCode() == 200) {
//             Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
//             String status = (String) root.get('status');
//             if (status == 'OK') {
//                 List<Object> resultsList = (List<Object>) root.get('results');
//                 if (!resultsList.isEmpty()) {
//                     Map<String, Object> first = (Map<String, Object>) resultsList[0];
//                     return (String) first.get('formatted_address');
//                 }
//             }
//         }
//         return null;
//     }
// }
public class ICBFS_GeoCaptureController {
    // Excepción personalizada
    public class GeoCaptureException extends Exception {}

    public class GeoCaptureRequest {
        @InvocableVariable(required=true)
        public Id recordId;
        @InvocableVariable(required=true)
        public Decimal latitude;
        @InvocableVariable(required=true)
        public Decimal longitude;
        @InvocableVariable
        public Id triggeredByUserId;
        @InvocableVariable
        public String sObjectApiName;
    }
    
    public class GeoCaptureResult {
        @InvocableVariable
        public Boolean success;
        @InvocableVariable
        public String message;
    }

    @AuraEnabled
    public static List<GeoCaptureResult> captureGeoFromLwc(Id recordId, Decimal latitude, Decimal longitude, String sObjectApiName) {
        System.debug('captureGeoFromLwc called. recordId=' + recordId
                     + ', lat=' + latitude + ', long=' + longitude
                     + ', sObjectApiName=' + sObjectApiName);
        GeoCaptureRequest req = new GeoCaptureRequest();
        req.recordId = recordId;
        req.latitude = latitude;
        req.longitude = longitude;
        req.sObjectApiName = sObjectApiName;
        req.triggeredByUserId = UserInfo.getUserId();
        System.debug('   GeoCaptureRequest built: ' + JSON.serialize(req));
        
        List<GeoCaptureRequest> lst = new List<GeoCaptureRequest>{ req };
        return captureGeo(lst);
    }
    
    @InvocableMethod(label='Capture Geolocation + Validate' description='Actualiza lat/long + dirección en unic_maps__c')
    public static List<GeoCaptureResult> captureGeo(List<GeoCaptureRequest> requests) {
        System.debug('captureGeo entered with requests: ' + JSON.serialize(requests));
        List<GeoCaptureResult> results = new List<GeoCaptureResult>();
        List<SObject> updates = new List<SObject>();
        
        String googleApiKey = 'AIzaSyC4ObJce3_zjgNUXCSC7eSe88Tn9B-Jecs'; //AIzaSyB3poYWoZGL85PTHl7n5fyHGcTpiE_QsV0
        
        for (GeoCaptureRequest req : requests) {
            System.debug(' Processing request: ' + JSON.serialize(req));
            GeoCaptureResult res = new GeoCaptureResult();
            try {
                if (req.recordId == null) {
                    throw new GeoCaptureException('recordId es null');
                }
                
                SObject obj;
                if (String.isNotBlank(req.sObjectApiName)) {
                    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
                    Schema.SObjectType sType = gd.get(req.sObjectApiName);
                    if (sType == null) {
                        throw new GeoCaptureException('sObjectApiName inválido: ' + req.sObjectApiName);
                    }
                    obj = sType.newSObject(req.recordId);
                } else {
                    obj = req.recordId.getSObjectType().newSObject(req.recordId);
                }
                if (obj == null) {
                    throw new GeoCaptureException('No se pudo instanciar el SObject para ' + req.recordId);
                }
                
                if (req.latitude != null) {
                    obj.put('Ubicaci_n_Tiempo_Real__Latitude__s', req.latitude);
                }
                if (req.longitude != null) {
                    obj.put('Ubicaci_n_Tiempo_Real__Longitude__s', req.longitude);
                }
                
                String direccion = reverseGeocode(req.latitude, req.longitude, googleApiKey);
                System.debug('  reverseGeocode returned: ' + direccion);
                
                if (direccion != null) {
                    obj.put('Ubicaci_n_Actual_Asesor__c', direccion);
                    obj.put('Url_maps__c', 'https://www.google.com/maps/search/?api=1&query=' 
                            + String.valueOf(req.latitude) + ',' + String.valueOf(req.longitude));
                }
                
                updates.add(obj);
                res.success = true;
                res.message = 'Lat/Long actualizados y dirección procesada';
            } catch (GeoCaptureException gce) {
                res.success = false;
                res.message = 'Error personalizado: ' + gce.getMessage();
                System.debug('  GeoCaptureException: ' + gce.getMessage());
            } catch (Exception ex) {
                res.success = false;
                res.message = 'Error general: ' + ex.getMessage();
                System.debug('  Exception general: ' + ex.getMessage() + ' stack: ' + ex.getStackTraceString());
            }
            results.add(res);
        }
        
        if (!updates.isEmpty()) {
            System.debug('About to update: ' + JSON.serialize(updates));
            update updates;
            System.debug('Update executed.');
        }
        
        System.debug('Returning results: ' + JSON.serialize(results));
        return results;
    }
    
    private static String reverseGeocode(Decimal latitude, Decimal longitude, String apiKey) {
        System.debug('reverseGeocode called with lat=' + latitude + ', long=' + longitude);
        if (latitude == null || longitude == null) {
            System.debug('latitude o longitude es null, saliendo');
            return null;
        }
        
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        String endpoint = 'https://maps.googleapis.com/maps/api/geocode/json'
            + '?latlng=' + EncodingUtil.urlEncode(String.valueOf(latitude) + ',' + String.valueOf(longitude), 'UTF-8')
            + '&key=' + EncodingUtil.urlEncode(apiKey, 'UTF-8');
        req.setEndpoint(endpoint);
        System.debug('  endpoint: ' + endpoint);
        
        HttpResponse resp = new Http().send(req);
        System.debug('  HTTP Response status: ' + resp.getStatusCode() + ', body: ' + resp.getBody());
        if (resp.getStatusCode() == 200) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            String status = (String) root.get('status');
            if (status == 'OK') {
                List<Object> resultsList = (List<Object>) root.get('results');
                if (!resultsList.isEmpty()) {
                    Map<String, Object> first = (Map<String, Object>) resultsList[0];
                    return (String) first.get('formatted_address');
                }
            }
        }
        return null;
    }
}