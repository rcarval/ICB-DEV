public with sharing class ICBFS_QR_CampaignMemberEmailHandler {

    private static final String LANDING_BASE_URL = 'https://energy-saas-7178.my.site.com/openday';
    private static final String SUBJECT = 'ICB Food Service OPENDAY';
    private static final String ACCOUNT_EMAIL_FIELD = 'Email__c';

    public static void afterSave(List<CampaignMember> newList, Map<Id, CampaignMember> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        Map<Id, Set<Id>> memberIdsByCampaign = new Map<Id, Set<Id>>();
        for (CampaignMember cm : newList) {
            if (!shouldSend(cm, oldMap == null ? null : oldMap.get(cm.Id))) continue;

            if (!memberIdsByCampaign.containsKey(cm.CampaignId)) {
                memberIdsByCampaign.put(cm.CampaignId, new Set<Id>());
            }
            memberIdsByCampaign.get(cm.CampaignId).add(cm.Id);
        }

        if (memberIdsByCampaign.isEmpty()) return;

        for (Campaign campaign : [
            SELECT Id, ID_Formulario_WEB__c, IsActive
            FROM Campaign
            WHERE Id IN :memberIdsByCampaign.keySet()
        ]) {
            if (campaign.IsActive != true) continue;

            Route route = routeFor(campaign.ID_Formulario_WEB__c);
            if (route == null) continue;

            System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
                campaign.Id,
                ACCOUNT_EMAIL_FIELD,
                LANDING_BASE_URL,
                SUBJECT,
                route.headerUrl,
                route.footerUrl,
                ICBFS_QR_SendCampaignQueue.SEND_MODE_MASSIVE,
                memberIdsByCampaign.get(campaign.Id)
            ));
        }
    }

    private static Boolean shouldSend(CampaignMember current, CampaignMember oldRecord) {
        if (current == null) return false;
        if (current.CampaignId == null) return false;
        if (current.QR_Enviado__c == true) return false;
        if (String.isBlank(current.QR_Token__c)) return false;

        if (oldRecord == null) return true;
        return String.isBlank(oldRecord.QR_Token__c) && !String.isBlank(current.QR_Token__c);
    }

    private static Route routeFor(String formKey) {
        if (String.isBlank(formKey)) return null;

        String key = formKey.toLowerCase();
        if (key.contains('concepcion24062026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_CONC.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_CONC.png'
            );
        }
        if (key.contains('antofagasta19052026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_ANT.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_ANT.png'
            );
        }
        if (key.contains('curico16042026')) {
            return new Route(
                'https://github.com/tron0110/icbfs-openday-assets/raw/main/OD_HEADER_CUR.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_CUR.png'
            );
        }
        if (key.contains('25032026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/ICBFS_OPENDAY_HEADER.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/ICBFS_OPENDAY_FOOTER.png'
            );
        }

        return null;
    }

    private class Route {
        private String headerUrl;
        private String footerUrl;

        private Route(String headerUrl, String footerUrl) {
            this.headerUrl = headerUrl;
            this.footerUrl = footerUrl;
        }
    }
}