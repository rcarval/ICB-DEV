public with sharing class seidor_FechaRetiroValidator {

    private static final Integer MAX_DIAS_HABILES = 8;

    public static void validar(
        List<Case> nuevos,
        Map<Id, Case> antiguos
    ) {

        Date hoy = Date.today();

        for (Case registro : nuevos) {

            // Solo validar si es nuevo o cambió la fecha
            if (Trigger.isUpdate &&
                antiguos != null &&
                antiguos.containsKey(registro.Id) &&
                registro.Fecha_retiro__c == antiguos.get(registro.Id).Fecha_retiro__c) {
                continue;
            }

            if (registro.Fecha_retiro__c == null) {
                continue;
            }

            // Permitir hoy y fechas futuras
            if (registro.Fecha_retiro__c >= hoy) {
                continue;
            }

            Integer diasHabiles = obtenerDiasHabiles(
                registro.Fecha_retiro__c,
                hoy
            );

            if (diasHabiles > MAX_DIAS_HABILES) {
                registro.Fecha_retiro__c.addError(
                    'Solo se permite seleccionar una fecha con un máximo de 8 días hábiles hacia atrás (lunes a sábado).'
                );
            }
        }
    }

    /**
     * Cuenta días hábiles entre dos fechas.
     * Días hábiles: Lunes a Sábado.
     * Domingo no cuenta.
     */
    private static Integer obtenerDiasHabiles(Date fechaInicio, Date fechaFin) {

        Integer contador = 0;
        Date fecha = fechaInicio;

        while (fecha < fechaFin) {

            fecha = fecha.addDays(1);

            // Domingo = 7 usando formato ISO (u)
            Integer diaSemana = Integer.valueOf(
                DateTime.newInstance(
                    fecha.year(),
                    fecha.month(),
                    fecha.day()
                ).format('u')
            );

            if (diaSemana != 7) {
                contador++;
            }
        }

        return contador;
    }

}