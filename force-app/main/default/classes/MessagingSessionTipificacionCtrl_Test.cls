/**
 * @description Test class para MessagingSessionTipificacionCtrl
 *
 * ─── LIMITACIONES TÉCNICAS DOCUMENTADAS ──────────────────────────────────────
 *
 * 1. MessagingSession y MessagingEndUser son special objects de Service Cloud.
 *    No son insertables via DML en test context sin un Messaging Channel configurado.
 *    → Los tests de validación (que disparan ANTES del SOQL) usan cualquier Id
 *      no-null válido y no requieren DML.
 *    → El happy path del update real requiere @isTest(SeeAllData=true).
 *      Alternativa limpia: refactorizar saveTipificacion con un @TestVisible selector.
 *
 * 2. Schema.describe sobre Sub_tipificacion__c no es mockeable en Apex puro.
 *    Los tests de getDependentPicklists asumen que el campo existe en el org.
 *
 * 3. El test FLS usa System.runAs con un perfil Read Only. Si falla el guard
 *    readOnlyProfiles.isEmpty(), ajusta el LIKE con los nombres de perfil de tu org.
 */
@isTest
private class MessagingSessionTipificacionCtrl_Test {

    // =========================================================================
    // getDependentPicklists
    // =========================================================================

    @isTest
    static void getDependentPicklists_debeRetornarAmbasClavesPrincipales() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        Assert.isNotNull(result, 'El resultado no debe ser null');
        Assert.isTrue(result.containsKey('controllerOptions'),
            'Debe contener la clave controllerOptions');
        Assert.isTrue(result.containsKey('dependentMap'),
            'Debe contener la clave dependentMap');
    }

    @isTest
    static void getDependentPicklists_controllerOptionDebeSerConsultaYReclamo() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        List<Object> opts = (List<Object>) result.get('controllerOptions');
        Assert.areEqual(2, opts.size(),
            'Deben existir exactamente 2 opciones controladoras');

        Map<String, String> consulta = (Map<String, String>) opts[0];
        Map<String, String> reclamo  = (Map<String, String>) opts[1];

        Assert.areEqual('Consultas', consulta.get('value'), 'Primera opción value debe ser Consulta');
        Assert.areEqual('Consultas', consulta.get('label'), 'Primera opción label debe ser Consulta');
        Assert.areEqual('Reclamos',  reclamo.get('value'),  'Segunda opción value debe ser Reclamo');
        Assert.areEqual('Reclamos',  reclamo.get('label'),  'Segunda opción label debe ser Reclamo');
    }

    @isTest
    static void getDependentPicklists_dependentMapDebeTenerClavesConsultaYReclamo() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        Map<String, Object> depMap = (Map<String, Object>) result.get('dependentMap');
        Assert.isNotNull(depMap, 'dependentMap no debe ser null');
        Assert.isTrue(depMap.containsKey('Consultas'), 'dependentMap debe tener clave Consulta');
        Assert.isTrue(depMap.containsKey('Reclamos'),  'dependentMap debe tener clave Reclamo');
    }

    @isTest
    static void getDependentPicklists_opcionesDeConsultaYReclamoDebenSerListas() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        Map<String, Object> depMap = (Map<String, Object>) result.get('dependentMap');
        Assert.isNotNull((List<Object>) depMap.get('Consultas'), 'Lista Consulta no debe ser null');
        Assert.isNotNull((List<Object>) depMap.get('Reclamos'),  'Lista Reclamo no debe ser null');
    }

    @isTest
    static void getDependentPicklists_cadaEntradaDebeContenerLabelYValue() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        Map<String, Object> depMap = (Map<String, Object>) result.get('dependentMap');

        for (String key : new List<String>{ 'Consultas', 'Reclamos' }) {
            List<Object> opts = (List<Object>) depMap.get(key);
            for (Object item : opts) {
                Map<String, String> entry = (Map<String, String>) item;
                Assert.isTrue(entry.containsKey('label'),
                    key + ': cada entrada debe tener clave label');
                Assert.isTrue(entry.containsKey('value'),
                    key + ': cada entrada debe tener clave value');
                Assert.isNotNull(entry.get('label'),  key + ': label no debe ser null');
                Assert.isNotNull(entry.get('value'),  key + ': value no debe ser null');
            }
        }
    }

    @isTest
    static void getDependentPicklists_ningunaOpcionDeConsultaDebeEstarEnReclamo() {
        Test.startTest();
        Map<String, Object> result = MessagingSessionTipificacionCtrl.getDependentPicklists();
        Test.stopTest();

        Map<String, Object> depMap  = (Map<String, Object>) result.get('dependentMap');
        List<Object> consultaOpts   = (List<Object>) depMap.get('Consultas');
        List<Object> reclamoOpts    = (List<Object>) depMap.get('Reclamos');

        Set<String> SOLO_CONSULTA = new Set<String>{
            'Pedido (ingreso, modificación)',
            'Estado de pedido / Despacho',
            'Productos y Stock (info, disponibilidad)',
            'Precios / Cotización',
            'Pagos (confirmación, estado de cuenta)',
            'Datos de cliente (creación, actualización, vendedor)',
            'Tiendas / Contacto comercial',
            'Café / Comodato (solicitud, mantención)'
        };
        Set<String> SOLO_RECLAMO = new Set<String>{
            'Producto en mal estado / Devolución',
            'Problema con despacho (atraso, faltantes, no entrega)',
            'Problema con pedido (error, bloqueo, no ingreso)',
            'Problema con pago (cobro incorrecto, no aplicado)',
            'Documentos (nota de crédito, refacturación)',
            'Problema con plataforma (autoenrolamiento, acceso)'
        };

        for (Object item : reclamoOpts) {
            Map<String, String> entry = (Map<String, String>) item;
            Assert.isFalse(SOLO_CONSULTA.contains(entry.get('label')),
                '"' + entry.get('label') + '" es exclusiva de Consulta y no debe estar en Reclamo');
        }
        for (Object item : consultaOpts) {
            Map<String, String> entry = (Map<String, String>) item;
            Assert.isFalse(SOLO_RECLAMO.contains(entry.get('label')),
                '"' + entry.get('label') + '" es exclusiva de Reclamo y no debe estar en Consulta');
        }
    }

    // =========================================================================
    // saveTipificacion – Validaciones básicas ANTES del SOQL
    // Estas excepciones disparan antes de cualquier SOQL/DML.
    // UserInfo.getUserId() se usa como Id no-null válido; nunca llega al query.
    // =========================================================================

    @isTest
    static void saveTipificacion_sessionIdNull_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                null, 'Consultas', 'Pedido', null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        // AuraHandledException.getMessage() siempre retorna "Script-thrown exception"
        // en test context — no es posible verificar el texto del mensaje.
        Assert.isNotNull(capturada,
            'Debe arrojar AuraHandledException cuando sessionId es null');
    }

    @isTest
    static void saveTipificacion_tipificacionBlank_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), '', 'Pedido', null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            'Debe arrojar AuraHandledException cuando tipificacion está en blanco');
    }

    @isTest
    static void saveTipificacion_subTipificacionBlank_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), 'Consultas', '', null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            'Debe arrojar AuraHandledException cuando subTipificacion está en blanco');
    }

    @isTest
    static void saveTipificacion_ambosCamposBlank_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), '', '', null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            'Debe arrojar AuraHandledException con ambos campos en blanco');
    }

    @isTest
    static void saveTipificacion_subTipOtrosSinComentario_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), 'Consultas', 'Otros', '');
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            'Debe arrojar AuraHandledException cuando subTip = Otros y comentario vacío');
    }

    // =========================================================================
    // esOtros – Edge cases (case-insensitive + whitespace)
    // =========================================================================

    @isTest
    static void saveTipificacion_subTipOtrosCaseInsensitive_debeArrojarExcepcion() {
        for (String variante : new List<String>{ 'OTROS', 'otros', 'oTrOs', 'Otros' }) {
            AuraHandledException capturada;
            try {
                MessagingSessionTipificacionCtrl.saveTipificacion(
                    UserInfo.getUserId(), 'Consultas', variante, null);
            } catch (AuraHandledException e) {
                capturada = e;
            }
            Assert.isNotNull(capturada,
                'Debe arrojar excepción para la variante: ' + variante);
        }
    }

    @isTest
    static void saveTipificacion_subTipOtrosConEspaciosPadding_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), 'Consultas', '  Otros  ', null);
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            '"  Otros  " con espacios debe considerarse Otros y requerir comentario');
    }

    @isTest
    static void saveTipificacion_subTipOtrosConSoloEspacios_debeArrojarExcepcion() {
        AuraHandledException capturada;
        try {
            Test.startTest();
            MessagingSessionTipificacionCtrl.saveTipificacion(
                UserInfo.getUserId(), 'Reclamos', 'Otros', '   ');
            Test.stopTest();
        } catch (AuraHandledException e) {
            capturada = e;
        }
        Assert.isNotNull(capturada,
            'Espacios en blanco no son aceptados como comentario cuando Otros');
    }

    // =========================================================================
    // saveTipificacion – Validación FLS
    //
    // Usa System.runAs con un perfil de solo lectura para forzar isUpdateable()=false.
    // Si el test se omite, ejecuta: SELECT Name FROM Profile LIMIT 20
    // y ajusta el filtro LIKE con el nombre de perfil correcto de tu org.
    // =========================================================================

    @isTest
    static void saveTipificacion_sinPermisosFLS_debeArrojarExcepcionDePermisos() {
        List<Profile> readOnlyProfiles = [
            SELECT Id
            FROM   Profile
            WHERE  Name LIKE '%Read Only%'
               OR  Name LIKE '%Minimum Access%'
               OR  Name LIKE '%Solo lectura%'
            LIMIT  1
        ];
        if (readOnlyProfiles.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no se encontró perfil Read Only en el org. ' +
                'Ajusta el filtro LIKE con el nombre correcto de tu org.');
            return;
        }

        User restrictedUser = new User(
            LastName          = 'TestFLS',
            FirstName         = 'Usuario',
            Alias             = 'tstfls',
            Email             = 'test.fls.tipificacion@example.test.com',
            Username          = 'test.fls.tipificacion.' + System.now().getTime() + '@example.test.com',
            ProfileId         = readOnlyProfiles[0].Id,
            TimeZoneSidKey    = 'America/Santiago',
            LocaleSidKey      = 'es_CL',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'es'
        );
        insert restrictedUser;

        AuraHandledException capturada;
        System.runAs(restrictedUser) {
            try {
                Test.startTest();
                MessagingSessionTipificacionCtrl.saveTipificacion(
                    UserInfo.getUserId(), 'Consultas', 'Pedido', null);
                Test.stopTest();
            } catch (AuraHandledException e) {
                capturada = e;
            }
        }

        Assert.isNotNull(capturada,
            'Un usuario Read Only debe recibir AuraHandledException por FLS');
    }

    // =========================================================================
    // saveTipificacion – Happy path + actualizarEsperandoEncuesta
    //
    // @isTest(SeeAllData=true) es necesario porque MessagingSession no es
    // insertable via DML sin un MessagingChannel activo en el org.
    // Cada test hace return silencioso si no hay datos, sin fallar.
    // =========================================================================

    @isTest(SeeAllData=true)
    static void saveTipificacion_conSubTipNoOtros_debeGuardarSinComentario() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay MessagingSession en el org.');
            return;
        }

        Id sessionId = sessions[0].Id;

        Test.startTest();
        MessagingSessionTipificacionCtrl.saveTipificacion(
            sessionId, 'Consultas', 'Pedido (ingreso, modificación)', null);
        Test.stopTest();

        MessagingSession updated = [
            SELECT Tipificacion__c, Sub_tipificacion__c, Comentario__c,
                   Tipificada__c
            FROM   MessagingSession
            WHERE  Id = :sessionId
        ];
        Assert.areEqual('Consultas', updated.Tipificacion__c,
            'Tipificacion__c debe ser "Consulta"');
        Assert.areEqual('Pedido (ingreso, modificación)', updated.Sub_tipificacion__c,
            'Sub_tipificacion__c debe coincidir');
        Assert.isNull(updated.Comentario__c,
            'Comentario__c debe ser null cuando subTipificacion no es Otros');
        Assert.isTrue(updated.Tipificada__c,
            'Tipificada__c debe ser true tras guardar');
    }

    @isTest(SeeAllData=true)
    static void saveTipificacion_conSubTipOtrosYComentario_debeGuardarConComentario() {
        List<MessagingSession> sessions = [
            SELECT Id FROM MessagingSession LIMIT 1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEST OMITIDO: no hay MessagingSession en el org.');
            return;
        }

        Id     sessionId  = sessions[0].Id;
        String comentario = 'Motivo específico no listado en las opciones';

        Test.startTest();
        MessagingSessionTipificacionCtrl.saveTipificacion(
            sessionId, 'Reclamos', 'Otros', comentario);
        Test.stopTest();

        MessagingSession updated = [
            SELECT Tipificacion__c, Sub_tipificacion__c, Comentario__c, Tipificada__c
            FROM   MessagingSession
            WHERE  Id = :sessionId
        ];
        Assert.areEqual('Reclamos', updated.Tipificacion__c,
            'Tipificacion__c debe ser "Reclamo"');
        Assert.areEqual('Otros', updated.Sub_tipificacion__c,
            'Sub_tipificacion__c debe ser "Otros"');
        Assert.areEqual(comentario, updated.Comentario__c,
            'Comentario__c debe persistir cuando subTipificacion es Otros');
        Assert.isTrue(updated.Tipificada__c, 'Tipificada__c debe ser true');
    }

    @isTest(SeeAllData=true)
    static void saveTipificacion_conEndUserId_debeActualizarEsperandoEncuesta() {
        // Cubre actualizarEsperandoEncuesta con un MessagingEndUserId real
        List<MessagingSession> sessions = [
            SELECT Id, MessagingEndUserId
            FROM   MessagingSession
            WHERE  MessagingEndUserId != null
            LIMIT  1
        ];
        if (sessions.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'TEST OMITIDO: no hay MessagingSession con MessagingEndUser asociado.');
            return;
        }

        Id sessionId = sessions[0].Id;
        Id endUserId = sessions[0].MessagingEndUserId;

        Test.startTest();
        MessagingSessionTipificacionCtrl.saveTipificacion(
            sessionId, 'Consultas', 'Estado de pedido / Despacho', null);
        Test.stopTest();

        MessagingEndUser endUser = [
            SELECT Esperando_encuesta__c
            FROM   MessagingEndUser
            WHERE  Id = :endUserId
        ];
        Assert.isTrue(endUser.Esperando_encuesta__c,
            'Esperando_encuesta__c debe ser true después de guardar la tipificación');
    }
        @isTest
        static void getInt_debeEjecutar() {
            Test.startTest();
            MessagingSessionTipificacionCtrl.getInt();
            Test.stopTest();
        }

}