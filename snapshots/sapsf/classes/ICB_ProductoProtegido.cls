/**
 * Punto unico para saber si un Product2 esta protegido contra la sincronizacion automatica
 * de IsActive.
 *
 * Un producto esta protegido cuando pertenece a alguna de las listas de precios que el equipo
 * administra a mano (LISTAS_PROTEGIDAS). Para esos productos, IsActive es una decision del
 * negocio y ningun proceso automatico debe reescribirlo.
 *
 * Se resuelve por NOMBRE de lista y no por Id para que funcione igual en cualquier org
 * (sandbox, UAT, produccion), donde los Ids difieren.
 */
public with sharing class ICB_ProductoProtegido {

    /** Listas de precios cuyos productos no deben ser tocados por automatismos. */
    public static final Set<String> LISTAS_PROTEGIDAS = new Set<String>{ 'COMODATO' };

    /**
     * De los Ids recibidos, devuelve los que pertenecen a una lista de precios protegida.
     *
     * Una sola consulta por invocacion: pensado para llamarse una vez por transaccion desde
     * un trigger, nunca dentro de un loop.
     */
    public static Set<Id> idsEnListasProtegidas(Set<Id> productoIds) {
        Set<Id> protegidos = new Set<Id>();
        if (productoIds == null || productoIds.isEmpty()) {
            return protegidos;
        }
        for (PricebookEntry pbe : [
            SELECT Product2Id
            FROM PricebookEntry
            WHERE Product2Id IN :productoIds
              AND Pricebook2.Name IN :LISTAS_PROTEGIDAS
        ]) {
            protegidos.add(pbe.Product2Id);
        }
        return protegidos;
    }

    /** Conveniencia para un solo producto. Evitar en contextos masivos. */
    public static Boolean estaProtegido(Id productoId) {
        return productoId != null
            && !idsEnListasProtegidas(new Set<Id>{ productoId }).isEmpty();
    }
}