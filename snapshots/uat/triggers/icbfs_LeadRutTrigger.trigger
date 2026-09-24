/**
 * @Name        : icbfs_LeadRutTrigger
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Valida RUT__c en Lead.
 */
trigger icbfs_LeadRutTrigger on Lead (before insert, before update) {

    for (Lead l : Trigger.new) {
        String rut = l.RUT__c;
        String oldRut = Trigger.isUpdate ? Trigger.oldMap.get(l.Id).RUT__c : null;

        // Si no cambió, no revalidar
        if (Trigger.isUpdate && rut == oldRut) continue;

        // Vacío no bloquea
        if (String.isBlank(rut)) continue;

        icbfs_RutValidator.Result res = icbfs_RutValidator.validate(rut);

        if (!res.isFormatOk) {
            l.RUT__c.addError('Formato de RUT incorrecto. Usa xxxxxxxx-x (sin puntos y con guion).');
        } else if (!res.isValid) {
            l.RUT__c.addError('RUT inválido');
        }
    }
}