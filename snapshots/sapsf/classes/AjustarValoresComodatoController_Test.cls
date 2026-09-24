@IsTest
private class AjustarValoresComodatoController_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Cuenta Test Ajuste Controller');
        insert acc;

        Product2 maquina = new Product2(Name = 'Maquina Test Controller', IsActive = true, Codigo__c = 'MAQ-002');
        Product2 insumo = new Product2(Name = 'Insumo Test Controller', IsActive = true, Codigo__c = 'INS-002');
        insert new List<Product2>{ maquina, insumo };

        insert new Comodato__c(
            Maquina__c = maquina.Id,
            Producto_Asociado__c = insumo.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 80,
            Unidad_de_Medida__c = 'Cajas',
            Precio_Unitario_Neto__c = 3000
        );

        Opportunity opp = new Opportunity(
            Name = 'OPP Test Ajuste Controller',
            AccountId = acc.Id,
            StageName = 'En proceso de Firma',
            CloseDate = Date.today()
        );
        insert opp;

        insert new Quote(Name = 'Quote Test Ajuste Controller', OpportunityId = opp.Id);
    }

    private static Comodato__c getComodato() {
        return [SELECT Id, Maquina__c FROM Comodato__c LIMIT 1];
    }

    private static Quote getQuote() {
        return [SELECT Id FROM Quote LIMIT 1];
    }

    @IsTest
    static void obtenerLineasParaAjuste_devuelveSoloLineasConProductoAsociado() {
        User u = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(u) {
            Test.startTest();
            List<AjustarValoresComodatoController.LineaAjusteDto> lineas =
                AjustarValoresComodatoController.obtenerLineasParaAjuste(new List<Id>{ c.Maquina__c }, q.Id);
            Test.stopTest();

            System.assertEquals(1, lineas.size());
            AjustarValoresComodatoController.LineaAjusteDto dto = lineas[0];
            System.assertEquals(c.Id, dto.comodatoId);
            System.assertEquals(80, dto.cantidadOriginal);
            System.assertEquals('Cajas', dto.unidadOriginal);
            System.assertEquals(3000, dto.precioOriginal);
            System.assertEquals(80, dto.cantidadEfectiva, 'Sin ajuste, lo efectivo debe igualar lo original.');
            System.assertEquals(false, dto.tieneAjuste);
        }
    }

    @IsTest
    static void obtenerLineasParaAjuste_maquinaIdsVacio_devuelveListaVacia() {
        User u = crearUsuarioConPermisoAjuste();
        Id quoteId = getQuote().Id;

        System.runAs(u) {
            Test.startTest();
            List<AjustarValoresComodatoController.LineaAjusteDto> lineas =
                AjustarValoresComodatoController.obtenerLineasParaAjuste(new List<Id>(), quoteId);
            Test.stopTest();

            System.assertEquals(0, lineas.size());
        }
    }

    @IsTest
    static void obtenerLineasParaAjuste_quoteIdNull_devuelveValoresOriginalesSinAjuste() {
        User u = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();

        System.runAs(u) {
            Test.startTest();
            List<AjustarValoresComodatoController.LineaAjusteDto> lineas =
                AjustarValoresComodatoController.obtenerLineasParaAjuste(new List<Id>{ c.Maquina__c }, null);
            Test.stopTest();

            System.assertEquals(1, lineas.size());
            System.assertEquals(false, lineas[0].tieneAjuste);
        }
    }

    @IsTest
    static void guardarAjuste_sinPermiso_lanzaAuraHandledException() {
        User u = crearUsuarioSinPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(u) {
            Test.startTest();
            try {
                AjustarValoresComodatoController.guardarAjuste(c.Id, q.Id, 150, 'Cajas', 3500, 'Motivo de prueba controller');
                System.assert(false, 'Debe lanzar excepcion cuando el usuario no tiene el Custom Permission.');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void revertirAjuste_sinPermiso_lanzaAuraHandledException() {
        User u = crearUsuarioSinPermisoAjuste();

        System.runAs(u) {
            Test.startTest();
            try {
                AjustarValoresComodatoController.revertirAjuste(idInexistenteDeOverride());
                System.assert(false, 'Debe lanzar excepcion cuando el usuario no tiene el Custom Permission.');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void puedeAjustarValores_sinPermiso_devuelveFalse() {
        User u = crearUsuarioSinPermisoAjuste();

        System.runAs(u) {
            Test.startTest();
            Boolean puede = AjustarValoresComodatoController.puedeAjustarValores();
            Test.stopTest();

            System.assertEquals(false, puede, 'Un asesor sin ADMIN_COMODATO no debe poder ajustar valores.');
        }
    }

    /**
     * Cubre el camino feliz de guardarAjuste()/puedeAjustarValores() con el permiso concedido
     * via el Permission Set ADMIN_COMODATO. Si ese Permission Set deja de otorgar el Custom
     * Permission Ajustar_Valores_Comodato, este test debe actualizarse junto con el metadata.
     */
    @IsTest
    static void guardarAjuste_conPermiso_creaOverrideYQuedaVisibleEnPuedeAjustarValores() {
        User usuarioConPermiso = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(usuarioConPermiso) {
            Test.startTest();

            Boolean puede = AjustarValoresComodatoController.puedeAjustarValores();
            System.assertEquals(true, puede);

            Id overrideId = AjustarValoresComodatoController.guardarAjuste(
                c.Id, q.Id, 150, 'Cajas', 3500, 'Ajuste de prueba desde el controller.'
            );
            System.assertNotEquals(null, overrideId);

            List<AjustarValoresComodatoController.LineaAjusteDto> lineas =
                AjustarValoresComodatoController.obtenerLineasParaAjuste(new List<Id>{ c.Maquina__c }, q.Id);
            System.assertEquals(1, lineas.size());
            System.assertEquals(true, lineas[0].tieneAjuste);
            System.assertEquals(150, lineas[0].cantidadEfectiva);
            System.assertEquals(80, lineas[0].cantidadOriginal, 'El original nunca cambia aunque exista un ajuste.');

            AjustarValoresComodatoController.revertirAjuste(overrideId);

            List<AjustarValoresComodatoController.LineaAjusteDto> lineasDespues =
                AjustarValoresComodatoController.obtenerLineasParaAjuste(new List<Id>{ c.Maquina__c }, q.Id);
            System.assertEquals(false, lineasDespues[0].tieneAjuste, 'Tras revertir, debe volver al valor original.');

            Test.stopTest();
        }
    }

    /**
     * Id sintacticamente valido de Comodato_Override__c que no corresponde a ningun registro.
     * Se deriva del key prefix real del objeto: un Id de otro sObject (ej. el prefijo 001 de
     * Account) provoca System.TypeException antes de llegar a la validacion de permiso.
     */
    private static Id idInexistenteDeOverride() {
        return Id.valueOf(Comodato_Override__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
    }

    /** Perfil de la Comodato Admin real (Cynthia Perez) + el Permission Set. */
    private static User crearUsuarioConPermisoAjuste() {
        User u = crearUsuario('tajctl', PERFILES_COMODATO_ADMIN);
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ADMIN_COMODATO' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    /** Perfil del asesor comercial real (Karen Carrasco), SIN ADMIN_COMODATO. */
    private static User crearUsuarioSinPermisoAjuste() {
        return crearUsuario('tsjctl', PERFILES_ASESOR);
    }

    private static final List<String> PERFILES_COMODATO_ADMIN = new List<String>{ 'Category' };
    private static final List<String> PERFILES_ASESOR = new List<String>{ 'Asesor comercial' };
    private static final List<String> PERFILES_FALLBACK = new List<String>{ 'Standard User', 'Usuario estándar' };

    /**
     * Resuelve el perfil objetivo; si esa org no lo tiene, cae al perfil estandar para que
     * la suite siga corriendo (el Custom Permission no lo concede ningun perfil, solo
     * ADMIN_COMODATO, asi que el caso "sin permiso" se mantiene valido igual).
     */
    private static Profile resolverPerfil(List<String> nombres) {
        List<Profile> ps = [SELECT Id FROM Profile WHERE Name IN :nombres LIMIT 1];
        if (ps.isEmpty()) {
            ps = [SELECT Id FROM Profile WHERE Name IN :PERFILES_FALLBACK LIMIT 1];
        }
        return ps[0];
    }

    private static User crearUsuario(String alias, List<String> nombresPerfil) {
        Profile p = resolverPerfil(nombresPerfil);
        User u = new User(
            FirstName = 'Test',
            LastName = 'AjusteController',
            Alias = alias,
            Email = 'test.ajuste.controller@icbfs.test.invalid',
            Username = 'test.ajuste.controller.' + alias + '.' + Crypto.getRandomInteger() + '@icbfs.test.invalid',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Santiago',
            LocaleSidKey = 'es_CL',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es'
        );
        insert u;
        return u;
    }
}