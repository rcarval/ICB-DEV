/**
 * @Name        : icbfs_AccountRutTrigger
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Valida RUT__c en Account.
 */
trigger icbfs_AccountRutTrigger on Account (before insert, before update) {

    for (Account a : Trigger.new) {
        String rut = a.RUT__c;
        String oldRut = Trigger.isUpdate ? Trigger.oldMap.get(a.Id).RUT__c : null;

        if (Trigger.isUpdate && rut == oldRut) continue;

        if (String.isBlank(rut)) continue;

        icbfs_RutValidator.Result res = icbfs_RutValidator.validate(rut);

        if (!res.isFormatOk) {
            a.RUT__c.addError('Formato de RUT incorrecto. Usa xxxxxxxx-x (sin puntos y con guion).');
        } else if (!res.isValid) {
            a.RUT__c.addError('RUT inválido');
        }
    }
}