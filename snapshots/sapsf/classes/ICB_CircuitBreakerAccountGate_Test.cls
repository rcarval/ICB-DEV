@IsTest
public class ICB_CircuitBreakerAccountGate_Test {

    private static Circuit_Breaker__c crearBreakerAbierto(String nombreProceso) {
        Circuit_Breaker__c cb = new Circuit_Breaker__c(
            Name = nombreProceso.left(80),
            Nombre_Proceso__c = nombreProceso,
            Activo__c = true,
            Umbral_Intentos__c = 20,
            Ventana_Segundos__c = 1,
            Enfriamiento_Minutos__c = 15,
            Estado__c = 'Abierto',
            Fecha_Apertura__c = Datetime.now(),
            Destinatarios_Correo__c = 'test@icbfs.cl'
        );
        insert cb;
        return cb;
    }

    @IsTest
    static void testCampoNoRelevanteNoEvaluaNiBloquea() {
        // Ningun proceso protegido escucha Description: el gate no debe evaluar nada.
        crearBreakerAbierto('Update_Cliente_Full_Cliente_SAP');

        Account acc = new Account(Name = 'Cuenta Gate Irrelevante');
        insert acc;

        Test.startTest();
        acc.Description = 'cambio que no le importa a ningun proceso protegido';
        update acc;
        Test.stopTest();

        Account actualizada = [SELECT Description FROM Account WHERE Id = :acc.Id];
        System.assertEquals('cambio que no le importa a ningun proceso protegido', actualizada.Description);
    }

    @IsTest
    static void testBloqueaUpdateClienteFullSiBreakerAbierto() {
        crearBreakerAbierto('Update_Cliente_Full_Cliente_SAP');

        Account acc = new Account(Name = 'Cuenta Gate Update Cliente Full');
        insert acc;

        Test.startTest();
        acc.Sucursal__c = 'S001 - Suc Santiago';
        Boolean lanzoExcepcion = false;
        try {
            update acc;
        } catch (DmlException e) {
            lanzoExcepcion = true;
            System.assert(
                e.getMessage().contains('Control de Flujos SAP'),
                'El mensaje de error debe indicar que fue el Control de Flujos SAP quien bloqueo: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, lanzoExcepcion,
            'Un cambio de Sucursal__c con el breaker de Update_Cliente_Full_Cliente_SAP abierto debe rechazar el guardado completo');
    }

    @IsTest
    static void testBloqueaCrearAsociacionPorParentIdEnInsercionSiBreakerAbierto() {
        crearBreakerAbierto('Crear_Asociacion');

        Account padre = new Account(Name = 'Cuenta Padre Gate');
        insert padre;

        Account hijo = new Account(Name = 'Cuenta Hijo Gate', ParentId = padre.Id);

        Test.startTest();
        Boolean lanzoExcepcion = false;
        try {
            insert hijo;
        } catch (DmlException e) {
            lanzoExcepcion = true;
            System.assert(
                e.getMessage().contains('Crear_Asociacion'),
                'El mensaje de error debe indicar que fue Crear_Asociacion quien bloqueo: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, lanzoExcepcion,
            'Insertar una cuenta con ParentId con el breaker de Crear_Asociacion abierto debe rechazar el guardado completo');
    }

    @IsTest
    static void testBloqueaSubflowDomicilioV3EnCreacionSiBreakerAbierto() {
        crearBreakerAbierto('Subflow_Domicilio_adicional_cliente_v3');

        Map<String, Schema.RecordTypeInfo> infos =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo infoSucursal = infos.get('Sucursal');

        if (infoSucursal == null) {
            // Si este RecordType no existe en el org donde corre el test, no hay nada que
            // este criterio pueda coincidir; se evita un falso negativo por ambiente.
            return;
        }

        Account acc = new Account(
            Name = 'Cuenta Gate Subflow Domicilio v3',
            RecordTypeId = infoSucursal.getRecordTypeId(),
            Checkflow__c = true
        );

        Test.startTest();
        Boolean lanzoExcepcion = false;
        try {
            insert acc;
        } catch (DmlException e) {
            lanzoExcepcion = true;
            System.assert(
                e.getMessage().contains('Subflow_Domicilio_adicional_cliente_v3'),
                'El mensaje de error debe indicar que fue Subflow_Domicilio_adicional_cliente_v3 quien bloqueo: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, lanzoExcepcion,
            'Crear una cuenta Sucursal sin Cliente_Despacho__c con Checkflow__c=true y el breaker abierto debe rechazar el guardado');
    }

    @IsTest
    static void testBypassDeIntegracionNoBloqueaElGuardado() {
        // Breaker ABIERTO: sin bypass, tocar un campo vigilado hace fallar el update.
        crearBreakerAbierto('Update_Cliente_Full_Cliente_SAP');

        Account acc = new Account(Name = 'Cuenta Bypass Integracion');
        insert acc;

        ICB_CircuitBreakerService.bypassUsuarioForzado = true;
        try {
            Test.startTest();
            acc.Phone = '+56900000000';   // campo vigilado por el proceso
            update acc;                   // con bypass esto debe pasar igual
            Test.stopTest();
        } finally {
            ICB_CircuitBreakerService.bypassUsuarioForzado = null;
        }

        Account actualizada = [SELECT Phone FROM Account WHERE Id = :acc.Id];
        System.assertEquals('+56900000000', actualizada.Phone,
            'Con Bypass_Control_Flujos_SAP el gate no debe bloquear aunque el breaker este abierto');
    }

}