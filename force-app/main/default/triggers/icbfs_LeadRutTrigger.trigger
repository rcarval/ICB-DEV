/**
 * @Name        : icbfs_LeadRutTrigger
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Valida RUT__c en Lead y asigna Account__c buscando primero por RUT y,
 *                si no hay coincidencia, por Email como fallback.
 */
trigger icbfs_LeadRutTrigger on Lead (before insert, before update) {

    List<Lead> leadsAProc = new List<Lead>();
    Set<String> rutsParaBuscar = new Set<String>();

    for (Lead l : Trigger.new) {
        String rut   = l.RUT__c;
        String email = l.Email;

        // En update: procesar solo si cambió el RUT o el Email
        if (Trigger.isUpdate) {
            Lead old = Trigger.oldMap.get(l.Id);
            if (rut == old.RUT__c && email == old.Email) continue;
        }

        // Validar RUT si viene con valor
        if (!String.isBlank(rut)) {
            icbfs_RutValidator.Result res = icbfs_RutValidator.validate(rut, l.LeadSource);
            if (!res.isFormatOk) {
                l.RUT__c.addError('Formato de RUT incorrecto. Usa xxxxxxxx-x (sin puntos y con guion).');
                continue;
            } else if (!res.isValid) {
                l.RUT__c.addError('RUT inválido');
                continue;
            }
            rutsParaBuscar.add(rut);
        }

        leadsAProc.add(l);
    }

    if (leadsAProc.isEmpty()) return;

    // ── Búsqueda por RUT ────────────────────────────────────────────────
    Map<String, Id> rutACuentaId = new Map<String, Id>();
    if (!rutsParaBuscar.isEmpty()) {
        for (Account acc : [SELECT Id, RUT__c FROM Account WHERE RUT__c IN :rutsParaBuscar LIMIT 10000]) {
            rutACuentaId.put(acc.RUT__c, acc.Id);
        }
    }

    // Asignar desde RUT; acumular emails de los que no tuvieron match
    Set<String> emailsParaBuscar = new Set<String>();
    for (Lead l : leadsAProc) {
        if (!String.isBlank(l.RUT__c) && rutACuentaId.containsKey(l.RUT__c)) {
            l.Account__c = rutACuentaId.get(l.RUT__c);
        } else if (!String.isBlank(l.Email)) {
            emailsParaBuscar.add(l.Email);
        }
    }

    // ── Fallback por Email ───────────────────────────────────────────────
    if (emailsParaBuscar.isEmpty()) return;

    Map<String, Id> emailACuentaId = new Map<String, Id>();
    for (Account acc : [SELECT Id, Email__c FROM Account WHERE Email__c IN :emailsParaBuscar LIMIT 10000]) {
        if (!String.isBlank(acc.Email__c)) {
            emailACuentaId.put(acc.Email__c, acc.Id);
        }
    }

    for (Lead l : leadsAProc) {
        if (l.Account__c != null) continue;
        if (String.isBlank(l.Email)) continue;
        if (emailACuentaId.containsKey(l.Email)) {
            l.Account__c = emailACuentaId.get(l.Email);
        }
    }
}