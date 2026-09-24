/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-02-09
Descripción : Ejecuta el Flow QR_Registrar_Scan en transacción separada (DML allowed).
**********************************************************************************/
public without sharing class ICBFD_QR_RegistrarScanJob implements Queueable {

    private String token;

    public ICBFD_QR_RegistrarScanJob(String token) {
        this.token = token;
    }

    public void execute(QueueableContext qc) {
        if (String.isBlank(token)) return;

        Map<String, Object> inputs = new Map<String, Object>{
            'varToken' => token
        };

        Flow.Interview interview = Flow.Interview.createInterview('QR_Registrar_Scan', inputs);
        interview.start();
    }
}