/**
 * @Name        : icbfs_RutValidatorTest
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Pruebas unitarias para validación de RUT en Account y Lead.
 */
@IsTest
private class icbfs_RutValidatorTest {

    @IsTest
static void test_Account_FormatoIncorrecto() {
    Account a = new Account(
        Name = 'Cuenta Test',
        RUT__c = '1234567-55' // 10 chars, formato inválido (DV con 2 dígitos)
    );

    try {
        insert a;
        System.assert(false, 'Debió fallar por formato');
    } catch (DmlException e) {
        System.assert(
            e.getDmlMessage(0).contains('Formato de RUT incorrecto'),
            e.getDmlMessage(0)
        );
    }
}


    @IsTest
    static void test_Account_DVInvalido() {
        Account a = new Account(
            Name = 'Cuenta Test',
            RUT__c = '12345678-1' // formato OK, DV malo (muy probable)
        );

        try {
            insert a;
            System.assert(false, 'Debió fallar por DV inválido');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('RUT inválido'),
                e.getDmlMessage(0)
            );
        }
    }

    @IsTest
    static void test_Account_Valido() {
        // Caso común: 12.345.678-5 => 12345678-5
        Account a = new Account(
            Name = 'Cuenta Test',
            RUT__c = '12345678-5'
        );

        insert a;
        System.assertNotEquals(null, a.Id);
    }

    @IsTest
    static void test_Lead_FormatoIncorrecto() {
        Lead l = new Lead(
            FirstName = 'Juan',
            LastName = 'Perez',
            Company = 'ACME',
            RUT__c = '123456785' // sin guion => falla formato
        );

        try {
            insert l;
            System.assert(false, 'Debió fallar por formato');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('Formato de RUT incorrecto'),
                e.getDmlMessage(0)
            );
        }
    }

    @IsTest
    static void test_Lead_DVInvalido() {
        Lead l = new Lead(
            FirstName = 'Juan',
            LastName = 'Gomez',
            Company = 'ACME',
            RUT__c = '12345678-1'
        );

        try {
            insert l;
            System.assert(false, 'Debió fallar por DV inválido');
        } catch (DmlException e) {
            System.assert(
                e.getDmlMessage(0).contains('RUT inválido'),
                e.getDmlMessage(0)
            );
        }
    }

    @IsTest
    static void test_Lead_Valido() {
        Lead l = new Lead(
            FirstName = 'Juan',
            LastName = 'Lopez',
            Company = 'ACME',
            RUT__c = '12345678-5'
        );

        insert l;
        System.assertNotEquals(null, l.Id);
    }

    @IsTest
    static void test_Lead_OpenDay_SinRut_Permitido() {
        // Los leads de OpenDay llegan del formulario web sin RUT — deben guardarse igual
        Lead l = new Lead(
            FirstName = 'Juan',
            LastName = 'OpenDay',
            Company = 'ACME',
            LeadSource = 'OpenDay'
        );

        insert l;
        System.assertNotEquals(null, l.Id, 'El lead OpenDay sin RUT debería guardarse sin error');
    }

    @IsTest
    static void test_Util_SoportaDVK() {
        // Asegura que el validador soporta DV K encontrando un cuerpo cuyo DV sea K.
        Integer cuerpoEncontrado;
        for (Integer i = 1000000; i < 1005000; i++) {
            icbfs_RutValidator.Result r = icbfs_RutValidator.validate(String.valueOf(i) + '-K');
            if (r.isFormatOk && r.isValid) {
                cuerpoEncontrado = i;
                break;
            }
        }
        System.assertNotEquals(null, cuerpoEncontrado, 'No se encontró un RUT con DV K en el rango');
    }
    @IsTest
static void test_Contact_FormatoIncorrecto() {
    Account a = new Account(Name='Cuenta Base');
    insert a;

    Contact c = new Contact(LastName='Contacto Test', AccountId=a.Id, RUT__c='123456785');
    try {
        insert c;
        System.assert(false, 'Debió fallar por formato');
    } catch (DmlException e) {
        System.assert(e.getDmlMessage(0).contains('Formato de RUT incorrecto'), e.getDmlMessage(0));
    }
}

@IsTest
static void test_Contact_DVInvalido() {
    Account a = new Account(Name='Cuenta Base');
    insert a;

    Contact c = new Contact(LastName='Contacto Test', AccountId=a.Id, RUT__c='12345678-1');
    try {
        insert c;
        System.assert(false, 'Debió fallar por DV inválido');
    } catch (DmlException e) {
        System.assert(e.getDmlMessage(0).contains('RUT inválido'), e.getDmlMessage(0));
    }
}

@IsTest
static void test_Contact_Valido() {
    Account a = new Account(Name='Cuenta Base');
    insert a;

    Contact c = new Contact(LastName='Contacto Test', AccountId=a.Id, RUT__c='12345678-5');
    insert c;
    System.assertNotEquals(null, c.Id);
}

    // ── Tests lookup RUT → Account ───────────────────────────────────────

    @IsTest
    static void test_Lead_AsignaAccountPorRUT() {
        Account cuenta = new Account(Name='Cuenta RUT Test', RUT__c='12345678-5');
        insert cuenta;

        Lead l = new Lead(FirstName='Test', LastName='RUT', Company='ACME', RUT__c='12345678-5');
        insert l;

        Lead insertado = [SELECT Account__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(cuenta.Id, insertado.Account__c, 'Debió asignar Account__c por RUT');
    }

    @IsTest
    static void test_Lead_AsignaAccountPorEmailFallback() {
        Account cuenta = new Account(Name='Cuenta Email Test', Email__c='match@test.com');
        insert cuenta;

        Lead l = new Lead(FirstName='Test', LastName='Email', Company='ACME', Email='match@test.com');
        insert l;

        Lead insertado = [SELECT Account__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(cuenta.Id, insertado.Account__c, 'Debió asignar Account__c por Email como fallback');
    }

    @IsTest
    static void test_Lead_SinMatchNinguno() {
        Lead l = new Lead(FirstName='Test', LastName='NoMatch', Company='ACME', Email='noexiste@test.com');
        insert l;

        Lead insertado = [SELECT Account__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(null, insertado.Account__c, 'No debió asignar Account__c si no hay match');
    }

    @IsTest
    static void test_Lead_Update_CambioEmail_AsignaAccount() {
        Account cuenta = new Account(Name='Cuenta Update Email', Email__c='update@test.com');
        insert cuenta;

        Lead l = new Lead(FirstName='Test', LastName='Update', Company='ACME', Email='otro@test.com');
        insert l;

        l.Email = 'update@test.com';
        update l;

        Lead actualizado = [SELECT Account__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(cuenta.Id, actualizado.Account__c, 'Debió asignar Account__c al cambiar email en update');
    }

}