/**
 * Persiste los ajustes excepcionales de Comodato que se capturaron EN MEMORIA durante el
 * flujo de creacion de propuesta, una vez que la Quote ya existe.
 *
 * Por que existe: el usuario ajusta los valores ANTES de que se cree la Opportunity y la
 * Quote (no tiene sentido crear una propuesta con valores que todavia no estan ajustados).
 * En ese momento no se puede crear un Comodato_Override__c porque Quote__c es obligatorio,
 * asi que la pantalla de ajuste entrega los cambios como JSON y esta accion los materializa
 * inmediatamente despues de crear la Quote, antes de generar el PDF y las partidas.
 *
 * Comodato__c (configuracion maestra) nunca se modifica: cada ajuste es un registro
 * Comodato_Override__c ligado a esa Quote.
 */
public with sharing class PersistirAjustesComodatoAction {

    @InvocableMethod(
        label='Persistir Ajustes Comodato'
        description='Crea los Comodato_Override__c a partir de los ajustes capturados en la pantalla de ajuste'
    )
    public static List<Output> persistir(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input i : inputs) {
            try {
                results.add(new Output(procesar(i), true, ''));
            } catch (Exception e) {
                // No se corta la creacion de la propuesta por un fallo al persistir el ajuste:
                // se informa al Flow para que decida, y el PDF saldria con valores originales.
                results.add(new Output(0, false, e.getMessage()));
            }
        }
        return results;
    }

    private static Integer procesar(Input input) {
        if (input.quoteId == null || String.isBlank(input.ajustesJson)) {
            return 0;
        }

        List<Ajuste> ajustes;
        try {
            ajustes = (List<Ajuste>) JSON.deserialize(input.ajustesJson, List<Ajuste>.class);
        } catch (Exception e) {
            throw new AjustesException('No se pudieron leer los ajustes capturados: ' + e.getMessage());
        }
        if (ajustes == null || ajustes.isEmpty()) {
            return 0;
        }

        Integer creados = 0;
        for (Ajuste a : ajustes) {
            if (a.comodatoId == null) {
                continue;
            }
            // registrarAjuste() valida el Custom Permission, exige motivo y desactiva
            // cualquier override previo de ese Comodato en la misma Quote.
            ComodatoOverrideResolver.registrarAjuste(
                a.comodatoId,
                input.quoteId,
                a.cantidadAjustada,
                a.unidadAjustada,
                a.precioAjustado,
                a.motivo
            );
            creados++;
        }
        return creados;
    }

    public class Ajuste {
        public Id comodatoId;
        public Decimal cantidadAjustada;
        public String unidadAjustada;
        public Decimal precioAjustado;
        public String motivo;
    }

    public class AjustesException extends Exception {}

    public class Input {
        @InvocableVariable(label='ID de la Quote' required=true)
        public Id quoteId;

        @InvocableVariable(label='Ajustes capturados (JSON)' required=false)
        public String ajustesJson;
    }

    public class Output {
        @InvocableVariable public Integer ajustesCreados;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;

        public Output(Integer creados, Boolean ok, String msg) {
            this.ajustesCreados = creados;
            this.success = ok;
            this.errorMessage = msg;
        }
    }
}