/**
 * Tests de ComodatoOverrideResolver.
 *
 * Cada test fija explicitamente bajo que usuario corre (System.runAs), de modo que el
 * resultado NO dependa de si quien ejecuta la suite tiene asignado ADMIN_COMODATO:
 *   - usuarioConPermiso: perfil de la Comodato Admin (Category) + ADMIN_COMODATO.
 *   - usuarioSinPermiso: perfil del asesor comercial, sin el Permission Set.
 * Son los dos tipos de usuario reales que operan Comodato en la organizacion.
 * El Custom Permission lo otorga unicamente ADMIN_COMODATO (ningun perfil lo concede),
 * por eso el usuario sin el Permission Set es un caso "sin permiso" fiable.
 */
@IsTest
private class ComodatoOverrideResolver_Test {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Cuenta Test Comodato');
        insert acc;

        Product2 maquina = new Product2(Name = 'Maquina Test', IsActive = true, Codigo__c = 'MAQ-001');
        Product2 insumo = new Product2(Name = 'Insumo Test', IsActive = true, Codigo__c = 'INS-001');
        insert new List<Product2>{ maquina, insumo };

        Comodato__c comodato = new Comodato__c(
            Maquina__c = maquina.Id,
            Producto_Asociado__c = insumo.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 100,
            Unidad_de_Medida__c = 'Kilos',
            Precio_Unitario_Neto__c = 5000
        );
        insert comodato;

        Opportunity opp = new Opportunity(
            Name = 'OPP Test Comodato',
            AccountId = acc.Id,
            StageName = 'En proceso de Firma',
            CloseDate = Date.today()
        );
        insert opp;

