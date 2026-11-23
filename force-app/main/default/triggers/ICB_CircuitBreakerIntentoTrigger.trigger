/**
 * @Name        : ICB_CircuitBreakerIntentoTrigger
 * @Description : Suscriptor del Platform Event Circuit_Breaker_Intento__e. Corre async,
 *                en transaccion propia, para que el conteo/apertura/notificacion del
 *                Circuit Breaker sobreviva aunque el guardado que origino el intento
 *                haya sido rechazado por ICB_AccountCircuitBreakerGate.
 */
trigger ICB_CircuitBreakerIntentoTrigger on Circuit_Breaker_Intento__e (after insert) {
    ICB_CircuitBreakerAsyncHandler.procesarIntentos(Trigger.new);
}