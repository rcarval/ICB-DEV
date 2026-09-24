/**********************************************************************************
 * ICB_PIA_RegistrationFlowAction
 * Acción invocable desde Flow para registrar Cuenta en PIA.
 * SEIDOR - Ticket 00026565
 **********************************************************************************/
public with sharing class ICB_PIA_RegistrationFlowAction {

    public class InvocableInput {
        @InvocableVariable(required=true label='Id de Cuenta')
        public Id accountId;

        @InvocableVariable(label='Forzar reintento')
        public Boolean forceRetry;
    }

    public class InvocableOutput {
        @InvocableVariable(label='Éxito')
        public Boolean success;

        @InvocableVariable(label='Estado solicitud PIA')
        public String estadoSolicitud;

        @InvocableVariable(label='Mensaje')
        public String mensaje;
    }

    @InvocableMethod(
        label='Registrar Cuenta en PIA'
        description='Invoca el servicio de registro de usuario PIA para una Cuenta con código SAP.'
        callout=true
        category='PIA'
    )
    public static List<InvocableOutput> registrarCuentaEnPia(List<InvocableInput> inputs) {
        List<InvocableOutput> outputs = new List<InvocableOutput>();
        List<Id> accountIds = new List<Id>();
        Boolean forceRetry = false;

        if (inputs != null) {
            for (InvocableInput input : inputs) {
                if (input != null && input.accountId != null) {
                    accountIds.add(input.accountId);
                    if (input.forceRetry == true) {
                        forceRetry = true;
                    }
                }
            }
        }

        List<ICB_PIA_RegistrationService.RegistrationResult> results =
            ICB_PIA_RegistrationService.registerAccounts(accountIds, forceRetry);

        for (ICB_PIA_RegistrationService.RegistrationResult result : results) {
            InvocableOutput output = new InvocableOutput();
            output.success = result.success;
            output.estadoSolicitud = result.estadoSolicitud;
            output.mensaje = result.mensaje;
            outputs.add(output);
        }

        return outputs;
    }
}