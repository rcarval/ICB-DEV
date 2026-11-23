public with sharing class ICBFS_AccountGeocodeNullQueueable implements Queueable, Database.AllowsCallouts {
    private static final String SUCURSAL_RECORD_TYPE = 'Sucursal';
    private final Set<Id> accountIds;

    public ICBFS_AccountGeocodeNullQueueable(Set<Id> accountIds) {
        this.accountIds = accountIds == null ? new Set<Id>() : new Set<Id>(accountIds);
    }

    public void execute(QueueableContext context) {
        if (accountIds.isEmpty()) {
            return;
        }

        List<Account> accounts = [
            SELECT Id,
                   RecordTypeId, RecordType.DeveloperName,
                   ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
                   ShippingLatitude, ShippingLongitude,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                   BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id IN :accountIds
        ];

        for (Account acc : accounts) {
            if (shouldGeocodeShipping(acc)) {
                geocodeAndUpdate(acc.Id, 'SHIPPING');
            }
            if (shouldGeocodeBilling(acc)) {
                geocodeAndUpdate(acc.Id, 'BILLING');
            }
        }
    }

    private static Boolean shouldGeocodeShipping(Account acc) {
        return acc != null
            && hasAddress(acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, acc.ShippingPostalCode, acc.ShippingCountry)
            && (acc.ShippingLatitude == null || acc.ShippingLongitude == null);
    }

    private static Boolean shouldGeocodeBilling(Account acc) {
        return acc != null
            && !isSucursal(acc)
            && hasAddress(acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingPostalCode, acc.BillingCountry)
            && (acc.BillingLatitude == null || acc.BillingLongitude == null);
    }

    public static Boolean isSucursal(Account acc) {
        return acc != null
            && acc.RecordType != null
            && acc.RecordType.DeveloperName == SUCURSAL_RECORD_TYPE;
    }

    public static Boolean needsShippingGeocode(Account acc) {
        return acc != null
            && acc.Id != null
            && hasAddress(acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, acc.ShippingPostalCode, acc.ShippingCountry)
            && (acc.ShippingLatitude == null || acc.ShippingLongitude == null);
    }

    public static Boolean needsBillingGeocode(Account acc) {
        return acc != null
            && acc.Id != null
            && !isSucursal(acc)
            && hasAddress(acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingPostalCode, acc.BillingCountry)
            && (acc.BillingLatitude == null || acc.BillingLongitude == null);
    }

    private static Boolean hasAddress(String street, String city, String state, String postalCode, String country) {
        return !String.isBlank(street)
            && !String.isBlank(city)
            && !String.isBlank(country);
    }

    public static Boolean geocodeAndUpdate(Id accountId, String targetType) {
        ICBFS_GeocodeFromAccountAddress.GeocodeRequest req = new ICBFS_GeocodeFromAccountAddress.GeocodeRequest();
        req.accountId = accountId;
        req.targetType = targetType;

        List<ICBFS_GeocodeFromAccountAddress.GeocodeResponse> geocodeResults =
            ICBFS_GeocodeFromAccountAddress.geocode(new List<ICBFS_GeocodeFromAccountAddress.GeocodeRequest>{ req });
        if (geocodeResults.isEmpty()) {
            return false;
        }

        ICBFS_GeocodeFromAccountAddress.GeocodeResponse geo = geocodeResults[0];
        if (geo == null || geo.latitude == null || geo.longitude == null) {
            return false;
        }

        ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest updateReq =
            new ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest();
        updateReq.accountId = accountId;
        updateReq.latitude = geo.latitude;
        updateReq.longitude = geo.longitude;
        updateReq.targetType = targetType;

        ICBFS_GeocodeUpdateAccount.applyGeocodingToAccounts(
            new List<ICBFS_GeocodeUpdateAccount.GeocodeAccountUpdateRequest>{ updateReq }
        );
        return true;
    }
}