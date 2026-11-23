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
        if (inputs == null) return;
        List<Lead> leadsToUpdate = new List<Lead>();
        for (Input inp : inputs) if (inp != null && inp.leadId != null && inp.campaignId != null) {
            try {
                Lead leadToUpdate = new Lead(Id = inp.leadId);
                leadToUpdate.put('CampaignId', inp.campaignId);
                leadsToUpdate.add(leadToUpdate);
            } catch (Exception e) {
                return;
            }
        }
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
    }
}