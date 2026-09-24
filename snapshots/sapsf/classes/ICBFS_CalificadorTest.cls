@IsTest
private class ICBFS_CalificadorTest {
    private class AcceptedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(request.getEndpoint().endsWith('/v1/calificar/async'));
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            System.assert(body.containsKey('lead'));
            System.assertEquals('https://relay.example.test/calificador', body.get('webhook'));
            Map<String, Object> headers = (Map<String, Object>) body.get('webhook_headers');
            System.assertEquals('TEST-QUEUE-001', headers.get('X-ICBFS-Correlation-Id'));
            System.assertEquals('callback-token-test', headers.get('X-ICBFS-Callback-Token'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(202);
            response.setBody('{"ok":true,"estado":"en_proceso","executionArn":"arn:aws:states:qa:test-001","mensaje":"aceptado"}');
            return response;
        }
    }

    private static ICBFS_CalificadorConfig.Values enabledConfig() {
        ICBFS_CalificadorConfig.Values config = new ICBFS_CalificadorConfig.Values();
        config.enabled = true;
        config.webhookUrl = 'https://relay.example.test/calificador';
        config.ownerUsernameBase = 'usuario.integracion@icbfs.cl';
        config.codePrefix = 'FS';
        config.excludedRecordType = 'Sucursal';
        config.callbackToken = 'callback-token-test';
        return config;
    }

    private static User integrationUser() {
        return [SELECT Id, Username FROM User WHERE Username LIKE 'usuario.integracion@icbfs.cl%' AND IsActive=true LIMIT 1];
    }