        Quote q = new Quote(Name = 'Quote Test Comodato', OpportunityId = opp.Id);
        insert q;
    }

    private static Comodato__c getComodato() {
        return [SELECT Id, Maquina__c FROM Comodato__c LIMIT 1];
    }

    private static Quote getQuote() {
        return [SELECT Id FROM Quote LIMIT 1];
    }

    @IsTest
    static void resolver_sinOverride_devuelveValoresOriginales() {
        User u = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(u) {
            Test.startTest();
            List<ComodatoOverrideResolver.LineaResuelta> lineas =
                ComodatoOverrideResolver.resolver(new Set<Id>{ c.Maquina__c }, q.Id);
            Test.stopTest();

            System.assertEquals(1, lineas.size(), 'Debe devolver la unica linea Comodato de la maquina.');
            ComodatoOverrideResolver.LineaResuelta linea = lineas[0];
            System.assertEquals(false, linea.tieneAjuste, 'Sin override registrado, no debe marcarse ajuste.');
            System.assertEquals(100, linea.cantidadMinimaMensual);
            System.assertEquals('Kilos', linea.unidadDeMedida);
            System.assertEquals(5000, linea.precioUnitarioNeto);
            System.assertEquals(100, linea.cantidadMinimaMensualOriginal);
            System.assertEquals(false, linea.getCantidadFueAjustada());
        }
    }

    @IsTest
    static void resolver_quoteIdNull_nuncaAplicaOverride() {
        User u = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();

        System.runAs(u) {
            Test.startTest();
            List<ComodatoOverrideResolver.LineaResuelta> lineas =
                ComodatoOverrideResolver.resolver(new Set<Id>{ c.Maquina__c }, null);
            Test.stopTest();

            System.assertEquals(1, lineas.size());
            System.assertEquals(false, lineas[0].tieneAjuste, 'Sin Quote no puede existir override aplicable.');
        }
    }

    @IsTest
    static void resolver_maquinaIdsVacio_devuelveListaVacia() {
        User u = crearUsuarioConPermisoAjuste();
        Id quoteId = getQuote().Id;

        System.runAs(u) {
            Test.startTest();
            List<ComodatoOverrideResolver.LineaResuelta> lineas =
                ComodatoOverrideResolver.resolver(new Set<Id>(), quoteId);
            Test.stopTest();

            System.assertEquals(0, lineas.size());
        }
    }

    @IsTest
    static void resolver_conOverrideActivo_devuelveValoresAjustadosYOriginalIntacto() {
        User u = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(u) {
            insert new Comodato_Override__c(
                Comodato_Original__c = c.Id,
                Quote__c = q.Id,
                Maquina__c = c.Maquina__c,
                Cantidad_Ajustada__c = 250,
                Precio_Unitario_Ajustado__c = 4200,
                Motivo__c = 'Ajuste de prueba por acuerdo comercial excepcional.',
                Ajustado_Por__c = UserInfo.getUserId(),
                Fecha_Ajuste__c = Datetime.now(),
                Activo__c = true
            );

            Test.startTest();
            List<ComodatoOverrideResolver.LineaResuelta> lineas =
                ComodatoOverrideResolver.resolver(new Set<Id>{ c.Maquina__c }, q.Id);
            Test.stopTest();

            System.assertEquals(1, lineas.size());
            ComodatoOverrideResolver.LineaResuelta linea = lineas[0];
            System.assertEquals(true, linea.tieneAjuste);
            System.assertEquals(250, linea.cantidadMinimaMensual, 'Valor efectivo debe reflejar el ajuste.');
            System.assertEquals(4200, linea.precioUnitarioNeto);
            System.assertEquals('Kilos', linea.unidadDeMedida, 'Unidad no ajustada debe mantener el original.');
            System.assertEquals(100, linea.cantidadMinimaMensualOriginal, 'El original de Comodato__c nunca cambia.');
            System.assertEquals(5000, linea.precioUnitarioNetoOriginal);
            System.assertEquals(true, linea.getCantidadFueAjustada());
            System.assertEquals(true, linea.getPrecioFueAjustado());
            System.assertEquals(false, linea.getUnidadFueAjustada());

            Comodato__c comodatoDespues = [SELECT Cantidad_Minima_Mensual__c, Precio_Unitario_Neto__c FROM Comodato__c WHERE Id = :c.Id];
            System.assertEquals(100, comodatoDespues.Cantidad_Minima_Mensual__c, 'Comodato__c maestro nunca debe modificarse.');
            System.assertEquals(5000, comodatoDespues.Precio_Unitario_Neto__c);
        }
    }

    @IsTest
    static void registrarAjuste_sinPermiso_lanzaExcepcion() {
        User u = crearUsuarioSinPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(u) {
            Test.startTest();
            try {
                ComodatoOverrideResolver.registrarAjuste(c.Id, q.Id, 200, 'Kilos', 4500, 'Motivo de prueba');
                System.assert(false, 'Debe lanzar excepcion cuando el usuario no tiene el Custom Permission.');
            } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
                System.assert(e.getMessage().contains('permiso'), 'El mensaje debe indicar falta de permiso.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void revertirAjuste_sinPermiso_lanzaExcepcion() {
        User u = crearUsuarioSinPermisoAjuste();

        System.runAs(u) {
            Test.startTest();
            try {
                ComodatoOverrideResolver.revertirAjuste(idInexistenteDeOverride());
                System.assert(false, 'Debe lanzar excepcion cuando el usuario no tiene el Custom Permission.');
            } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
                System.assert(e.getMessage().contains('permiso'));
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void revertirAjuste_idNull_noHaceNada() {
        // Sin permiso tambien lanza excepcion antes de llegar al check de null; se documenta
        // la precedencia (permiso siempre se valida primero) y se cubre el guard de permiso.
        User u = crearUsuarioSinPermisoAjuste();

        System.runAs(u) {
            Test.startTest();
            try {
                ComodatoOverrideResolver.revertirAjuste(null);
                System.assert(false, 'Debe lanzar excepcion de permiso antes de evaluar el id null.');
            } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
                System.assert(e.getMessage().contains('permiso'));
            }
            Test.stopTest();
        }
    }

    /**
     * Corre las validaciones de registrarAjuste() que solo se alcanzan CON el permiso
     * concedido (al menos un valor a ajustar, reemplazo del override
     * previo activo). Requiere que el Custom Permission Ajustar_Valores_Comodato este
     * incluido en el Permission Set ADMIN_COMODATO -- si el nombre o alcance de ese
     * Permission Set cambia, este test debe actualizarse junto con el metadata.
     */
    @IsTest
    static void registrarAjuste_conPermiso_validaCambiosYReemplazaOverridePrevio() {
        User usuarioConPermiso = crearUsuarioConPermisoAjuste();
        Comodato__c c = getComodato();
        Quote q = getQuote();

        System.runAs(usuarioConPermiso) {
            Test.startTest();

            // El motivo es opcional (decision de negocio 2026-08-25): un ajuste sin motivo
            // debe guardarse igual. Si vuelve a exigirse, este bloque cambia a esperar excepcion.
            Id sinMotivo = ComodatoOverrideResolver.registrarAjuste(c.Id, q.Id, 200, 'Kilos', 4500, '');
            System.assertNotEquals(null, sinMotivo, 'Sin motivo el ajuste igual debe registrarse.');

            try {
                ComodatoOverrideResolver.registrarAjuste(c.Id, q.Id, null, null, null, 'Motivo valido pero sin cambios.');
                System.assert(false, 'Sin ningun valor a ajustar debe ser rechazado.');
            } catch (ComodatoOverrideResolver.ComodatoOverrideException e) {
                System.assert(e.getMessage().contains('ajustar'), 'Debe exigir al menos un valor ajustado.');
            }

            Id primerOverrideId = ComodatoOverrideResolver.registrarAjuste(
                c.Id, q.Id, 200, null, null, 'Primer ajuste de prueba, cliente solicito reduccion.'
            );
            System.assertNotEquals(null, primerOverrideId);

            Id segundoOverrideId = ComodatoOverrideResolver.registrarAjuste(
                c.Id, q.Id, 300, null, null, 'Correccion del ajuste anterior, nuevo acuerdo.'
            );
            System.assertNotEquals(primerOverrideId, segundoOverrideId, 'Un nuevo ajuste debe crear un registro nuevo.');

            Comodato_Override__c anterior = [SELECT Activo__c FROM Comodato_Override__c WHERE Id = :primerOverrideId];
            System.assertEquals(false, anterior.Activo__c, 'El override reemplazado debe quedar desactivado, no borrado.');

            Comodato_Override__c actual = [SELECT Activo__c, Cantidad_Ajustada__c FROM Comodato_Override__c WHERE Id = :segundoOverrideId];
            System.assertEquals(true, actual.Activo__c);
            System.assertEquals(300, actual.Cantidad_Ajustada__c);

            ComodatoOverrideResolver.revertirAjuste(segundoOverrideId);
            Comodato_Override__c revertido = [SELECT Activo__c FROM Comodato_Override__c WHERE Id = :segundoOverrideId];
            System.assertEquals(false, revertido.Activo__c, 'Revertir debe desactivar, no borrar, el override.');

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

    /**
     * Crea un usuario de test y le asigna el Permission Set ADMIN_COMODATO, que otorga el
     * Custom Permission Ajustar_Valores_Comodato. Si ADMIN_COMODATO deja de otorgar ese
     * Custom Permission, este helper (y los tests que lo usan) deben actualizarse.
     */
    private static User crearUsuarioConPermisoAjuste() {
        // Perfil de la Comodato Admin real (Cynthia Perez) + el Permission Set.
        User u = crearUsuario('tajcmd', PERFILES_COMODATO_ADMIN);
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ADMIN_COMODATO' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    /** Perfil del asesor comercial real (Karen Carrasco), SIN ADMIN_COMODATO. */
    private static User crearUsuarioSinPermisoAjuste() {
        return crearUsuario('tsjcmd', PERFILES_ASESOR);
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
            LastName = 'AjusteComodato',
            Alias = alias,
            Email = 'test.ajuste.comodato@icbfs.test.invalid',
            Username = 'test.ajuste.comodato.' + alias + '.' + Crypto.getRandomInteger() + '@icbfs.test.invalid',
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