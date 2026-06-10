@isTest
private class ICBFS_GeocodeUpdateAccountTest {

    @isTest
    static void testUpdateShippingCoordinatesSuccess() {
        Account acc = new Account(Name = 'Acc shipping test');
        insert acc;

        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest req =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        req.accountId = acc.Id;
        req.latitude = -33.45;
        req.longitude = -70.66;
        req.targetType = 'SHIPPING';

        Test.startTest();
        List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateResult> outRes =
            ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
                new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, outRes.size());
        System.assertEquals(true, outRes[0].success);

        Account updated = [SELECT ShippingLatitude, ShippingLongitude FROM Account WHERE Id = :acc.Id];
        System.assertEquals((Decimal)-33.45, updated.ShippingLatitude);
        System.assertEquals((Decimal)-70.66, updated.ShippingLongitude);
    }

    @isTest
    static void testMissingAccountIdReturnsError() {
        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest req =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        req.latitude = -33.45;
        req.longitude = -70.66;

        Test.startTest();
        List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateResult> outRes =
            ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
                new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, outRes.size());
        System.assertEquals(false, outRes[0].success);
        System.assert(outRes[0].errorMessage.contains('AccountId'));
    }

    @isTest
    static void testMissingCoordinatesReturnsError() {
        Account acc = new Account(Name = 'Acc coords test');
        insert acc;

        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest req =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        req.accountId = acc.Id;
        req.targetType = 'BILLING';

        Test.startTest();
        List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateResult> outRes =
            ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
                new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, outRes.size());
        System.assertEquals(false, outRes[0].success);
        System.assert(outRes[0].errorMessage.contains('Latitud y longitud'));
    }

    @isTest
    static void testBillingPathOrBillingFieldValidation() {
        Account acc = new Account(Name = 'Acc billing test');
        insert acc;

        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest req =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        req.accountId = acc.Id;
        req.latitude = -33.11;
        req.longitude = -70.11;
        req.targetType = 'BILLING';

        Test.startTest();
        List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateResult> outRes =
            ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
                new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, outRes.size());
        System.assertEquals(acc.Id, outRes[0].accountId);
        if (outRes[0].success == false) {
            System.assert(outRes[0].errorMessage.contains('BillingLatitude') || outRes[0].errorMessage.contains('BillingLongitude'));
        }
    }

    @isTest
    static void testInvalidAccountAndNullRequest() {
        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest invalidReq =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        invalidReq.accountId = '001000000000000AAA';
        invalidReq.latitude = -30.0;
        invalidReq.longitude = -70.0;

        Test.startTest();
        List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateResult> outRes =
            ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
                new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ null, invalidReq }
            );
        Test.stopTest();

        System.assertEquals(2, outRes.size());
        System.assertEquals(false, outRes[0].success);
        System.assert(outRes[0].errorMessage.contains('Request nulo'));
        System.assertEquals(false, outRes[1].success);
        System.assertNotEquals(null, outRes[1].errorMessage);
    }
}