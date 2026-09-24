public with sharing class ICB_FirmaDigitalPrecheckAction {
    public class ValidationInput {
        @InvocableVariable(required=true label='Opportunity Id')
        public String opportunityId;
    }

    public class ValidationOutput {
        @InvocableVariable(label='Válido')
        public Boolean valid;
        @InvocableVariable(label='Mensaje')
        public String message;
    }

    @InvocableMethod(label='Validar requisitos de Firma Digital por Opportunity' description='Valida aprobación y función de contacto (Representante Legal con RUT, móvil y correo)' callout=false)
    public static List<ValidationOutput> validarRequisitosOpportunity(List<ValidationInput> inputs) {
        List<ValidationOutput> outs = new List<ValidationOutput>();
        for (ValidationInput input : inputs) {
            ValidationOutput out = new ValidationOutput();
            out.valid = false;
            out.message = null;

            Id oppId = (input == null || String.isBlank(input.opportunityId)) ? null : (Id) input.opportunityId;
            if (oppId == null) {
                out.message = 'Debe informar una Opportunity válida.';
                outs.add(out);
                continue;
            }

            Opportunity opp;
            List<Opportunity> opps = [SELECT Id, Estado_de_Aprobacion__c FROM Opportunity WHERE Id = :oppId LIMIT 1];
            opp = opps.isEmpty() ? null : opps[0];
            if (opp == null || opp.Estado_de_Aprobacion__c != 'Aprobado') {
                out.message = 'El proceso está en Solicitud de Aprobación. Debe estar Aprobado para continuar.';
                outs.add(out);
                continue;
            }

            List<OpportunityContactRole> roles = [
                SELECT ContactId, Role, IsPrimary, Contact.RUT__c, Contact.RUT_Contacto__c, Contact.MobilePhone, Contact.Email
                FROM OpportunityContactRole
                WHERE OpportunityId = :oppId AND ContactId != null AND IsDeleted = false
                ORDER BY IsPrimary DESC, CreatedDate ASC
            ];
            Boolean cumple = false;
            for (OpportunityContactRole r : roles) {
                String rol = r.Role == null ? '' : r.Role.toLowerCase();
                if (!rol.contains('representante legal')) continue;
                if (r.Contact == null) continue;
                String rut = String.isNotBlank(r.Contact.RUT__c) ? r.Contact.RUT__c : r.Contact.RUT_Contacto__c;
                if (String.isBlank(rut) || String.isBlank(r.Contact.MobilePhone) || String.isBlank(r.Contact.Email)) continue;
                cumple = true;
                break;
            }
            if (!cumple) {
                out.message = 'La oportunidad debe tener una Función de contacto con Rol Representante Legal, y el contacto debe tener RUT, móvil y correo.';
                outs.add(out);
                continue;
            }

            out.valid = true;
            out.message = 'OK';
            outs.add(out);
        }
        return outs;
    }
}