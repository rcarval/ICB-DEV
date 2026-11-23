@IsTest
private class ICBFS_FlowLookupContactoCuentaCtrlTest {

    @IsTest
    static void searchContactsByAccount_returnsAccountContactsOnly() {
        Account accountOne = new Account(Name = 'Cuenta Uno');
        Account accountTwo = new Account(Name = 'Cuenta Dos');
        insert new List<Account>{ accountOne, accountTwo };

        Contact legalRep = new Contact(
            AccountId = accountOne.Id,
            LastName = 'Perez',
            FirstName = 'Ana',
            Cargo_en_la_Empresa__c = 'Representante Legal',
            Email = 'ana@test.com',
            MobilePhone = '+56911111111'
        );
        Contact otherContact = new Contact(
            AccountId = accountOne.Id,
            LastName = 'Diaz',
            FirstName = 'Mario'
        );
        Contact foreignContact = new Contact(
            AccountId = accountTwo.Id,
            LastName = 'Fuera',
            FirstName = 'Lucia',
            Cargo_en_la_Empresa__c = 'Representante Legal'
        );
        insert new List<Contact>{ legalRep, otherContact, foreignContact };

        Test.startTest();
        List<ICBFS_FlowLookupContactoCuentaController.LookupResult> results =
            ICBFS_FlowLookupContactoCuentaController.searchContactsByAccount(accountOne.Id, 'an', 10);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(legalRep.Id, results[0].id);
        System.assert(results[0].label.contains('Representante Legal'));
        System.assertEquals('Ana Perez', results[0].name);
        System.assertEquals('Representante Legal', results[0].role);
        System.assertEquals('ana@test.com', results[0].email);
        System.assertEquals('+56911111111', results[0].mobilePhone);
    }

    @IsTest
    static void searchContactsByAccount_returnsSeedListWhenSearchBlank() {
        Account accountRecord = new Account(Name = 'Cuenta Semilla');
        insert accountRecord;

        insert new Contact(AccountId = accountRecord.Id, LastName = 'Lopez', FirstName = 'Pia');

        Test.startTest();
        List<ICBFS_FlowLookupContactoCuentaController.LookupResult> results =
            ICBFS_FlowLookupContactoCuentaController.searchContactsByAccount(accountRecord.Id, '', 10);
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @IsTest
    static void searchContactsByAccount_returnsEmptyWhenAccountHasNoContacts() {
        Account accountRecord = new Account(Name = 'Cuenta Vacia');
        insert accountRecord;

        Test.startTest();
        List<ICBFS_FlowLookupContactoCuentaController.LookupResult> results =
            ICBFS_FlowLookupContactoCuentaController.searchContactsByAccount(accountRecord.Id, '', 50);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}