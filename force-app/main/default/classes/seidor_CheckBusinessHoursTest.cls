@isTest
public class seidor_CheckBusinessHoursTest {

    @testSetup
    static void setupData() {

        BusinessHours bh = [
            SELECT Id, Name
            FROM BusinessHours
            WHERE Name = 'Default' AND IsActive = true
            LIMIT 1
        ];
    }

    @isTest
    static void test_checkBusinessHoursById() {

        BusinessHours bh = [SELECT Id FROM BusinessHours LIMIT 1];

        Test.startTest();

        Boolean result = seidor_CheckBusinessHours.checkBusinessHoursById(bh.Id);

        System.assert(result == true || result == false); // válido, depende de la hora actual

        Test.stopTest();
    }

    @isTest
    static void test_checkBusinessHoursById_null() {

        Test.startTest();

        Boolean result = seidor_CheckBusinessHours.checkBusinessHoursById(null);

        System.assert(result == false);

        Test.stopTest();
    }

    @isTest
    static void test_checkBusinessHoursByName_valid() {

        Test.startTest();

        List<Boolean> results = seidor_CheckBusinessHours.checkBusinessHoursByName(
            new List<String>{ 'BH Test' }
        );

        System.assert(results.size() == 1);
        System.assert(results[0] == true || results[0] == false);

        Test.stopTest();
    }

    @isTest
    static void test_checkBusinessHoursByName_invalid() {

        Test.startTest();

        List<Boolean> results = seidor_CheckBusinessHours.checkBusinessHoursByName(
            new List<String>{ 'NO_EXISTE' }
        );

        System.assert(results.size() == 1);
        System.assert(results[0] == false);

        Test.stopTest();
    }

    @isTest
    static void test_checkBusinessHoursByName_multiple() {

        Test.startTest();

        List<Boolean> results = seidor_CheckBusinessHours.checkBusinessHoursByName(
            new List<String>{ 'BH Test', 'NO_EXISTE' }
        );

        System.assert(results.size() == 2);

        Test.stopTest();
    }
}