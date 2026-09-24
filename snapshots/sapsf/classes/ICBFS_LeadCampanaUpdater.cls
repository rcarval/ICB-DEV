public with sharing class ICBFS_LeadCampanaUpdater {

    public class Input {
        @InvocableVariable(required=true label='Lead ID')
        public Id leadId;

        @InvocableVariable(required=true label='Campaign ID')
        public Id campaignId;
    }

    @InvocableMethod(
        label='Asignar Campana al Lead'
        description='Actualiza el campo CampaignId estandar del Lead con la campana OpenDay encontrada.'
    )
    public static void asignarCampana(List<Input> inputs) {
        Map<String, Schema.SObjectField> leadFields = Lead.SObjectType.getDescribe().fields.getMap();
        if (!leadFields.containsKey('CampaignId')) {
            return;
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Input inp : inputs) {
            if (inp == null || inp.leadId == null || inp.campaignId == null) {
                continue;
            }

            Lead leadToUpdate = new Lead(Id = inp.leadId);
            leadToUpdate.put('CampaignId', inp.campaignId);
            leadsToUpdate.add(leadToUpdate);
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
}