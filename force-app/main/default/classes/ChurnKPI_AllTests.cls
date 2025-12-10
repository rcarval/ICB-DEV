@IsTest
private class ChurnKPI_AllTests {

    private static User mkUser(String alias){
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        User u = new User(
            ProfileId = p.Id,
            Username = alias + DateTime.now().getTime() + '@t.icb',
            LastName = 'T',
            Email = alias + '@t.icb',
            Alias = alias.left(8),
            CommunityNickname = alias + DateTime.now().getTime(),
            TimeZoneSidKey = 'America/Santiago',
            LocaleSidKey = 'es_CL',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es'
        );
        insert u;
        return u;
    }

    @testSetup
    static void data(){
        User ownerU = mkUser('schedJobU');

        List<Account> accts = new List<Account>{
            new Account(Name='A1', OwnerId=ownerU.Id),
            new Account(Name='A2', OwnerId=ownerU.Id)
        };
        insert accts;

        Date lm = Date.today().addMonths(-1);
        Date tm = Date.today();

        insert new Facturas__c(Cliente__c = accts[0].Id, Fecha_de_Documento__c = lm);
        insert new Facturas__c(Cliente__c = accts[0].Id, Fecha_de_Documento__c = tm);

        insert new Facturas__c(Cliente__c = accts[1].Id, Fecha_de_Documento__c = lm);
    }

    @IsTest
    static void schedulable_runs_once_and_creates(){
        Test.startTest();
        System.schedule('UT-KPI', '0 0 0 1 1 ? 2099', new ChurnKPI_DailyJob());
        Test.stopTest();

        Integer kpis = [
            SELECT COUNT() FROM SalesKPI__c WHERE AsOfDate__c = :Date.today()
        ];
        System.assert(kpis > 0, 'El job programado debió generar al menos 1 KPI');
    }
}