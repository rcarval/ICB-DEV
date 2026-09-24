/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-03
Descripción : Registro de escaneo QR vía Flow (contexto async)
**********************************************************************************/
public class ICBFS_QR_RegistrarScanFuture {

    @future
    public static void registrar(String token) {

        Map<String, Object> inputs = new Map<String, Object>{
            'varToken' => token
        };

        Flow.Interview interview =
            Flow.Interview.createInterview('QR_Registrar_Scan', inputs);

        interview.start();
    }
}