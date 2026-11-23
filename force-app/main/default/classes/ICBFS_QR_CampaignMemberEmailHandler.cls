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
            SELECT Id, ID_Formulario_WEB__c, IsActive,
                   OpenDay_Header_URL__c, OpenDay_Footer_URL__c, OpenDay_Maps_URL__c
            FROM Campaign
            WHERE Id IN :memberIdsByCampaign.keySet()
        ]) {
            if (campaign.IsActive != true) continue;

            Route route = routeFor(campaign);
            if (route == null) continue;

            System.enqueueJob(new ICBFS_QR_SendCampaignQueue(
                campaign.Id,
                ACCOUNT_EMAIL_FIELD,
                LANDING_BASE_URL,
                SUBJECT,
                route.headerUrl,
                route.footerUrl,
                route.mapsUrl,
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

    private static Route routeFor(Campaign campaign) {
        if (campaign == null) return null;

        Route fallback = legacyRouteFor(campaign.ID_Formulario_WEB__c);
        String headerUrl = firstValue(campaign.OpenDay_Header_URL__c, fallback == null ? null : fallback.headerUrl);
        String footerUrl = firstValue(campaign.OpenDay_Footer_URL__c, fallback == null ? null : fallback.footerUrl);
        String mapsUrl = firstValue(campaign.OpenDay_Maps_URL__c, fallback == null ? null : fallback.mapsUrl);

        if (String.isBlank(headerUrl) || String.isBlank(footerUrl)) return null;
        return new Route(headerUrl, footerUrl, mapsUrl);
    }

    private static Route legacyRouteFor(String formKey) {
        if (String.isBlank(formKey)) return null;

        String key = formKey.toLowerCase();
        if (key.contains('concepcion24062026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_CONC.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_CONC.png',
                null
            );
        }
        if (key.contains('antofagasta19052026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_ANT.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_ANT.png',
                null
            );
        }
        if (key.contains('curico16042026')) {
            return new Route(
                'https://github.com/tron0110/icbfs-openday-assets/raw/main/OD_HEADER_CUR.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_CUR.png',
                null
            );
        }
        if (key.contains('25032026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/ICBFS_OPENDAY_HEADER.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/ICBFS_OPENDAY_FOOTER.png',
                null
            );
        }
        if (key.contains('iquique06082026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_IQU.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_IQU.png',
                'https://maps.app.goo.gl/eZ7FNJ9qkjjgGqkeA'
            );
        }
        if (key.contains('temuco09092026')) {
            return new Route(
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_HEADER_TEMUCO.png',
                'https://raw.githubusercontent.com/tron0110/icbfs-openday-assets/main/OD_FOOTER_TEMUCO.png',
                'https://maps.app.goo.gl/xFGb4cMDPF52kMrcA'
            );
        }

        return null;
    }

    private static String firstValue(String preferred, String fallback) {
        return String.isBlank(preferred) ? fallback : preferred.trim();
    }

    private class Route {
        private String headerUrl;
        private String footerUrl;
        private String mapsUrl;

        private Route(String headerUrl, String footerUrl, String mapsUrl) {
            this.headerUrl = headerUrl;
            this.footerUrl = footerUrl;
            this.mapsUrl = mapsUrl;
        }
    }
}