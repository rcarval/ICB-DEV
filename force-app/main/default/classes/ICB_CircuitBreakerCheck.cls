/**********************************************************************************
 * ICB_CircuitBreakerCheck
 * InvocableMethod que cada Flow llama antes de hacer el callout a SAP para
 * verificar/contar un intento contra el circuit breaker del proceso (Circuit_Breaker__c).
 * Mismo patron de invocable que FlowExecutionValidator. Nunca lanza excepcion:
 * ante cualquier error interno responde permitirContinuar=false (fail-closed).
 **********************************************************************************/
public with sharing class ICB_CircuitBreakerCheck {

    public class Request {
        @InvocableVariable(required=true label='Nombre del Proceso')
        public String nombreProceso;

        @InvocableVariable(label='Id de referencia (Account u otro registro)')
        public Id registroId;
    }

    public class Response {
        @InvocableVariable public Boolean permitirContinuar;
        @InvocableVariable public String estadoBreaker;
        @InvocableVariable public String motivo;
    }

    @InvocableMethod(
        label='Circuit Breaker - Verificar Intento SAP'
        description='Verifica y cuenta un intento de envio a SAP; abre el breaker si supera el umbral configurado en Circuit_Breaker__c. Nunca lanza excepcion; ante error interno bloquea por seguridad.'
        category='Logica de integracion'
    )
    public static List<Response> verificar(List<Request> requests) {
        List<Response> respuestas = new List<Response>();

        // Mismo bypass por usuario que aplica el gate before-save, para que los dos
        // caminos (trigger e invocable de Flow) traten igual a las identidades de integracion.
        if (ICB_CircuitBreakerService.usuarioTieneBypass()) {
            for (Request req : requests) {
                Response resp = new Response();
                resp.permitirContinuar = true;
                resp.estadoBreaker = 'Cerrado';
                resp.motivo = 'Bypass de integracion: el usuario tiene Bypass_Control_Flujos_SAP';
                respuestas.add(resp);
            }
            return respuestas;
        }

        try {
            List<String> nombres = new List<String>();
            List<Id> ids = new List<Id>();
            for (Request req : requests) {
                nombres.add(req.nombreProceso);
                ids.add(req.registroId);
            }

            Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
                ICB_CircuitBreakerService.evaluarLote(nombres, ids);

            for (Integer i = 0; i < requests.size(); i++) {
                ICB_CircuitBreakerService.BreakerResultado r = resultados.get(i);
                Response resp = new Response();
                if (r == null) {
                    resp.permitirContinuar = false;
                    resp.estadoBreaker = 'Error';
                    resp.motivo = 'Sin resultado del circuit breaker';
                } else {
                    resp.permitirContinuar = r.permitirContinuar;
                    resp.estadoBreaker = r.estadoBreaker;
                    resp.motivo = r.motivo;
                }
                respuestas.add(resp);

                if (resp.permitirContinuar != true) {
                    registrarBloqueo(requests[i], resp.motivo);
                }
            }
        } catch (Exception e) {
            respuestas = new List<Response>();
            for (Request req : requests) {
                Response resp = new Response();
                resp.permitirContinuar = false;
                resp.estadoBreaker = 'Error';
                resp.motivo = 'Error interno del circuit breaker: ' + e.getMessage();
                respuestas.add(resp);
            }
        }

        return respuestas;
    }

    private static void registrarBloqueo(Request req, String motivo) {
        try {
            ICB_LogIntegracionService.insertarLogOutbound(
                'CircuitBreaker:' + req.nombreProceso,
                null,
                null,
                null,
                'RegistroId=' + req.registroId,
                null,
                null,
                null,
                false,
                'Bloqueado por Circuit Breaker: ' + motivo,
                null,
                req.nombreProceso
            );
            ICB_LogIntegracionService.publicarLogsOutboundPendientes();
        } catch (Exception logEx) {
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerCheck] Error al registrar bloqueo: ' + logEx.getMessage());
        }
    }
}