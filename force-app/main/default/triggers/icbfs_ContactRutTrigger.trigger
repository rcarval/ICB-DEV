/**
 * @Name        : icbfs_ContactRutTrigger
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Valida RUT__c en Contact.
 */
trigger icbfs_ContactRutTrigger on Contact (before insert, before update) {

    for (Contact c : Trigger.new) {
        String rut = c.RUT__c;
        String oldRut = Trigger.isUpdate ? Trigger.oldMap.get(c.Id).RUT__c : null;

        // Si no cambió, no revalidar
        if (Trigger.isUpdate && rut == oldRut) continue;

        // Vacío no bloquea
        if (String.isBlank(rut)) continue;

        icbfs_RutValidator.Result res = icbfs_RutValidator.validate(rut);

        if (!res.isFormatOk) {
            c.RUT__c.addError('Formato de RUT incorrecto. Usa xxxxxxxx-x (sin puntos y con guion).');
        } else if (!res.isValid) {
            c.RUT__c.addError('RUT inválido');
        }
    }
}