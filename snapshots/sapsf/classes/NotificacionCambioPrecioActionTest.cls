/**
 * Pruebas de NotificacionCambioPrecioAction y del subflujo CAMBIO_LISTA_PRECIOS_EML_NotificarCambiosZona.
 * Versión: v2 - 2026-09-23
 */
@IsTest
private class NotificacionCambioPrecioActionTest {
    private static final String ZONA_CON_USUARIOS = 'Suc Santiago';
    private static final String ZONA_SIN_GRUPO_TEST = 'Suc Calama';
    private static final String FLUJO_NOTIFICACION = 'CAMBIO_LISTA_PRECIOS_EML_NotificarCambiosZona';

    @TestSetup
    static void crearDatos() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Group grupo = new Group(Name = ZONA_CON_USUARIOS, DeveloperName = 'Suc_Test_Notificacion', Type = 'Regular');
            insert grupo;
            insert new GroupMember(GroupId = grupo.Id, UserOrGroupId = UserInfo.getUserId());
        }

        Cambio_Lista_Precios__c cambio = new Cambio_Lista_Precios__c(
            Name = 'Cambio Test',
            Fecha_de_cambio__c = Date.today(),
            Enviar_Notificacion__c = false
        );
        insert cambio;

        insert new List<Informacion_Producto__c>{
            new Informacion_Producto__c(Cambio_Lista_Precios__c = cambio.Id, Zona__c = ZONA_CON_USUARIOS),
            new Informacion_Producto__c(Cambio_Lista_Precios__c = cambio.Id, Zona__c = ZONA_CON_USUARIOS),
            new Informacion_Producto__c(Cambio_Lista_Precios__c = cambio.Id, Zona__c = ZONA_CON_USUARIOS, Notificacion_enviada__c = true)
        };
    }

    @IsTest
    static void enviarNotificacionesDebeEnviarUnaInvocacionDeCorreo() {
        Cambio_Lista_Precios__c cambio = [SELECT Id FROM Cambio_Lista_Precios__c LIMIT 1];

        NotificacionCambioPrecioAction.Request req = new NotificacionCambioPrecioAction.Request();
        req.cambioListaPreciosId = cambio.Id;
        req.usuarioIds = new List<String>{ UserInfo.getUserId(), UserInfo.getUserId() };
        req.zonas = new List<String>{ ZONA_CON_USUARIOS, ZONA_CON_USUARIOS };
        req.cantidadesProductos = new List<Decimal>{ 2, 2 };

        Test.startTest();
        NotificacionCambioPrecioAction.enviarNotificaciones(new List<NotificacionCambioPrecioAction.Request>{ req });
        Integer invocaciones = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(1, invocaciones, 'Debe enviarse todo en una sola invocación de correo');
    }

    @IsTest
    static void enviarNotificacionesSinNotificacionesNoDebeEnviarCorreo() {
        Cambio_Lista_Precios__c cambio = [SELECT Id FROM Cambio_Lista_Precios__c LIMIT 1];

        NotificacionCambioPrecioAction.Request req = new NotificacionCambioPrecioAction.Request();
        req.cambioListaPreciosId = cambio.Id;

        Test.startTest();
        NotificacionCambioPrecioAction.enviarNotificaciones(new List<NotificacionCambioPrecioAction.Request>{ req });
        Integer invocaciones = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocaciones, 'No debe enviarse correo sin notificaciones');
    }

    @IsTest
    static void subflujoDebeMarcarProductosNotificadosDeZonaConUsuarios() {
        Cambio_Lista_Precios__c cambio = [SELECT Id FROM Cambio_Lista_Precios__c LIMIT 1];
        Informacion_Producto__c productoSinGrupo = new Informacion_Producto__c(
            Cambio_Lista_Precios__c = cambio.Id,
            Zona__c = ZONA_SIN_GRUPO_TEST
        );
        insert productoSinGrupo;

        Test.startTest();
        Flow.Interview.createInterview(
                FLUJO_NOTIFICACION,
                new Map<String, Object>{ 'varT_CambioListaPreciosId' => cambio.Id }
            )
            .start();
        Integer invocaciones = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(1, invocaciones, 'El subflujo debe enviar los correos en una sola invocación');
        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Informacion_Producto__c WHERE Zona__c = :ZONA_CON_USUARIOS AND Notificacion_enviada__c = TRUE],
            'Los productos de la zona con usuarios deben quedar notificados'
        );
    }
}