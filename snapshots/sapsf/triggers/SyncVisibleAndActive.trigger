/**
 * Sincroniza Product2.IsActive con Visible_For_Sales__c, EXCEPTO para los productos que
 * pertenecen a las listas de precios protegidas (ver ICB_ProductoProtegido.LISTAS_PROTEGIDAS).
 *
 * Por que la excepcion: los productos de la lista COMODATO los administra el equipo a mano.
 * Sin este resguardo, cualquier actualizacion del producto (integracion, carga masiva, un flujo
 * que toque el registro, o la edicion de otro campo) revertia IsActive al valor de
 * Visible_For_Sales__c y deshacia ese trabajo, dando la impresion de que "se desactivan solos".
 *
 * El calculo de productos protegidos esta en ICB_ProductoProtegido para que sea bulk-safe:
 * una sola consulta por transaccion, nunca dentro del loop.
 */
trigger SyncVisibleAndActive on Product2 (before insert, before update) {

    // En before insert el registro todavia no tiene Id, asi que no puede estar en una lista
    // de precios: solo hay que resolver protegidos en update.
    Set<Id> protegidos = Trigger.isUpdate
        ? ICB_ProductoProtegido.idsEnListasProtegidas(Trigger.newMap.keySet())
        : new Set<Id>();

    for (Product2 p : Trigger.new) {
        // Producto protegido: su IsActive lo decide el equipo, no este trigger.
        if (p.Id != null && protegidos.contains(p.Id)) {
            continue;
        }
        if (p.Visible_For_Sales__c != p.IsActive) {
            p.IsActive = p.Visible_For_Sales__c;
        }
    }
}