    private static Id businessRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='Negocio' LIMIT 1].Id;
    }

    private static Account createEligibleAccount() {
        Account account = new Account(
            Name='Cliente Calificador QA', OwnerId=integrationUser().Id, RecordTypeId=businessRecordTypeId(),
            RUT__c='78793360-2', C_digo_de_cliente__c='QA-NO-CALIFICAR', Email__c='qa@example.test',
            Contacto_Auxiliar__c='Contacto QA Calificador', Phone='+56911111111',
            Website='https://example.test', BillingStreet='El Rosal 4864', BillingCity='Huechuraba',
            Especialidad__c='C9 - Cliente B2B PIA'
        );
        insert account;
        account.C_digo_de_cliente__c = 'FS-TEST-001';
        update account;
        return account;
    }

    @IsTest static void flowActionCreatesOneRequestAndQueues() {
        Account account = createEligibleAccount();
        ICBFS_CalificadorFlowAction.Input input = new ICBFS_CalificadorFlowAction.Input();
        input.accountId = account.Id;
        List<ICBFS_CalificadorFlowAction.Output> outputs = ICBFS_CalificadorFlowAction.enqueue(
            new List<ICBFS_CalificadorFlowAction.Input>{input}
        );
        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].queued);
        ICBFS_Calificacion_Request__c request = [
            SELECT Account__c, Estado__c, Correlation_Id__c FROM ICBFS_Calificacion_Request__c WHERE Id=:outputs[0].requestId
        ];
        System.assertEquals(account.Id, request.Account__c);
        System.assertEquals('Pendiente', request.Estado__c);
        System.assertNotEquals(null, request.Correlation_Id__c);
    }

    @IsTest static void queueableSendsAsyncAndStoresArn() {
        Account account = createEligibleAccount();
        ICBFS_Calificacion_Request__c request = new ICBFS_Calificacion_Request__c(
            Account__c=account.Id, Correlation_Id__c='TEST-QUEUE-001', Estado__c='Pendiente', Intento__c=0, Fecha_Solicitud__c=System.now()
        );
        insert request;
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        Test.setMock(HttpCalloutMock.class, new AcceptedMock());
        Test.startTest();
        new ICBFS_CalificadorQueueable(new List<Id>{request.Id}).execute(null);
        Test.stopTest();
        request = [SELECT Estado__c, Execution_Arn__c, Intento__c FROM ICBFS_Calificacion_Request__c WHERE Id=:request.Id];
        account = [SELECT ICBFS_Calificador_Estado__c, ICBFS_Calificador_ExecutionArn__c FROM Account WHERE Id=:account.Id];
        System.assertEquals('En proceso', request.Estado__c);
        System.assertEquals('arn:aws:states:qa:test-001', request.Execution_Arn__c);
        System.assertEquals(1, request.Intento__c);
        System.assertEquals('En proceso', account.ICBFS_Calificador_Estado__c);
    }

    @IsTest static void queueableRejectsSucursalWithoutCallout() {
        Account account = createEligibleAccount();
        account.RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType='Account' AND DeveloperName='Sucursal' LIMIT 1].Id;
        update account;
        ICBFS_Calificacion_Request__c request = new ICBFS_Calificacion_Request__c(
            Account__c=account.Id, Correlation_Id__c='TEST-NOAPLICA-001', Estado__c='Pendiente', Intento__c=0
        );
        insert request;
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        new ICBFS_CalificadorQueueable(new List<Id>{request.Id}).execute(null);
        request = [SELECT Estado__c FROM ICBFS_Calificacion_Request__c WHERE Id=:request.Id];
        System.assertEquals('No aplica', request.Estado__c);
    }

    @IsTest static void eventUpdatesAccountAndIsIdempotent() {
        Account account = createEligibleAccount();
        String arn = 'arn:aws:states:qa:event-001';
        ICBFS_Calificacion_Request__c request = new ICBFS_Calificacion_Request__c(
            Account__c=account.Id, Correlation_Id__c='TEST-EVENT-001', Execution_Arn__c=arn,
            Estado__c='En proceso', Intento__c=1
        );
        insert request;
        Map<String, Object> lead = new Map<String, Object>{
            'codigo'=>String.valueOf(account.Id), 'calificacion'=>'A', 'score'=>88, 'segmento'=>'horeca', 'confiabilidad'=>'alta',
            'd1'=>new Map<String,Object>{'puntaje'=>100}, 'd2'=>new Map<String,Object>{'puntaje'=>100},
            'd3'=>new Map<String,Object>{'puntaje'=>100}, 'd4'=>new Map<String,Object>{'puntaje'=>20},
            'alertas'=>new List<String>{'Alerta de prueba'}, 'notas'=>'Resultado QA'
        };
        String payload = JSON.serialize(new Map<String, Object>{'run_ts'=>'20260803-2116','leads'=>new List<Object>{lead}});
        ICBFS_Calificacion_Lead__e event = new ICBFS_Calificacion_Lead__e(
            Account_Id__c=String.valueOf(account.Id), Execution_Arn__c=arn, Payload__c=payload
        );
        Test.startTest();
        Database.SaveResult published = EventBus.publish(event);
        System.assertEquals(true, published.isSuccess());
        Test.getEventBus().deliver();
        // Reentrega deliberada: el consumidor debe ser idempotente.
        EventBus.publish(new ICBFS_Calificacion_Lead__e(
            Account_Id__c=String.valueOf(account.Id), Execution_Arn__c=arn, Payload__c=payload
        ));
        Test.getEventBus().deliver();
        Test.stopTest();
        account = [SELECT ICBFS_Calificador_Estado__c, ICBFS_Calificacion__c, ICBFS_Calificador_Score__c,
                          ICBFS_Calificador_D1__c, ICBFS_Calificador_D4__c FROM Account WHERE Id=:account.Id];
        request = [SELECT Estado__c, Payload_Respuesta__c FROM ICBFS_Calificacion_Request__c WHERE Id=:request.Id];
        System.assertEquals('Completado', account.ICBFS_Calificador_Estado__c);
        System.assertEquals('A', account.ICBFS_Calificacion__c);
        System.assertEquals(88, account.ICBFS_Calificador_Score__c);
        System.assertEquals(100, account.ICBFS_Calificador_D1__c);
        System.assertEquals(20, account.ICBFS_Calificador_D4__c);
        System.assertEquals('Completado', request.Estado__c);
        System.assert(request.Payload_Respuesta__c.contains('Resultado QA'));
    }

    @IsTest static void callbackRejectsInvalidToken() {
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        RestContext.request = callbackRequest('invalid-token', 'TEST-CALLBACK-401', '{}');
        RestContext.response = new RestResponse();
        ICBFS_CalificadorCallbackRest.receive();
        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest static void callbackRejectsMissingCorrelation() {
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        RestContext.request = callbackRequest('callback-token-test', null, '{}');
        RestContext.response = new RestResponse();
        ICBFS_CalificadorCallbackRest.receive();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest static void callbackPublishesAndUpdatesAccount() {
        Account account = createEligibleAccount();
        String arn = 'arn:aws:states:qa:callback-001';
        String correlationId = 'TEST-CALLBACK-202';
        insert new ICBFS_Calificacion_Request__c(
            Account__c=account.Id, Correlation_Id__c=correlationId, Execution_Arn__c=arn,
            Estado__c='En proceso', Intento__c=1
        );
        Map<String, Object> lead = new Map<String, Object>{
            'codigo'=>String.valueOf(account.Id), 'calificacion'=>'B+', 'score'=>70,
            'segmento'=>'distribuidor', 'confiabilidad'=>'media'
        };
        String payload = JSON.serialize(new Map<String, Object>{'leads'=>new List<Object>{lead}});
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        RestContext.request = callbackRequest('callback-token-test', correlationId, payload);
        RestContext.response = new RestResponse();
        Test.startTest();
        ICBFS_CalificadorCallbackRest.receive();
        System.assertEquals(202, RestContext.response.statusCode);
        Test.getEventBus().deliver();
        Test.stopTest();
        account = [SELECT ICBFS_Calificador_Estado__c, ICBFS_Calificacion__c FROM Account WHERE Id=:account.Id];
        System.assertEquals('Completado', account.ICBFS_Calificador_Estado__c);
        System.assertEquals('B+', account.ICBFS_Calificacion__c);
    }

    @IsTest static void callbackPropagatesAwsFailure() {
        Account account = createEligibleAccount();
        String arn = 'arn:aws:states:qa:callback-failure';
        String correlationId = 'TEST-CALLBACK-FAIL';
        ICBFS_Calificacion_Request__c request = new ICBFS_Calificacion_Request__c(
            Account__c=account.Id, Correlation_Id__c=correlationId, Execution_Arn__c=arn,
            Estado__c='En proceso', Intento__c=1
        );
        insert request;
        String payload = '{"estado":"fallido","error":"Prueba de fallo AWS","leads":[]}';
        ICBFS_CalificadorConfig.testValues = enabledConfig();
        RestContext.request = callbackRequest('callback-token-test', correlationId, payload);
        RestContext.response = new RestResponse();
        Test.startTest();
        ICBFS_CalificadorCallbackRest.receive();
        Test.getEventBus().deliver();
        Test.stopTest();
        account = [SELECT ICBFS_Calificador_Estado__c, ICBFS_Calificador_Ultimo_Error__c FROM Account WHERE Id=:account.Id];
        request = [SELECT Estado__c, Ultimo_Error__c FROM ICBFS_Calificacion_Request__c WHERE Id=:request.Id];
        System.assertEquals('Error', account.ICBFS_Calificador_Estado__c);
        System.assertEquals('Error', request.Estado__c);
        System.assertEquals('Prueba de fallo AWS', request.Ultimo_Error__c);
    }

    private static RestRequest callbackRequest(String token, String correlationId, String payload) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/icbfs/calificador/callback';
        request.httpMethod = 'POST';
        request.addHeader('X-ICBFS-Callback-Token', token);
        if (correlationId != null) request.addHeader('X-ICBFS-Correlation-Id', correlationId);
        request.requestBody = Blob.valueOf(payload);
        return request;
    }
}