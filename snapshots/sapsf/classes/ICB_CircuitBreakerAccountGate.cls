/**********************************************************************************
 * ICB_CircuitBreakerAccountGate
 * Gate before-save (before insert/update) sobre Account: replica el criterio de
 * entrada de los flows Record-Triggered protegidos por Circuit Breaker y, si el
 * proceso esta abierto/bloqueado, rechaza el registro completo via addError()
 * ANTES del commit. A diferencia del chequeo dentro de los flows (RecordAfterSave,
 * que ya no puede deshacer un update que ya se guardo), este gate SI evita que el
 * dato quede guardado.
 *
 * Reutiliza ICB_CircuitBreakerService.evaluarLote (mismo Circuit_Breaker__c por
 * proceso, mismo Activo__c/Bypass como kill-switch). Los flows ya no cuentan por
 * su cuenta para estos 3 procesos (se les quito su propio Verificar_CB) para no
 * duplicar el conteo contra el mismo umbral.
 **********************************************************************************/
public without sharing class ICB_CircuitBreakerAccountGate {

    private static final Set<String> CAMPOS_UPDATE_CLIENTE_FULL = new Set<String>{
        'Status_Jur_dico__c', 'Asesor_Asignado__c', 'BillingCity', 'ShippingCity',
        'ShippingPostalCode', 'BillingPostalCode', 'ShippingStreet', 'BillingStreet',
        'Centro_de_Abastecimiento__c', 'Email__c', 'Especialidad__c', 'Gerencia__c',
        'Name', 'Oficina_de_Venta__c', 'ParentId', 'Phone', 'Razon_Social__c', 'RUT__c',
        'Sucursal__c', 'OwnerId', 'Comuna_Despacho__c', 'Comuna_Facturaci_n__c',
        'Region_Despacho__c', 'Region__c', 'Limite_Credito__c', 'Persona_Fisica__c',
        'Auxiliar_Formula_Persona_Fisica__c', 'Datos_de_Contacto_Principal__c',
        'Codigo_Ramo__c', 'condicion_pago__c'
    };

    // Resuelto por DeveloperName (no por Id): el Id de un RecordType es especifico
    // de cada org y nunca es portable entre sandbox y PROD.
    private static final Id RT_SUBFLOW_DOMICILIO_V3 = resolverRecordTypeId('Sucursal');

    private static Id resolverRecordTypeId(String developerName) {
        Map<String, Schema.RecordTypeInfo> infos =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(developerName);
        return info != null ? info.getRecordTypeId() : null;
    }

    public static void evaluarAntesDeGuardar(List<Account> nuevas, Map<Id, Account> viejasMap) {
        // Identidades de integracion exentas: no se cuentan ni se bloquean. Se sale antes
        // de evaluar nada, asi el trafico esperado tampoco consume el contador de ventana
        // ni el lock sobre Circuit_Breaker__c.
        if (ICB_CircuitBreakerService.usuarioTieneBypass()) {
            return;
        }

        List<String> nombresProceso = new List<String>();
        List<Id> registroIds = new List<Id>();
        List<Account> cuentaPorIndice = new List<Account>();

        for (Account nueva : nuevas) {
            Account vieja = (viejasMap != null) ? viejasMap.get(nueva.Id) : null;

            if (vieja != null && coincideUpdateClienteFull(nueva, vieja)) {
                nombresProceso.add('Update_Cliente_Full_Cliente_SAP');
                registroIds.add(nueva.Id);
                cuentaPorIndice.add(nueva);
            }

            if (coincideCrearAsociacion(nueva, vieja)) {
                nombresProceso.add('Crear_Asociacion');
                registroIds.add(vieja != null ? nueva.Id : null);
                cuentaPorIndice.add(nueva);
            }

            if (vieja == null && coincideSubflowDomicilioV3(nueva)) {
                nombresProceso.add('Subflow_Domicilio_adicional_cliente_v3');
                registroIds.add(null);
                cuentaPorIndice.add(nueva);
            }
        }

        if (nombresProceso.isEmpty()) {
            return;
        }

        // Peek: decide con el estado actual pero SIN persistir (si mas abajo se llama
        // addError, esta misma transaccion se revierte completa, incluyendo cualquier
        // DML que hubieramos hecho aqui). El conteo/apertura/notificacion reales se
        // hacen async via Circuit_Breaker_Intento__e, que sobrevive a esa reversion.
        Map<Integer, ICB_CircuitBreakerService.BreakerResultado> resultados =
            ICB_CircuitBreakerService.evaluarLotePeek(nombresProceso, registroIds);

        List<Circuit_Breaker_Intento__e> eventos = new List<Circuit_Breaker_Intento__e>();

        for (Integer i = 0; i < nombresProceso.size(); i++) {
            eventos.add(new Circuit_Breaker_Intento__e(
                Nombre_Proceso__c = nombresProceso[i],
                Registro_Id__c = registroIds[i]
            ));

            ICB_CircuitBreakerService.BreakerResultado r = resultados.get(i);
            if (r != null && r.permitirContinuar != true) {
                cuentaPorIndice[i].addError(
                    'Guardado bloqueado por Control de Flujos SAP (' + nombresProceso[i] + '): ' + r.motivo
                    + '. Revisa/reactiva el proceso en el Panel Control de Flujos SAP si esto no es una carga masiva real.'
                );
            }
        }

        if (!eventos.isEmpty()) {
            EventBus.publish(eventos);
        }
    }

    private static Boolean coincideUpdateClienteFull(Account nueva, Account vieja) {
        for (String campo : CAMPOS_UPDATE_CLIENTE_FULL) {
            if (nueva.get(campo) != vieja.get(campo)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean coincideCrearAsociacion(Account nueva, Account vieja) {
        Id parentNuevo = nueva.ParentId;
        Id parentViejo = (vieja != null) ? vieja.ParentId : null;
        return parentNuevo != parentViejo;
    }

    private static Boolean coincideSubflowDomicilioV3(Account nueva) {
        return nueva.RecordTypeId == RT_SUBFLOW_DOMICILIO_V3
            && nueva.Checkflow__c == true
            && nueva.Cliente_Despacho__c == null;
    }
}