public with sharing class ICBFS_GeocodeLeadShipping {
    public class Request {
        @InvocableVariable(label='Id de Lead' required=true)
        public Id leadId;
    }

    public class Result {
        @InvocableVariable(label='Id de Lead')
        public Id leadId;

        @InvocableVariable(label='Actualizado')
        public Boolean success;

        @InvocableVariable(label='Omitido')
        public Boolean skipped;

        @InvocableVariable(label='Mensaje')
        public String errorMessage;
    }

    @InvocableMethod(label='ICBFS Geocodificar despacho de Lead' callout=true)
    public static List<Result> geocode(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> leadIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.leadId != null) {
                leadIds.add(req.leadId);
            }
        }

        Map<Id, Lead> leadsById = leadIds.isEmpty()
            ? new Map<Id, Lead>()
            : new Map<Id, Lead>([
                SELECT Id,
                       Direccion_de_Despacho__Street__s,
                       Direccion_de_Despacho__City__s,
                       Direccion_de_Despacho__CountryCode__s,
                       Direccion_de_Despacho__Latitude__s,
                       Direccion_de_Despacho__Longitude__s
                FROM Lead
                WHERE Id IN :leadIds
            ]);

        List<Lead> leadsToUpdate = new List<Lead>();
        List<Integer> updateResultIndexes = new List<Integer>();

        for (Request req : requests) {
            Result item = new Result();
            item.leadId = req == null ? null : req.leadId;
            item.success = false;
            item.skipped = false;
            results.add(item);

            if (req == null || req.leadId == null) {
                item.errorMessage = 'LeadId es requerido';
                continue;
            }

            Lead leadItem = leadsById.get(req.leadId);
            if (leadItem == null) {
                item.errorMessage = 'No se encuentra el Lead';
                continue;
            }

            if (leadItem.Direccion_de_Despacho__Latitude__s != null
                && leadItem.Direccion_de_Despacho__Longitude__s != null) {
                item.success = true;
                item.skipped = true;
                item.errorMessage = 'Coordenadas ya informadas; geocodificacion omitida';
                continue;
            }

            if (String.isBlank(leadItem.Direccion_de_Despacho__Street__s)
                || String.isBlank(leadItem.Direccion_de_Despacho__City__s)
                || String.isBlank(leadItem.Direccion_de_Despacho__CountryCode__s)) {
                item.skipped = true;
                item.errorMessage = 'No hay direccion suficiente para geocodificar (calle, ciudad y pais)';
                continue;
            }

            String address = String.join(new List<String>{
                leadItem.Direccion_de_Despacho__Street__s.trim(),
                leadItem.Direccion_de_Despacho__City__s.trim(),
                leadItem.Direccion_de_Despacho__CountryCode__s.trim()
            }, ', ');
            ICBFS_GeocodeFromAccountAddress.GeocodeResponse geo =
                ICBFS_GeocodeFromAccountAddress.geocodeComposedAddress(address);
            if (geo == null || geo.latitude == null || geo.longitude == null) {
                item.errorMessage = geo == null ? 'Respuesta GEO vacia' : geo.errorMessage;
                continue;
            }

            leadsToUpdate.add(new Lead(
                Id = leadItem.Id,
                Direccion_de_Despacho__Latitude__s = geo.latitude,
                Direccion_de_Despacho__Longitude__s = geo.longitude
            ));
            updateResultIndexes.add(results.size() - 1);
        }

        if (!leadsToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(leadsToUpdate, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Result item = results[updateResultIndexes[i]];
                if (saveResults[i].isSuccess()) {
                    item.success = true;
                    item.errorMessage = null;
                } else {
                    item.errorMessage = saveResults[i].getErrors()[0].getMessage();
                }
            }
        }
        return results;
    }
}