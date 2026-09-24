public with sharing class seidor_mapeoTipoContactoEmail {

    /*
    =========================================
    INPUT FLOW
    =========================================
    */
    public class InputWrapper {

        @InvocableVariable(required=true)
        public Id accountId;
    }

    /*
    =========================================
    OUTPUT FLOW
    =========================================
    */
    public class OutputWrapper {

        @InvocableVariable
        public Id contactId;

        @InvocableVariable
        public String contactName;

        @InvocableVariable
        public String contactEmail;

        @InvocableVariable
        public String tipoContactoEncontrado;
    }

    @InvocableMethod(label='Obtener Contactos para Email' description='Obtiene todos los contactos con email de la cuenta, o el email de la cuenta si no hay contactos')
    public static List<OutputWrapper> obtenerContactoPrioritario(List<InputWrapper> requests) 
    {

        List<OutputWrapper> responseList = new List<OutputWrapper>();

        for(InputWrapper req : requests) {

            List<Contact> contactos = [
                SELECT Id, Name, Email, Tipo_de_contacto__c
                FROM Contact
                WHERE AccountId = :req.accountId
                AND Email != null
            ];

            if(!contactos.isEmpty()) {

                for(Contact con : contactos) {
                    OutputWrapper output = new OutputWrapper();
                    output.contactId = con.Id;
                    output.contactName = con.Name;
                    output.contactEmail = con.Email;
                    output.tipoContactoEncontrado = con.Tipo_de_contacto__c;
                    responseList.add(output);
                }

            } else {

                Account cuenta = [
                    SELECT Email__c, Name
                    FROM Account
                    WHERE Id = :req.accountId
                    LIMIT 1
                ];

                if(String.isNotBlank(cuenta.Email__c)) {
                    OutputWrapper output = new OutputWrapper();
                    output.contactEmail = cuenta.Email__c;
                    output.contactName = cuenta.Name;
                    output.tipoContactoEncontrado = 'Email de cuenta';
                    responseList.add(output);
                }
            }
        }

        return responseList;
    }
}