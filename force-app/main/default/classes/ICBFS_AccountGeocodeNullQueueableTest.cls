@IsTest
private class ICBFS_AccountGeocodeNullQueueableTest {
    private class GeocodeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status":"OK","results":[{"geometry":{"location":{"lat":-33.45,"lng":-70.66}}}]}');
            return res;
        }
    }

    @IsTest
    static void fillsNullShippingAndBillingCoordinates() {
        Test.setMock(HttpCalloutMock.class, new GeocodeMock());

        Account acc = new Account(
            Name = 'Cuenta Geocode Test',
            ShippingStreet = 'El Greco 510',
            ShippingCity = 'Maipu',
            ShippingCountry = 'CL',
            BillingStreet = 'Avenida Apoquindo 3000',
            BillingCity = 'Las Condes',
            BillingCountry = 'CL'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account updated = [
            SELECT ShippingLatitude, ShippingLongitude, BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertNotEquals(null, updated.ShippingLatitude);
        System.assertNotEquals(null, updated.ShippingLongitude);
        System.assertNotEquals(null, updated.BillingLatitude);
        System.assertNotEquals(null, updated.BillingLongitude);
    }

    @IsTest
    static void skipsAccountsWithoutMissingCoordinates() {
        Test.setMock(HttpCalloutMock.class, new GeocodeMock());

        Account acc = new Account(
            Name = 'Cuenta Sin Geocode',
            ShippingStreet = 'Siempre Viva 123',
            ShippingCity = 'Santiago',
            ShippingCountry = 'CL',
            ShippingLatitude = -33.44,
            ShippingLongitude = -70.65
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account updated = [
            SELECT ShippingLatitude, ShippingLongitude, BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(-33.44, updated.ShippingLatitude);
        System.assertEquals(-70.65, updated.ShippingLongitude);
        System.assertEquals(null, updated.BillingLatitude);
        System.assertEquals(null, updated.BillingLongitude);
    }

    @IsTest
    static void rejectsInvalidRutOnInsert() {
        Account acc = new Account(
            Name = 'Cuenta RUT Invalido',
            RUT__c = '12345678-1'
        );

        try {
            insert acc;
            System.assert(false, 'Debio fallar por RUT invalido');
        } catch (DmlException e) {
            System.assert(e.getDmlMessage(0).contains('RUT invalido'), e.getDmlMessage(0));
        }
    }

    @IsTest
    static void rejectsBadRutFormatOnUpdate() {
        Account acc = new Account(
            Name = 'Cuenta RUT Update',
            RUT__c = '12345678-5'
        );
        insert acc;

        acc.RUT__c = '123456785';

        try {
            update acc;
            System.assert(false, 'Debio fallar por formato de RUT');
        } catch (DmlException e) {
            System.assert(e.getDmlMessage(0).contains('Formato de RUT incorrecto'), e.getDmlMessage(0));
        }
    }

    @IsTest
    static void allowsUpdateWhenRutDidNotChange() {
        Account acc = new Account(
            Name = 'Cuenta Sin Cambio RUT',
            RUT__c = '12345678-5'
        );
        insert acc;

        acc.Name = 'Cuenta Sin Cambio RUT Editada';
        update acc;

        Account updated = [
            SELECT Name, RUT__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals('Cuenta Sin Cambio RUT Editada', updated.Name);
        System.assertEquals('12345678-5', updated.RUT__c);
    }

    @IsTest
    static void sucursalOnlyGeocodesShipping() {
        Test.setMock(HttpCalloutMock.class, new GeocodeMock());

        Id sucursalRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Sucursal')
            .getRecordTypeId();

        Account acc = new Account(
            Name = 'Sucursal Solo Despacho',
            RecordTypeId = sucursalRecordTypeId,
            ShippingStreet = 'El Greco 510',
            ShippingCity = 'Maipu',
            ShippingCountry = 'CL',
            BillingStreet = 'Avenida Apoquindo 3000',
            BillingCity = 'Las Condes',
            BillingCountry = 'CL'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account updated = [
            SELECT ShippingLatitude, ShippingLongitude, BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertNotEquals(null, updated.ShippingLatitude);
        System.assertNotEquals(null, updated.ShippingLongitude);
        System.assertEquals(null, updated.BillingLatitude);
        System.assertEquals(null, updated.BillingLongitude);
    }

    @IsTest
    static void skipsIncompleteAddressEvenWhenCoordinatesAreNull() {
        Test.setMock(HttpCalloutMock.class, new GeocodeMock());

        Account acc = new Account(
            Name = 'Cuenta Direccion Incompleta',
            ShippingStreet = 'El Greco 510',
            ShippingCountry = 'CL',
            BillingStreet = 'Avenida Apoquindo 3000',
            BillingCountry = 'CL'
        );

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account updated = [
            SELECT ShippingLatitude, ShippingLongitude, BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals(null, updated.ShippingLatitude);
        System.assertEquals(null, updated.ShippingLongitude);
        System.assertEquals(null, updated.BillingLatitude);
        System.assertEquals(null, updated.BillingLongitude);
    }
}