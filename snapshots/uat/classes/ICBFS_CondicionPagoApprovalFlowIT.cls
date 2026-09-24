@IsTest(SeeAllData=true)
private class ICBFS_CondicionPagoApprovalFlowIT {

    private static Account getCandidateAccount() {
        List<Account> rows = [
            SELECT Id, OwnerId, condicion_pago__c, Condicion_Pago_Solicitada__c, Estado_Aprobacion_Condicion_Pago__c,
                   Owner.IsActive, Owner.ManagerId
            FROM Account
            WHERE Owner.IsActive = true
              AND Owner.ManagerId != null
              AND condicion_pago__c IN ('ZD01', 'ZE01')
              AND (Estado_Aprobacion_Condicion_Pago__c = null OR Estado_Aprobacion_Condicion_Pago__c != 'En Proceso de Aprobacion')
              AND Id NOT IN (
                  SELECT TargetObjectId
                  FROM ProcessInstance
                  WHERE Status = 'Pending'
              )
            LIMIT 1
        ];
        System.assert(!rows.isEmpty(), 'No existe cuenta candidata para pruebas de condicion de pago.');
        return rows[0];
    }

    private static String oppositeCondicion(String value) {
        return value == 'ZD01' ? 'ZE01' : 'ZD01';
    }

    private static User getBypassUser() {
        List<User> usersWithBypass = [
            SELECT Id
            FROM User
            WHERE IsActive = true
              AND Id IN (
                  SELECT AssigneeId
                  FROM PermissionSetAssignment
                  WHERE PermissionSet.Name = 'Bypass_Condicion_Pago_Aprobacion'
              )
            LIMIT 1
        ];
        if (!usersWithBypass.isEmpty()) {
            return usersWithBypass[0];
        }

        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE PermissionsModifyAllData = true
            LIMIT 1
        ];

        String stamp = String.valueOf(Datetime.now().getTime());
        User u = new User(
            Alias = 'tadmin',
            Email = 'test.bypass.' + stamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Bypass',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            ProfileId = adminProfile.Id,
            Username = 'test.bypass.' + stamp + '@example.com'
        );
        insert u;

        PermissionSet bypassPs = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Bypass_Condicion_Pago_Aprobacion'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = bypassPs.Id);

        return u;
    }

    @IsTest
    static void testSolicitudCreaProcesoPendienteYBloqueaDuplicado() {
        Account baseAcc = getCandidateAccount();
        User ownerUser = [SELECT Id FROM User WHERE Id = :baseAcc.OwnerId LIMIT 1];

        String oldCond = baseAcc.condicion_pago__c;
        String requestedCond = oppositeCondicion(oldCond);

        Test.startTest();
        System.runAs(ownerUser) {
            update new Account(
                Id = baseAcc.Id,
                condicion_pago__c = requestedCond
            );
        }
        Test.stopTest();

        Account afterRequest = [
            SELECT condicion_pago__c, Condicion_Pago_Solicitada__c, Estado_Aprobacion_Condicion_Pago__c
            FROM Account
            WHERE Id = :baseAcc.Id
        ];

        System.assertEquals(oldCond, afterRequest.condicion_pago__c, 'El valor real no debe cambiar hasta la aprobacion.');
        System.assertEquals(requestedCond, afterRequest.Condicion_Pago_Solicitada__c, 'Debe guardar condicion solicitada.');
        System.assertEquals('En Proceso de Aprobacion', afterRequest.Estado_Aprobacion_Condicion_Pago__c, 'Debe quedar en proceso.');

        Integer pendingCount = [
            SELECT COUNT()
            FROM ProcessInstance
            WHERE TargetObjectId = :baseAcc.Id
              AND Status = 'Pending'
        ];
        System.assertEquals(1, pendingCount, 'Debe crear exactamente una solicitud de aprobacion pendiente.');

        try {
            System.runAs(ownerUser) {
                update new Account(
                    Id = baseAcc.Id,
                    condicion_pago__c = requestedCond
                );
            }
            System.assert(false, 'Debio bloquear un segundo intento mientras hay una aprobacion pendiente.');
        } catch (DmlException e) {
            String msg = e.getDmlMessage(0);
            System.assert(
                msg.contains('Ya existe una solicitud de cambio de condicion de pago en proceso')
                || msg.contains('Este registro está bloqueado')
                || msg.contains('This record is locked'),
                'Mensaje inesperado: ' + msg
            );
        }
    }

    @IsTest
    static void testAprobacionAplicaCambioSolicitado() {
        Account baseAcc = getCandidateAccount();
        User ownerUser = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :baseAcc.OwnerId
            LIMIT 1
        ];
        User managerUser = [
            SELECT Id
            FROM User
            WHERE Id = :ownerUser.ManagerId
            LIMIT 1
        ];

        String oldCond = baseAcc.condicion_pago__c;
        String requestedCond = oppositeCondicion(oldCond);

        Test.startTest();
        System.runAs(ownerUser) {
            update new Account(
                Id = baseAcc.Id,
                condicion_pago__c = requestedCond
            );
        }

        ProcessInstanceWorkitem wi = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :baseAcc.Id
            LIMIT 1
        ];

        System.runAs(managerUser) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(wi.Id);
            req.setAction('Approve');
            req.setComments('Aprobado desde test.');
            Approval.ProcessResult res = Approval.process(req);
            System.assert(res.isSuccess(), 'La aprobacion del work item debe ser exitosa.');
        }
        Test.stopTest();

        Account afterApprove = [
            SELECT condicion_pago__c, Condicion_Pago_Solicitada__c, Estado_Aprobacion_Condicion_Pago__c
            FROM Account
            WHERE Id = :baseAcc.Id
        ];

        System.assertEquals(requestedCond, afterApprove.condicion_pago__c, 'Al aprobar se debe aplicar la condicion solicitada.');
        System.assertEquals(null, afterApprove.Condicion_Pago_Solicitada__c, 'Al aprobar se debe limpiar la condicion solicitada.');
        System.assertEquals('Aprobada', afterApprove.Estado_Aprobacion_Condicion_Pago__c, 'Al aprobar debe volver a Aprobada.');
    }

    @IsTest
    static void testBypassAdminAplicaCambioDirectoSinAprobacion() {
        Account baseAcc = getCandidateAccount();
        User bypassUser = getBypassUser();

        String oldCond = baseAcc.condicion_pago__c;
        String requestedCond = oppositeCondicion(oldCond);

        Test.startTest();
        System.runAs(bypassUser) {
            update new Account(
                Id = baseAcc.Id,
                condicion_pago__c = requestedCond
            );
        }
        Test.stopTest();

        Account afterBypass = [
            SELECT condicion_pago__c, Condicion_Pago_Solicitada__c, Estado_Aprobacion_Condicion_Pago__c
            FROM Account
            WHERE Id = :baseAcc.Id
        ];

        System.assertEquals(requestedCond, afterBypass.condicion_pago__c, 'Con bypass admin debe aplicar cambio directo.');
        System.assertEquals(null, afterBypass.Condicion_Pago_Solicitada__c, 'Con bypass no debe quedar solicitud pendiente.');
        System.assertEquals('Aprobada', afterBypass.Estado_Aprobacion_Condicion_Pago__c, 'Con bypass debe permanecer Aprobada.');

        Integer pendingCount = [
            SELECT COUNT()
            FROM ProcessInstance
            WHERE TargetObjectId = :baseAcc.Id
              AND Status = 'Pending'
        ];
        System.assertEquals(0, pendingCount, 'Con bypass no debe crearse proceso pendiente.');
    }
}