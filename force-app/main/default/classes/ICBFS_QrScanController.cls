/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-09
Descripción : Puente Apex para registrar escaneo QR ejecutando el Flow "QR_Registrar_Scan"
**********************************************************************************/
public with sharing class ICBFS_QrScanController {

    public class Resp {
        @AuraEnabled public String resultado;
        @AuraEnabled public String mensaje;
        public Resp(String r, String m){
            resultado = r;
            mensaje   = m;
        }
    }

    @AuraEnabled(cacheable=false)
    public static Resp registrar(String token) {

        if (String.isBlank(token)) {
            return new Resp('ERROR', 'Falta token en la URL');
        }

        try {
            Map<String, Object> inputs = new Map<String, Object>{
                'varToken' => token
            };

            Flow.Interview i = Flow.Interview.createInterview('QR_Registrar_Scan', inputs);
            i.start();

            String r = (String)i.getVariableValue('varResultado');
            String m = (String)i.getVariableValue('varMensaje');

            if (String.isBlank(r)) r = 'OK';
            if (String.isBlank(m)) m = 'Escaneo registrado';

            return new Resp(r, m);

        } catch (Exception e) {
            return new Resp('ERROR', 'Error registrando escaneo: ' + e.getMessage());
        }
    }
}