trigger seidor_FechaRetiroTrigger on Case (before insert, before update) {

    if (Trigger.isBefore) {
        seidor_FechaRetiroValidator.validar(Trigger.new, Trigger.oldMap);
    }

}