public with sharing class ICBFS_CampaignMemberCanalHandler {

    private static final String MANUAL_CANAL = 'Manual';

    public static void beforeInsert(List<CampaignMember> newList) {
        if (newList == null || newList.isEmpty()) return;

        for (CampaignMember cm : newList) {
            if (cm == null) continue;
            if (!String.isBlank(cm.Canal__c)) continue;
            if (cm.LeadId != null) continue;
            if (cm.ContactId == null && cm.AccountId == null) continue;

            cm.Canal__c = MANUAL_CANAL;
        }
    }
}