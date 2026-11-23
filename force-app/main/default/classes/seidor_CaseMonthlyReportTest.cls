@isTest
private class seidor_CaseMonthlyReportTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name = 'Test Account',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Negocio').getRecordTypeId()
        );
        insert acc;

        Account acc2 = new Account(
            Name = 'Segunda Account',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Negocio').getRecordTypeId()
        );
        insert acc2;

        Account suc = new Account(
            Name = 'Sucursal Test',
            ParentId = acc.Id,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Sucursal').getRecordTypeId(),
            Cliente_Despacho__c = 'FS34880-2',
            Region_Despacho__c = '13 - Región Metropolitana'
        );
        insert suc;

        List<Case> cases = new List<Case>();

        for (Integer i = 0; i < 5; i++) {
            cases.add(new Case(
                AccountId = acc.Id,
                Subject = 'Caso Test ' + i,
                Status = 'New',
                Origin = 'Email',
                Tipo_de_Requerimiento__c = 'Reclamo',
                Tipo_de_Reclamo__c = 'Calidad',
                Cantidad_reclamada__c = 10 + i,
                Valor_Neto__c = 1000 * (i + 1),
                Motivo__c = 'Calidad',
                Categoria__c = 'Rechazo de pedido',
                Sub_Categoria__c = 'Producto Vencido',
                Region_Cliente__c = '13 - Región Metropolitana',
                Sucursal_de_Retiro__c = suc.Id,
                Cumple_los_plazos__c = 'SI',
                Procede_el_Reclamo__c = 'Si, con retiro',
                Horario_retiro__c = '08:00 - 17:00'
            ));
        }

        cases.add(new Case(
            AccountId = acc2.Id,
            Subject = 'Caso Sin Sucursal',
            Status = 'New',
            Origin = 'Phone',
            Tipo_de_Requerimiento__c = 'Consulta',
            Region_Cliente__c = '13 - Región Metropolitana',
            Horario_retiro__c = '08:00 - 17:00'
        ));

        cases.add(new Case(
            Subject = 'Caso Sin Account',
            Status = 'New',
            Origin = 'Web',
            Tipo_de_Requerimiento__c = 'Reclamo',
            Region_Cliente__c = '13 - Región Metropolitana',
            Horario_retiro__c = '08:00 - 17:00'
        ));

        insert cases;

        List<Case> allCases = [SELECT Id, CreatedDate FROM Case WHERE Subject LIKE 'Caso Test%'];
        for (Case c : allCases) {
            Test.setCreatedDate(c.Id, Date.today().addMonths(-2));
        }

        Case caseWithFuture = [SELECT Id FROM Case WHERE Subject = 'Caso Sin Account' LIMIT 1];
        Test.setCreatedDate(caseWithFuture.Id, Date.today().addMonths(-1));
    }

    @isTest
    static void testGetReport() {
        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.groups.size() > 0);
        System.assert(result.totalRecords > 0);
        System.assert(result.totalRecords >= 7);
    }

    @isTest
    static void testGrouping() {
        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        Map<String, Integer> monthCounts = new Map<String, Integer>();
        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            monthCounts.put(g.monthLabel, g.totalCases);
            System.assertNotEquals(null, g.monthLabel);
            System.assert(g.records.size() > 0);
            System.assertEquals(g.records.size(), g.totalCases);
        }
        System.assert(monthCounts.size() >= 2);
    }

    @isTest
    static void testWrapperFields() {
        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        Boolean foundAccount = false;
        Boolean foundNoAccount = false;
        Boolean foundClosed = false;

        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            for (seidor_CaseMonthlyReportDTO.CaseWrapper w : g.records) {
                System.assertNotEquals(null, w.id);
                System.assertNotEquals(null, w.caseNumber);
                System.assertNotEquals(null, w.createdDate);
                System.assertNotEquals(null, w.status);

                if (w.accountName == 'Test Account') {
                    foundAccount = true;
                    System.assertNotEquals(null, w.asesor);
                    System.assertEquals('Calidad', w.motivo);
                    System.assertEquals('Rechazo de pedido', w.categoria);
                    System.assertEquals('Producto Vencido', w.causa);
                }
                if (w.accountName == null) {
                    foundNoAccount = true;
                    System.assertEquals(null, w.asesor);
                    System.assertEquals(null, w.codigoAsesor);
                    System.assertEquals(null, w.clienteDespacho);
                }
                if (w.closedDate != null) {
                    foundClosed = true;
                }
            }
        }
        System.assert(foundAccount, 'Should have cases with account');
        System.assert(foundNoAccount, 'Should have cases without account');
    }

    @isTest
    static void testPeriodoAtencionCalcDias() {
        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        Integer withClosed = 0;
        Integer withoutClosed = 0;
        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            for (seidor_CaseMonthlyReportDTO.CaseWrapper w : g.records) {
                if (w.closedDate != null) {
                    withClosed++;
                    System.assertNotEquals(null, w.periodoAtencion);
                    System.assert(w.periodoAtencion.contains('días'));
                } else {
                    withoutClosed++;
                    System.assertEquals(null, w.periodoAtencion);
                }
            }
        }
        System.assert(withoutClosed > 0, 'Should have cases without ClosedDate');
    }

    @isTest
    static void testMultipleMonthsGrouping() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        List<Case> cases = new List<Case>();
        for (Integer m = 1; m <= 3; m++) {
            cases.add(new Case(
                AccountId = acc.Id,
                Subject = 'Caso Mes ' + m,
                Status = 'New',
                Origin = 'Email',
                Tipo_de_Requerimiento__c = 'Reclamo',
                Region_Cliente__c = '13 - Región Metropolitana',
                Horario_retiro__c = '08:00 - 17:00'
            ));
        }
        insert cases;

        Test.setCreatedDate(cases[0].Id, Date.newInstance(2025, 1, 15));
        Test.setCreatedDate(cases[1].Id, Date.newInstance(2025, 6, 10));
        Test.setCreatedDate(cases[2].Id, Date.newInstance(2025, 12, 25));

        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        System.assert(result.groups.size() >= 3, 'Should have at least 3 month groups');
    }

    @isTest
    static void testNullFieldsInWrapper() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Segunda Account' LIMIT 1];
        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Caso Campos Nulos',
            Status = 'New',
            Origin = 'Phone',
            Region_Cliente__c = '13 - Región Metropolitana',
            Horario_retiro__c = '08:00 - 17:00'
        );
        insert c;

        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            for (seidor_CaseMonthlyReportDTO.CaseWrapper w : g.records) {
                if (w.caseNumber == c.CaseNumber) {
                    System.assertEquals(null, w.closedDate);
                    System.assertEquals(null, w.periodoAtencion);
                    System.assertEquals(null, w.sku);
                    System.assertEquals(null, w.nombreProducto);
                    System.assertEquals(null, w.cantidadReclamada);
                    System.assertEquals(null, w.valorNeto);
                    System.assertEquals(null, w.causa);
                }
            }
        }
    }

    @isTest
    static void testDTOConstructor() {
        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult rr =
            new seidor_CaseMonthlyReportDTO.ReportResult();
        System.assertNotEquals(null, rr.groups);
        System.assertEquals(0, rr.totalRecords);
        System.assertEquals(false, rr.hasMore);
        System.assertEquals(1, rr.currentPage);

        seidor_CaseMonthlyReportDTO.MonthGroup mg =
            new seidor_CaseMonthlyReportDTO.MonthGroup(3, 2025, 'Marzo 2025');
        System.assertEquals(3, mg.month);
        System.assertEquals(2025, mg.year);
        System.assertEquals('Marzo 2025', mg.monthLabel);
        System.assertEquals(0, mg.totalCases);
        System.assertNotEquals(null, mg.records);

        seidor_CaseMonthlyReportDTO.CaseWrapper cw =
            new seidor_CaseMonthlyReportDTO.CaseWrapper();
        System.assertNotEquals(null, cw);
        Test.stopTest();
    }

    @isTest
    static void testSendCaseReportEmail() {
        Test.startTest();
        seidor_CaseMonthlyReportController.sendCaseReportEmail(
            new List<String>{'test@correo.com'},
            new List<String>{},
            'Reporte de Casos - Test',
            '<p>Mensaje de prueba</p><table><tr><th>Caso</th></tr><tr><td>C-001</td></tr></table>',
            null,
            null
        );
        Test.stopTest();
        System.assert(true, 'Email sent without exception');
    }

    @isTest
    static void testSendCaseReportEmailMultipleRecipients() {
        Test.startTest();
        seidor_CaseMonthlyReportController.sendCaseReportEmail(
            new List<String>{'test1@correo.com', 'test2@correo.com'},
            new List<String>{'cc1@correo.com'},
            'Reporte Multiple',
            '<p>Body</p>',
            null,
            null
        );
        Test.stopTest();
        System.assert(true, 'Multi-recipient email sent');
    }

    @isTest
    static void testSendCaseReportEmailWithAttachment() {
        String attachmentName = 'Reporte_Casos_2026-09-01.xls';
        String attachmentBase64 = EncodingUtil.base64Encode(Blob.valueOf('<html><body><table><tr><th>Caso</th></tr><tr><td>C-001</td></tr></table></body></html>'));
        Test.startTest();
        seidor_CaseMonthlyReportController.sendCaseReportEmail(
            new List<String>{'test@correo.com'},
            new List<String>{},
            'Reporte con adjunto',
            '<p>Mensaje con Excel adjunto</p>',
            attachmentName,
            attachmentBase64
        );
        Test.stopTest();
        System.assert(true, 'Email with attachment sent without exception');
    }

    @isTest
    static void testSendEmailNoRecipients() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            seidor_CaseMonthlyReportController.sendCaseReportEmail(
                new List<String>(), null, 'Subject', '<p>Body</p>', null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for empty recipients');
    }

    @isTest
    static void testSendEmailNoSubject() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            seidor_CaseMonthlyReportController.sendCaseReportEmail(
                new List<String>{'test@correo.com'}, null, '', '<p>Body</p>', null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for blank subject');
    }

    @isTest
    static void testSendEmailNoBody() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            seidor_CaseMonthlyReportController.sendCaseReportEmail(
                new List<String>{'test@correo.com'}, null, 'Subject', '', null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for blank body');
    }

    @isTest
    static void testSearchUsers() {
        Test.startTest();
        List<Map<String, String>> results = seidor_CaseMonthlyReportController.searchUsers('Test');
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @isTest
    static void testSearchUsersNoResults() {
        Test.startTest();
        List<Map<String, String>> results = seidor_CaseMonthlyReportController.searchUsers('zzz_nonexistent_user_zzz');
        Test.stopTest();
        System.assertEquals(0, results.size());
    }

    @isTest
    static void testClosedCasePeriodoAtencion() {
        Case closedCase = new Case(
            Subject = 'Caso Cerrado',
            Status = 'Closed',
            Origin = 'Email',
            Tipo_de_Requerimiento__c = 'Reclamo',
            Region_Cliente__c = '13 - Región Metropolitana',
            Horario_retiro__c = '08:00 - 17:00'
        );
        insert closedCase;
        Test.setCreatedDate(closedCase.Id, Date.today().addDays(-3));

        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        Boolean found = false;
        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            for (seidor_CaseMonthlyReportDTO.CaseWrapper w : g.records) {
                if (w.id == closedCase.Id) {
                    found = true;
                    System.assertNotEquals(null, w.closedDate);
                    System.assertNotEquals(null, w.periodoAtencion);
                    System.assert(w.periodoAtencion.contains('días'));
                }
            }
        }
        System.assert(found, 'Closed case must be present in the report');
    }

    @isTest
    static void testSucursalClienteDespacho() {
        Account suc = [SELECT Id FROM Account WHERE Name = 'Sucursal Test' LIMIT 1];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        suc.Centro_de_Abastecimiento__c = 'FS03 - Temuco';
        update suc;
        Case c = new Case(
            AccountId = acc.Id,
            Sucursal_de_Retiro__c = suc.Id,
            Subject = 'Caso Sucursal',
            Status = 'New',
            Origin = 'Email',
            Tipo_de_Requerimiento__c = 'Reclamo',
            Region_Cliente__c = '13 - Región Metropolitana',
            Horario_retiro__c = '08:00 - 17:00'
        );
        insert c;

        Test.startTest();
        seidor_CaseMonthlyReportDTO.ReportResult result =
            seidor_CaseMonthlyReportController.getReport();
        Test.stopTest();

        Boolean found = false;
        for (seidor_CaseMonthlyReportDTO.MonthGroup g : result.groups) {
            for (seidor_CaseMonthlyReportDTO.CaseWrapper w : g.records) {
                if (w.id == c.Id) {
                    found = true;
                    System.assertEquals('FS34880-2', w.clienteDespacho);
                    System.assertEquals('FS03 - Temuco', w.centroAbastecimiento);
                    System.assertNotEquals(null, w.asesor);
                }
            }
        }
        System.assert(found, 'Case with sucursal must be present in the report');
    }

    @isTest
    static void testGetCaseById() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Caso Test 0' LIMIT 1];
        Test.startTest();
        seidor_CaseMonthlyReportDTO.CaseWrapper w =
            seidor_CaseMonthlyReportController.getCaseDetail(c.Id);
        Test.stopTest();
        System.assertNotEquals(null, w);
        System.assertEquals(c.Id, w.id);
        System.assertNotEquals(null, w.caseNumber);
        System.assertEquals('Reclamo', w.tipoRequerimiento);
        System.assertEquals('Rechazo de pedido', w.categoria);
    }

    @isTest
    static void testGetCaseByIdNullThrows() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            seidor_CaseMonthlyReportController.getCaseDetail(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for null case id');
    }

    @isTest
    static void testGetCaseByIdNotFoundThrows() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            seidor_CaseMonthlyReportController.getCaseDetail(Id.valueOf(
                '500000000000000AAA'));
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw for nonexistent case id');
    }

    @isTest
    static void testGetCaseDetailFields() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Caso Detalle Campos',
            Status = 'New',
            Origin = 'Email',
            Tipo_de_Requerimiento__c = 'Reclamo',
            Tipo_de_Reclamo__c = 'Calidad',
            Procede_el_Reclamo__c = 'Si, con retiro',
            Horario_retiro__c = '08:00 - 17:00',
            Fecha_retiro__c = Date.today().addDays(-2),
            Fecha_recepcion__c = Date.today().addDays(-1),
            Estado_Nota_de_Credito__c = 'Lista',
            Estado_de_Producto__c = 'Producto acorde',
            Valor_Neto__c = 1234.56
        );
        insert c;

        Test.startTest();
        seidor_CaseMonthlyReportDTO.CaseWrapper w =
            seidor_CaseMonthlyReportController.getCaseDetail(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, w.fechaRetiro);
        System.assertNotEquals(null, w.fechaRecepcion);
        System.assertEquals('Lista', w.estadoNotaCredito);
        System.assertEquals('Producto acorde', w.estadoProducto);
        System.assertEquals('08:00 - 17:00', w.horarioRetiro);
        System.assertEquals(1234.56, w.valorNeto);
    }
}