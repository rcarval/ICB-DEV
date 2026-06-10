/**********************************************************************************
ICB Food Service
Desarrollado por: José Illanes
Fecha       : 2026-04-08
Descripción : Controller para LWC de cola de impresión QR.
              Consulta escaneos no impresos por campaña y marca como impresos.
**********************************************************************************/
public with sharing class QRPrintController {
    private static final String DEFAULT_QR_LANDING_BASE_URL = 'https://energy-saas-7178.my.site.com/openday';

    public class ScanWrapper {
        @AuraEnabled public Id scanId;
        @AuraEnabled public List<Id> scanIds;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public String token;
        @AuraEnabled public String memberToken;
        @AuraEnabled public String memberName;
        @AuraEnabled public Id memberRecordId;
        @AuraEnabled public String memberType;
        @AuraEnabled public Datetime scanDate;
        @AuraEnabled public String scanUserName;

        public ScanWrapper(
            QR_Scan__c scan,
            String memberToken,
            String name,
            Id memberRecordId,
            String memberType,
            String userName
        ) {
            this.scanId = scan.Id;
            this.scanIds = new List<Id>{ scan.Id };
            this.quantity = 1;
            this.token = scan.Token__c;
            this.memberToken = memberToken;
            this.memberName = name;
            this.memberRecordId = memberRecordId;
            this.memberType = memberType;
            this.scanDate = scan.Fecha_Hora__c;
            this.scanUserName = userName;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ScanWrapper> getUnprintedScans(Id campaignId) {
        if (campaignId == null) {
            throw new AuraHandledException('Campaign ID es requerido.');
        }

        List<QR_Scan__c> scans = [
            SELECT Id, Token__c, Fecha_Hora__c, Scan_Usuario__r.Name, CampaignMemberId__c
            FROM QR_Scan__c
            WHERE Campa_a__c = :campaignId
            AND Impreso__c = false
            ORDER BY Fecha_Hora__c ASC
        ];

        Set<Id> memberIds = new Set<Id>();
        for (QR_Scan__c scan : scans) {
            if (scan.CampaignMemberId__c != null) {
                memberIds.add(Id.valueOf(scan.CampaignMemberId__c));
            }
        }

        Map<Id, CampaignMember> memberMap = new Map<Id, CampaignMember>();
        if (!memberIds.isEmpty()) {
            for (CampaignMember cm : [
                SELECT Id, QR_Token__c, LeadId, ContactId, AccountId, Lead.Name, Contact.Name, Account.Name
                FROM CampaignMember
                WHERE Id IN :memberIds
            ]) {
                memberMap.put(cm.Id, cm);
            }
        }

        List<ScanWrapper> wrappers = new List<ScanWrapper>();
        Map<String, ScanWrapper> grouped = new Map<String, ScanWrapper>();
        for (QR_Scan__c scan : scans) {
            String memberName = 'Sin Nombre';
            String memberToken = null;
            Id memberRecordId = null;
            String memberType = 'Miembro';
            String groupKey = 'SCAN_' + String.valueOf(scan.Id);
            if (scan.CampaignMemberId__c != null) {
                Id cmId = Id.valueOf(scan.CampaignMemberId__c);
                groupKey = 'CM_' + String.valueOf(cmId);
                CampaignMember cm = memberMap.get(cmId);
                if (cm != null) {
                    memberRecordId = cm.Id;
                    if (cm.LeadId != null) {
                        memberType = 'Lead';
                        memberName = cm.Lead?.Name ?? 'Sin Nombre';
                    } else if (cm.ContactId != null) {
                        memberType = 'Contacto';
                        memberName = cm.Contact?.Name ?? 'Sin Nombre';
                    } else if (cm.AccountId != null) {
                        memberType = 'Cuenta';
                        memberName = cm.Account?.Name ?? 'Sin Nombre';
                    } else {
                        memberName = cm.Lead?.Name ??
                                     cm.Contact?.Name ??
                                     cm.Account?.Name ??
                                     'Sin Nombre';
                    }
                    memberToken = cm.QR_Token__c;
                }
            }

            String userName = scan.Scan_Usuario__r != null ? scan.Scan_Usuario__r.Name : 'Desconocido';
            if (grouped.containsKey(groupKey)) {
                ScanWrapper existing = grouped.get(groupKey);
                existing.scanIds.add(scan.Id);
                existing.quantity = existing.scanIds.size();
                if (scan.Fecha_Hora__c != null && (existing.scanDate == null || scan.Fecha_Hora__c > existing.scanDate)) {
                    existing.scanDate = scan.Fecha_Hora__c;
                    existing.scanUserName = userName;
                }
            } else {
                ScanWrapper row = new ScanWrapper(scan, memberToken, memberName, memberRecordId, memberType, userName);
                grouped.put(groupKey, row);
                wrappers.add(row);
            }
        }

        return wrappers;
    }

    @AuraEnabled
    public static void markAsPrinted(Id scanId) {
        if (scanId == null) {
            throw new AuraHandledException('Scan ID es requerido.');
        }

        QR_Scan__c scan = new QR_Scan__c(Id = scanId, Impreso__c = true);
        update scan;
    }

    @AuraEnabled
    public static void markAsPrintedBatch(List<Id> scanIds) {
        if (scanIds == null || scanIds.isEmpty()) {
            throw new AuraHandledException('Debe enviar al menos un Scan ID.');
        }

        Set<Id> uniqueIds = new Set<Id>();
        for (Id scanId : scanIds) {
            if (scanId != null) {
                uniqueIds.add(scanId);
            }
        }
        if (uniqueIds.isEmpty()) {
            throw new AuraHandledException('Scan IDs inválidos.');
        }

        List<QR_Scan__c> scansToUpdate = new List<QR_Scan__c>();
        for (Id idToUpdate : uniqueIds) {
            scansToUpdate.add(new QR_Scan__c(Id = idToUpdate, Impreso__c = true));
        }
        update scansToUpdate;
    }

    @AuraEnabled(cacheable=true)
    public static String getQRData(Id scanId) {
        if (scanId == null) {
            throw new AuraHandledException('Scan ID es requerido.');
        }

        QR_Scan__c scan = [
            SELECT Id, CampaignMemberId__c
            FROM QR_Scan__c
            WHERE Id = :scanId
            LIMIT 1
        ];

        if (scan == null) {
            throw new AuraHandledException('Escaneo no encontrado.');
        }

        if (String.isBlank(scan.CampaignMemberId__c)) {
            throw new AuraHandledException('El escaneo no tiene CampaignMember asociado.');
        }

        Id campaignMemberId;
        try {
            campaignMemberId = Id.valueOf(scan.CampaignMemberId__c);
        } catch (Exception e) {
            throw new AuraHandledException('CampaignMemberId inválido en el escaneo.');
        }

        CampaignMember cm = [
            SELECT Id, QR_Token__c
            FROM CampaignMember
            WHERE Id = :campaignMemberId
            LIMIT 1
        ];

        if (cm == null || String.isBlank(cm.QR_Token__c)) {
            throw new AuraHandledException('El CampaignMember no tiene QR_Token__c para imprimir.');
        }

        String landing = DEFAULT_QR_LANDING_BASE_URL;
        if (!landing.endsWith('/')) {
            landing += '/';
        }

        return landing + '?token=' + EncodingUtil.urlEncode(cm.QR_Token__c.trim(), 'UTF-8');
    }
}