public with sharing class ICB_LeadConversionService {

    public class ConversionResult {
        public Id leadId;
        public Id accountId;
        public Id contactId;
        public Boolean success;
        public String message;
    }

    /**
     * Solo en contexto de prueba: evita Database.convertLead y simula conversión exitosa
     * con Account/Contact mínimos para ejecutar el mismo mapeo post-conversión.
     * Llamar desde @IsTest antes de convertAndMapLeads cuando la org bloquea convertLead.
     */
    private static Boolean simulateSuccessfulConversionInTest = false;

    public static void setSimulateSuccessfulConversionForTests(Boolean enabled) {
        if (!Test.isRunningTest()) {
            return;
        }
        simulateSuccessfulConversionInTest = enabled == true;
    }

    /**
     * ApiName del Lead Status al convertir (IsConverted=true en el proceso de candidatos).
     * Database.convertLead usa el API name, no el label (p. ej. label "Cliente Creado" → Prospecto).
     */
    private static final String CONVERTED_LEAD_STATUS_API = 'Prospecto';

    public static List<ConversionResult> convertAndMapLeads(Set<Id> leadIds) {
        List<ConversionResult> orderedResults = new List<ConversionResult>();
        if (leadIds == null || leadIds.isEmpty()) {
            return orderedResults;
        }

        try {
            Map<Id, Lead> leadById = new Map<Id, Lead>([
                SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId, RecordType.Name, LeadSource,
                       FirstName, LastName, Phone, Email, Codigo_Actividad_SII__c,
                       Direccion__City__s, Direccion__CountryCode__s, Direccion__PostalCode__s, Direccion__Street__s,
                       Comunas__c,
                       Direccion_de_Despacho__City__s, Direccion_de_Despacho__CountryCode__s,
                       Direccion_de_Despacho__Latitude__s, Direccion_de_Despacho__Longitude__s,
                       Direccion_de_Despacho__PostalCode__s, Direccion_de_Despacho__Street__s
                FROM Lead
                WHERE Id IN :leadIds
            ]);

            List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
            List<Id> leadIdsToConvert = new List<Id>();

            for (Lead leadItem : leadById.values()) {
                if (!leadItem.IsConverted) {
                    leadIdsToConvert.add(leadItem.Id);
                    if (!(Test.isRunningTest() && simulateSuccessfulConversionInTest)) {
                        Database.LeadConvert convertRequest = new Database.LeadConvert();
                        convertRequest.setLeadId(leadItem.Id);
                        convertRequest.setConvertedStatus(CONVERTED_LEAD_STATUS_API);
                        convertRequest.setDoNotCreateOpportunity(true);
                        converts.add(convertRequest);
                    }
                }
            }

            Map<Id, ConversionResult> resultByLeadId = new Map<Id, ConversionResult>();

            if (Test.isRunningTest() && simulateSuccessfulConversionInTest && !leadIdsToConvert.isEmpty()) {
                for (Id leadId : leadIdsToConvert) {
                    Lead src = leadById.get(leadId);
                    Account acc = new Account(Name = 'ICB Test Conv');
                    insert acc;
                    Id contactId = null;
                    if (src != null) {
                        Contact ct = new Contact(LastName = 'TestConv', AccountId = acc.Id);
                        insert ct;
                        contactId = ct.Id;
                    }
                    ConversionResult cr = new ConversionResult();
                    cr.leadId = leadId;
                    cr.success = true;
                    cr.accountId = acc.Id;
                    cr.contactId = contactId;
                    cr.message = 'Conversión exitosa';
                    resultByLeadId.put(leadId, cr);
                }
            } else if (!converts.isEmpty()) {
                List<Database.LeadConvertResult> convertResults = Database.convertLead(converts, false);
                for (Integer i = 0; i < convertResults.size(); i++) {
                    Id leadId = leadIdsToConvert[i];
                    Database.LeadConvertResult convertResult = convertResults[i];

                    ConversionResult itemResult = new ConversionResult();
                    itemResult.leadId = leadId;
                    itemResult.success = convertResult.isSuccess();
                    if (convertResult.isSuccess()) {
                        itemResult.accountId = convertResult.getAccountId();
                        itemResult.contactId = convertResult.getContactId();
                        itemResult.message = 'Conversión exitosa';
                    } else {
                        String errorMessage = 'Error en conversión';
                        if (convertResult.getErrors() != null && !convertResult.getErrors().isEmpty()) {
                            errorMessage = convertResult.getErrors()[0].getMessage();
                        }
                        itemResult.message = errorMessage;
                    }
                    resultByLeadId.put(leadId, itemResult);
                }
            }

            Map<Id, Lead> refreshedLeads;
            if (Test.isRunningTest() && simulateSuccessfulConversionInTest && !resultByLeadId.isEmpty()) {
                refreshedLeads = buildSyntheticConvertedLeadsMap(leadById, resultByLeadId);
            } else {
                refreshedLeads = new Map<Id, Lead>([
                    SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId, RecordType.Name, LeadSource,
                           FirstName, LastName, Phone, Email, Codigo_Actividad_SII__c,
                           Direccion__City__s, Direccion__CountryCode__s, Direccion__PostalCode__s, Direccion__Street__s,
                           Comunas__c,
                           Direccion_de_Despacho__City__s, Direccion_de_Despacho__CountryCode__s,
                           Direccion_de_Despacho__Latitude__s, Direccion_de_Despacho__Longitude__s,
                           Direccion_de_Despacho__PostalCode__s, Direccion_de_Despacho__Street__s
                    FROM Lead
                    WHERE Id IN :leadIds
                ]);
            }

            List<Account> accountsToUpdate = new List<Account>();
            List<Contact> contactsToUpdate = new List<Contact>();
            List<Lead> leadsToUpdate = new List<Lead>();

            for (Lead leadItem : refreshedLeads.values()) {
                ConversionResult existingResult = resultByLeadId.get(leadItem.Id);
                if (existingResult != null && !existingResult.success) {
                    continue;
                }
                if (!leadItem.IsConverted || leadItem.ConvertedAccountId == null) {
                    ConversionResult failedResult = existingResult == null ? new ConversionResult() : existingResult;
                    failedResult.leadId = leadItem.Id;
                    failedResult.success = false;
                    failedResult.message = 'Lead sin conversión válida';
                    resultByLeadId.put(leadItem.Id, failedResult);
                    continue;
                }

                applyPostConversionRow(
                    leadItem,
                    existingResult,
                    accountsToUpdate,
                    contactsToUpdate,
                    leadsToUpdate,
                    resultByLeadId
                );
            }

            if (!accountsToUpdate.isEmpty()) {
                update accountsToUpdate;
            }
            if (!contactsToUpdate.isEmpty()) {
                update contactsToUpdate;
            }
            if (!leadsToUpdate.isEmpty()) {
                update leadsToUpdate;
            }

            for (Id leadId : leadIds) {
                ConversionResult itemResult = resultByLeadId.get(leadId);
                if (itemResult == null) {
                    itemResult = new ConversionResult();
                    itemResult.leadId = leadId;
                    itemResult.success = false;
                    itemResult.message = 'Lead no encontrado';
                }
                orderedResults.add(itemResult);
            }
            return orderedResults;
        } finally {
            if (Test.isRunningTest()) {
                simulateSuccessfulConversionInTest = false;
            }
        }
    }

    private static Map<Id, Lead> buildSyntheticConvertedLeadsMap(
        Map<Id, Lead> leadById,
        Map<Id, ConversionResult> resultByLeadId
    ) {
        Map<Id, Lead> synthetic = new Map<Id, Lead>();
        for (Id leadId : leadById.keySet()) {
            ConversionResult cr = resultByLeadId.get(leadId);
            if (cr == null || !cr.success || cr.accountId == null) {
                continue;
            }
            Lead src = leadById.get(leadId);
            if (src == null) {
                continue;
            }
            Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(src));
            untyped.put('IsConverted', true);
            untyped.put('ConvertedAccountId', String.valueOf(cr.accountId));
            if (cr.contactId != null) {
                untyped.put('ConvertedContactId', String.valueOf(cr.contactId));
            }
            Lead merged = (Lead) JSON.deserialize(JSON.serialize(untyped), Lead.class);
            synthetic.put(leadId, merged);
        }
        return synthetic;
    }

    private static void applyPostConversionRow(
        Lead leadItem,
        ConversionResult existingResult,
        List<Account> accountsToUpdate,
        List<Contact> contactsToUpdate,
        List<Lead> leadsToUpdate,
        Map<Id, ConversionResult> resultByLeadId
    ) {
        Account accountToUpdate = new Account(Id = leadItem.ConvertedAccountId);
        accountToUpdate.BillingCity = leadItem.Direccion__City__s;
        accountToUpdate.BillingCountry = leadItem.Direccion__CountryCode__s;
        accountToUpdate.BillingPostalCode = leadItem.Direccion__PostalCode__s;
        accountToUpdate.BillingStreet = leadItem.Direccion__Street__s;
        accountToUpdate.Comuna_Facturaci_n__c = leadItem.Comunas__c;
        accountToUpdate.Email__c = leadItem.Email;
        accountToUpdate.Lead__c = leadItem.Id;
        accountToUpdate.Nombre_de_contacto__c = buildContactName(leadItem.FirstName, leadItem.LastName);
        accountToUpdate.ShippingCity = leadItem.Direccion_de_Despacho__City__s;
        accountToUpdate.ShippingCountry = leadItem.Direccion_de_Despacho__CountryCode__s;
        accountToUpdate.ShippingLatitude = leadItem.Direccion_de_Despacho__Latitude__s;
        accountToUpdate.ShippingLongitude = leadItem.Direccion_de_Despacho__Longitude__s;
        accountToUpdate.ShippingPostalCode = leadItem.Direccion_de_Despacho__PostalCode__s;
        accountToUpdate.ShippingStreet = leadItem.Direccion_de_Despacho__Street__s;
        accountToUpdate.Tipificaci_n_de_Origen__c = mapTipificacion(leadItem.LeadSource);
        accountToUpdate.Codigo_Actividad_SII__c = leadItem.Codigo_Actividad_SII__c;
        accountsToUpdate.add(accountToUpdate);

        if (leadItem.ConvertedContactId != null) {
            Contact contactToUpdate = new Contact(Id = leadItem.ConvertedContactId);
            contactToUpdate.MobilePhone = leadItem.Phone;
            contactsToUpdate.add(contactToUpdate);
        }

        Lead leadToUpdate = new Lead(Id = leadItem.Id);
        leadToUpdate.Account__c = leadItem.ConvertedAccountId;
        leadsToUpdate.add(leadToUpdate);

        ConversionResult successResult = existingResult == null ? new ConversionResult() : existingResult;
        successResult.leadId = leadItem.Id;
        successResult.accountId = leadItem.ConvertedAccountId;
        successResult.contactId = leadItem.ConvertedContactId;
        successResult.success = true;
        if (String.isBlank(successResult.message)) {
            successResult.message = 'Conversión y mapeo exitosos';
        }
        resultByLeadId.put(leadItem.Id, successResult);
    }

    private static String buildContactName(String firstName, String lastName) {
        String firstPart = firstName == null ? '' : firstName.trim();
        String lastPart = lastName == null ? '' : lastName.trim();
        if (String.isBlank(firstPart)) {
            return lastPart;
        }
        if (String.isBlank(lastPart)) {
            return firstPart;
        }
        return firstPart + ' ' + lastPart;
    }

    private static String mapTipificacion(String leadSource) {
        Set<String> leadSourceWeb = new Set<String>{ 'Web Hablemos', 'Web Contactanos', 'Catalogo web', 'CCC' };
        return leadSourceWeb.contains(leadSource) ? leadSource : 'Terreno';
    }
}