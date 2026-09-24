/**********************************************************************************
 * ICB_CircuitBreakerService
 * Motor del circuit breaker por proceso para frenar rafagas de envios a SAP.
 * Usa SELECT ... FOR UPDATE sobre Circuit_Breaker__c para serializar el conteo
 * entre transacciones async concurrentes (Cache.Org no ofrece incremento atomico).
 * Fail-open si el proceso no esta Activo__c; fail-closed ante cualquier error interno
 * o lock no disponible (nunca deja pasar trafico sin control por un fallo propio).
 **********************************************************************************/
public without sharing class ICB_CircuitBreakerService {

    public class BreakerResultado {
        public Boolean permitirContinuar;
        public String estadoBreaker;
        public String motivo;
    }

    private class ResultadoVentana {
        public Boolean permitirContinuar;
        public Boolean justOpened = false;
        public Boolean justClosed = false;
        public Integer totalBloqueadosAlCerrar;
        public String motivo;
    }

    /**
     * Bypass por USUARIO (distinto del Bypass_Activo__c, que es por proceso y global).
     * Las identidades de integracion con el custom permission Bypass_Control_Flujos_SAP
     * quedan exentas del breaker: su volumen es esperado y sostenido, no una anomalia.
     * Fail-safe: ante cualquier error responde false, o sea se comporta como hoy.
     */
    @TestVisible
    private static Boolean bypassUsuarioForzado = null;

    public static Boolean usuarioTieneBypass() {
        if (Test.isRunningTest() && bypassUsuarioForzado != null) {
            return bypassUsuarioForzado;
        }
        try {
            return FeatureManagement.checkPermission('Bypass_Control_Flujos_SAP');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error evaluando bypass de usuario: ' + e.getMessage());
            return false;
        }
    }

    public static Map<Integer, BreakerResultado> evaluarLote(List<String> nombresProceso, List<Id> registroIds) {
        return procesarLote(nombresProceso, registroIds, true);
    }

    /**
     * Igual que evaluarLote pero SIN persistir (no hace update de Circuit_Breaker__c ni
     * envia notificacion). Uso: gates before-save donde un addError() posterior en la misma
     * transaccion revertiria cualquier DML hecho aqui. La cuenta real y la notificacion se
     * hacen de forma async via Circuit_Breaker_Intento__e (PublishImmediately, no se revierte).
     */
    public static Map<Integer, BreakerResultado> evaluarLotePeek(List<String> nombresProceso, List<Id> registroIds) {
        return procesarLote(nombresProceso, registroIds, false);
    }

    private static Map<Integer, BreakerResultado> procesarLote(List<String> nombresProceso, List<Id> registroIds, Boolean persistir) {
        Map<Integer, BreakerResultado> resultados = new Map<Integer, BreakerResultado>();
        if (nombresProceso == null || nombresProceso.isEmpty()) {
            return resultados;
        }

        Datetime ahora = Datetime.now();

        Map<String, List<Integer>> indicesPorProceso = new Map<String, List<Integer>>();
        for (Integer i = 0; i < nombresProceso.size(); i++) {
            String nombre = nombresProceso[i];
            if (String.isBlank(nombre)) {
                resultados.put(i, fallo('Nombre de proceso vacio'));
                continue;
            }
            if (!indicesPorProceso.containsKey(nombre)) {
                indicesPorProceso.put(nombre, new List<Integer>());
            }
            indicesPorProceso.get(nombre).add(i);
        }

        if (indicesPorProceso.isEmpty()) {
            return resultados;
        }

        Set<String> nombresUnicos = indicesPorProceso.keySet();

        try {
            List<Circuit_Breaker__c> filas = [
                SELECT Id, Nombre_Proceso__c, Activo__c, Umbral_Intentos__c, Ventana_Segundos__c,
                       Enfriamiento_Minutos__c, Destinatarios_Correo__c, Remitente_OrgWideEmail__c,
                       Estado__c, Contador_Ventana__c, Inicio_Ventana__c, Fecha_Apertura__c,
                       Correo_Enviado__c, Total_Intentos_Bloqueados__c, Ultima_Actividad__c,
                       Bypass_Activo__c, Bypass_Hasta__c
                FROM Circuit_Breaker__c
                WHERE Nombre_Proceso__c IN :nombresUnicos
                FOR UPDATE
            ];

            Map<String, Circuit_Breaker__c> filaPorProceso = new Map<String, Circuit_Breaker__c>();
            for (Circuit_Breaker__c fila : filas) {
                filaPorProceso.put(fila.Nombre_Proceso__c, fila);
            }

            autoprovisionarFaltantes(nombresUnicos, filaPorProceso);

            List<Circuit_Breaker__c> paraActualizar = new List<Circuit_Breaker__c>();
            Map<String, ResultadoVentana> resultadoPorProceso = new Map<String, ResultadoVentana>();

            for (String nombreProceso : nombresUnicos) {
                Circuit_Breaker__c fila = filaPorProceso.get(nombreProceso);
                List<Integer> indices = indicesPorProceso.get(nombreProceso);

                if (fila == null || fila.Activo__c != true) {
                    BreakerResultado r = new BreakerResultado();
                    r.permitirContinuar = true;
                    r.estadoBreaker = fila != null ? fila.Estado__c : 'Cerrado';
                    r.motivo = fila == null ? 'Sin registro de configuracion - fail-open' : 'Breaker inactivo (Activo__c=false)';
                    for (Integer idx : indices) {
                        resultados.put(idx, r);
                    }
                    continue;
                }

                if (fila.Bypass_Activo__c == true) {
                    Boolean bypassVigente = fila.Bypass_Hasta__c == null
                        || ahora.getTime() < fila.Bypass_Hasta__c.getTime();

                    if (bypassVigente) {
                        fila.Ultima_Actividad__c = ahora;
                        paraActualizar.add(fila);

                        BreakerResultado r = new BreakerResultado();
                        r.permitirContinuar = true;
                        r.estadoBreaker = fila.Estado__c;
                        r.motivo = 'Bypass activo' + (fila.Bypass_Hasta__c != null ? ' hasta ' + fila.Bypass_Hasta__c : ' (sin vencimiento)');
                        for (Integer idx : indices) {
                            resultados.put(idx, r);
                        }
                        continue;
                    }

                    // Bypass vencido: se autodesactiva y sigue el flujo normal de conteo mas abajo.
                    fila.Bypass_Activo__c = false;
                    fila.Bypass_Hasta__c = null;
                }

                ResultadoVentana rv = aplicarLogicaVentana(fila, ahora, indices.size());
                resultadoPorProceso.put(nombreProceso, rv);
                paraActualizar.add(fila);
            }

            Boolean dmlOk = true;
            if (persistir && !paraActualizar.isEmpty()) {
                try {
                    update paraActualizar;
                } catch (Exception dmlEx) {
                    dmlOk = false;
                    System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error actualizando estado: ' + dmlEx.getMessage());
                }
            }

            for (String nombreProceso : resultadoPorProceso.keySet()) {
                List<Integer> indices = indicesPorProceso.get(nombreProceso);
                Circuit_Breaker__c fila = filaPorProceso.get(nombreProceso);
                ResultadoVentana rv = resultadoPorProceso.get(nombreProceso);

                BreakerResultado r = new BreakerResultado();
                if (!dmlOk) {
                    r.permitirContinuar = false;
                    r.motivo = 'Error interno actualizando el estado del circuit breaker';
                } else {
                    r.permitirContinuar = rv.permitirContinuar;
                    r.motivo = rv.motivo;
                }
                r.estadoBreaker = fila.Estado__c;
                for (Integer idx : indices) {
                    resultados.put(idx, r);
                }
            }

            if (persistir && dmlOk) {
                for (String nombreProceso : resultadoPorProceso.keySet()) {
                    ResultadoVentana rvNotif = resultadoPorProceso.get(nombreProceso);
                    if (rvNotif.justOpened) {
                        try {
                            ICB_CircuitBreakerNotifier.enviarAlertaApertura(filaPorProceso.get(nombreProceso));
                        } catch (Exception notifEx) {
                            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error enviando notificacion: ' + notifEx.getMessage());
                        }
                    }
                    if (rvNotif.justClosed) {
                        try {
                            ICB_CircuitBreakerNotifier.enviarAlertaCierre(filaPorProceso.get(nombreProceso), rvNotif.totalBloqueadosAlCerrar);
                        } catch (Exception notifEx) {
                            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error enviando notificacion de cierre: ' + notifEx.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Cubre fallo de lock (UNABLE_TO_LOCK_ROW) u otro error inesperado: fail-closed total del lote.
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error evaluando lote: ' + e.getMessage());
        }

        for (Integer i = 0; i < nombresProceso.size(); i++) {
            if (!resultados.containsKey(i)) {
                resultados.put(i, fallo('Error interno o lock no disponible'));
            }
        }

        return resultados;
    }

    private static void autoprovisionarFaltantes(Set<String> nombresUnicos, Map<String, Circuit_Breaker__c> filaPorProceso) {
        List<Circuit_Breaker__c> nuevas = new List<Circuit_Breaker__c>();
        for (String nombre : nombresUnicos) {
            if (!filaPorProceso.containsKey(nombre)) {
                nuevas.add(new Circuit_Breaker__c(
                    Name = nombre.left(80),
                    Nombre_Proceso__c = nombre,
                    Activo__c = false,
                    Estado__c = 'Cerrado'
                ));
            }
        }
        if (nuevas.isEmpty()) {
            return;
        }
        try {
            Database.SaveResult[] resultados = Database.insert(nuevas, false);
            for (Integer i = 0; i < resultados.size(); i++) {
                if (resultados[i].isSuccess()) {
                    filaPorProceso.put(nuevas[i].Nombre_Proceso__c, nuevas[i]);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[ICB_CircuitBreakerService] Error autoprovisionando: ' + e.getMessage());
        }
    }

    @TestVisible
    private static ResultadoVentana aplicarLogicaVentana(Circuit_Breaker__c fila, Datetime ahora, Integer localCount) {
        ResultadoVentana rv = new ResultadoVentana();

        Integer umbral = fila.Umbral_Intentos__c != null ? fila.Umbral_Intentos__c.intValue() : 20;
        Integer ventanaSeg = fila.Ventana_Segundos__c != null ? fila.Ventana_Segundos__c.intValue() : 1;
        Integer enfriamientoMin = fila.Enfriamiento_Minutos__c != null ? fila.Enfriamiento_Minutos__c.intValue() : 15;

        if (fila.Estado__c == 'Abierto') {
            Boolean enfriamientoVencido = fila.Fecha_Apertura__c != null
                && ahora.getTime() >= fila.Fecha_Apertura__c.addMinutes(enfriamientoMin).getTime();

            if (!enfriamientoVencido) {
                fila.Total_Intentos_Bloqueados__c = (fila.Total_Intentos_Bloqueados__c == null ? 0 : fila.Total_Intentos_Bloqueados__c) + localCount;
                fila.Ultima_Actividad__c = ahora;
                rv.permitirContinuar = false;
                rv.motivo = 'Breaker abierto, en enfriamiento hasta ' + fila.Fecha_Apertura__c.addMinutes(enfriamientoMin);
                return rv;
            }

            // Enfriamiento vencido: auto-cierre y se reevalua como ventana nueva mas abajo.
            rv.justClosed = true;
            rv.totalBloqueadosAlCerrar = fila.Total_Intentos_Bloqueados__c == null ? 0 : fila.Total_Intentos_Bloqueados__c.intValue();
            fila.Estado__c = 'Cerrado';
            fila.Fecha_Apertura__c = null;
            fila.Correo_Enviado__c = false;
            fila.Total_Intentos_Bloqueados__c = 0;
            fila.Inicio_Ventana__c = null;
            fila.Contador_Ventana__c = 0;
        }

        Boolean ventanaVigente = fila.Inicio_Ventana__c != null
            && ahora.getTime() <= fila.Inicio_Ventana__c.addSeconds(ventanaSeg).getTime();

        if (!ventanaVigente) {
            fila.Inicio_Ventana__c = ahora;
            fila.Contador_Ventana__c = 0;
        }

        Integer nuevoContador = (fila.Contador_Ventana__c == null ? 0 : fila.Contador_Ventana__c.intValue()) + localCount;
        fila.Ultima_Actividad__c = ahora;

        if (nuevoContador > umbral) {
            fila.Estado__c = 'Abierto';
            fila.Fecha_Apertura__c = ahora;
            fila.Contador_Ventana__c = nuevoContador;
            fila.Total_Intentos_Bloqueados__c = localCount;
            fila.Correo_Enviado__c = true;
            rv.permitirContinuar = false;
            rv.justOpened = true;
            rv.motivo = 'Se abrio el breaker: ' + nuevoContador + ' intentos > umbral ' + umbral;
        } else {
            fila.Contador_Ventana__c = nuevoContador;
            rv.permitirContinuar = true;
            rv.motivo = 'OK (' + nuevoContador + '/' + umbral + ')';
        }
        return rv;
    }

    private static BreakerResultado fallo(String motivo) {
        BreakerResultado r = new BreakerResultado();
        r.permitirContinuar = false;
        r.estadoBreaker = 'Error';
        r.motivo = motivo;
        return r;
    }
}