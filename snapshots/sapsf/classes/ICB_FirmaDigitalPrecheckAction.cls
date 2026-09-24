public with sharing class ICB_FirmaDigitalPrecheckAction {

    /** Valor exacto de la lista Tipo de contacto que habilita la firma. */
    private static final String TIPO_REPRESENTANTE_LEGAL = 'Representante Legal';

    /** RUT sin puntos y con guion: 7 u 8 digitos, guion, digito verificador (0-9 o K). */
    private static final String PATRON_RUT = '^\\d{7,8}-[\\dkK]$';

    /** Movil chileno: +569 seguido de 8 digitos. */
    private static final String PATRON_MOVIL = '^\\+569\\d{8}$';
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
                SELECT ContactId, Role, IsPrimary, Contact.Rut__c, Contact.RUT_Contacto__c,
                       Contact.Tipo_de_contacto__c, Contact.MobilePhone, Contact.Email
                FROM OpportunityContactRole
                WHERE OpportunityId = :oppId AND ContactId != null AND IsDeleted = false
                ORDER BY IsPrimary DESC, CreatedDate ASC
            ];
            Boolean cumple = false;
            List<String> motivos = new List<String>();
            Boolean hayRepresentante = false;

            for (OpportunityContactRole r : roles) {
                String rol = r.Role == null ? '' : r.Role.toLowerCase();
                if (!rol.contains('representante legal')) continue;
                if (r.Contact == null) continue;
                hayRepresentante = true;

                List<String> faltas = new List<String>();

                // El contacto debe estar marcado como Representante Legal en Tipo de contacto.
                String tipos = r.Contact.Tipo_de_contacto__c == null ? '' : r.Contact.Tipo_de_contacto__c;
                if (!tipos.contains(TIPO_REPRESENTANTE_LEGAL)) {
                    faltas.add('el campo Tipo de contacto debe incluir "' + TIPO_REPRESENTANTE_LEGAL + '"');
                }

                String rut = String.isNotBlank(r.Contact.Rut__c) ? r.Contact.Rut__c : r.Contact.RUT_Contacto__c;
                if (String.isBlank(rut)) {
                    faltas.add('falta el RUT');
                } else if (!Pattern.matches(PATRON_RUT, rut.trim())) {
                    faltas.add('el RUT debe ir sin puntos y con guion (ej: 12345678-9), y esta como "' + rut.trim() + '"');
                }

                String movil = r.Contact.MobilePhone == null ? '' : r.Contact.MobilePhone.replaceAll('\\s', '');
                if (String.isBlank(movil)) {
                    faltas.add('falta el teléfono móvil');
                } else if (!Pattern.matches(PATRON_MOVIL, movil)) {
                    faltas.add('el móvil debe ser +569 seguido de 8 dígitos (ej: +56988530660), y esta como "' + r.Contact.MobilePhone + '"');
                }

                if (String.isBlank(r.Contact.Email)) {
                    faltas.add('falta el correo electrónico');
                }

                if (faltas.isEmpty()) {
                    cumple = true;
                    break;
                }
                motivos.add(faltas.size() == 1 ? faltas[0] : String.join(faltas, '; '));
            }

            if (!cumple) {
                if (!hayRepresentante) {
                    out.message = 'La oportunidad debe tener una Función de contacto con Rol Representante Legal.';
                } else {
                    out.message = 'El Representante Legal no cumple: ' + String.join(motivos, ' | ') + '.';
                }
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