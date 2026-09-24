/**
 * ICB Food Service
 * Desarrollado por: José Illanes
 * Fecha: 2026-02-03
 * Descripción: Clase Apex para invocar Flow de registro de escaneo QR
 */
public with sharing class ICBFS_QR_Registrar_Scan {

    @AuraEnabled
    public static Map<String, String> ejecutar(String token) {
        Map<String, String> result = new Map<String, String>();

        if (String.isBlank(token)) {
            result.put('resultado', 'ERROR');
            result.put('mensaje', 'Token vacío');
            return result;
        }

        try {
            Map<String, Object> inputs = new Map<String, Object>();
            inputs.put('varToken', token);

            Flow.Interview.QR_Registrar_Scan flow =
                new Flow.Interview.QR_Registrar_Scan(inputs);

            flow.start();

            result.put('resultado', 'OK');
            result.put('mensaje', 'Escaneo procesado correctamente');

        } catch (Exception e) {
            result.put('resultado', 'ERROR');
            result.put('mensaje', e.getMessage());
        }

        return result;
    }
}