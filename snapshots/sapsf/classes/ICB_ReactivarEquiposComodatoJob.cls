/**
 * Repara las entradas de equipos en las listas de precios que el equipo administra a mano.
 *
 * El problema que resuelve: un proceso externo escribe PricebookEntry por API a las 04:00 con
 * el usuario de integracion y deja apagadas las entradas de la lista COMODATO. El selector de
 * equipos del flujo consulta PricebookEntry --no Product2-- asi que los equipos desaparecen de
 * la pantalla aunque el producto siga activo y visible. El 01/09/2026 quedo 1 maquina de 22.
 *
 * Por que un job y no un trigger: Salesforce no permite triggers en PricebookEntry
 * ("SObject type does not allow triggers"), y el proceso que las apaga no vive en el org, asi
 * que tampoco se puede corregir desde aqui. Reparar despues es la unica defensa disponible.
 *
 * Alcance deliberadamente estrecho: solo reactiva entradas de productos con Tipo_Equipo__c, que
 * son las que sostienen el selector. No toca los insumos, para no revivir lo que el equipo
 * desactivo a proposito al depurar la lista. Si hay que sacar un equipo de la lista, se borra su
 * entrada o se le quita el Tipo_Equipo__c; apagarla no alcanza, porque este job la revive.
 *
 * Programacion (Anonymous Apex, dos corridas para cubrir los dos jobs diarios del org):
 *   System.schedule('Reactivar equipos COMODATO 05:00', '0 0 5 * * ?',
 *                   new ICB_ReactivarEquiposComodatoJob());
 *   System.schedule('Reactivar equipos COMODATO 07:00', '0 0 7 * * ?',
 *                   new ICB_ReactivarEquiposComodatoJob());
 */
public with sharing class ICB_ReactivarEquiposComodatoJob implements Schedulable {

    public void execute(SchedulableContext ctx) {
        reactivar();
    }

    /**
     * Reactiva las entradas apagadas de equipos cuyo producto sigue activo.
     *
     * @return cuantas entradas se reactivaron.
     */
    public static Integer reactivar() {
        List<PricebookEntry> apagadas = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2.Name IN :ICB_ProductoProtegido.LISTAS_PROTEGIDAS
              AND IsActive = false
              AND Product2.IsActive = true
              AND Product2.Tipo_Equipo__c != null
            LIMIT 10000
        ];
        if (apagadas.isEmpty()) {
            return 0;
        }
        // Se arman registros nuevos con Id + IsActive en vez de reusar los consultados:
        // PricebookEntry rechaza el update si el registro trae cargados campos de Product2,
        // que son de solo lectura ("fields being inaccessible on Sobject PricebookEntry").
        List<PricebookEntry> aActualizar = new List<PricebookEntry>();
        for (PricebookEntry e : apagadas) {
            aActualizar.add(new PricebookEntry(Id = e.Id, IsActive = true));
        }
        update aActualizar;
        System.debug(LoggingLevel.INFO,
            'Entradas de equipos reactivadas en listas protegidas: ' + aActualizar.size());
        return aActualizar.size();
    }
}