@IsTest
private class seidor_DetalleFacturaSelectorTest {

    private static Id rtCuenta(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    @TestSetup
    static void setup() {
        Account negocio = new Account(Name = 'Cliente Negocio Test', RecordTypeId = rtCuenta('Negocio'));
        Account otraCuenta = new Account(Name = 'Otra Cuenta Test', RecordTypeId = rtCuenta('Negocio'));
        insert new List<Account>{ negocio, otraCuenta };

        Account sucursal = new Account(Name = 'Sucursal Test', RecordTypeId = rtCuenta('Sucursal'), ParentId = negocio.Id);
        insert sucursal;

        Facturas__c factura = new Facturas__c(
            
            Numero_de_Factura__c = '999001',
            Cliente__c = negocio.Id,
            Sucursal__c = sucursal.Id
        );
        Facturas__c facturaSinDetalle = new Facturas__c(Numero_de_Factura__c = '999002', Cliente__c = negocio.Id);
        insert new List<Facturas__c>{ factura, facturaSinDetalle };

        insert new List<Detalle_Factura__c>{
            new Detalle_Factura__c(Factura__c = factura.Id, SKU__c = 'SKU-KG', Cantidad__c = 2, Peso_neto__c = 20.5,
                Conversion_UM__c = 1, Unidad_de_Medida__c = 'KG', Valor_Neto__c = 41000, valore_Rappel__c = 0, Posicion__c = 10),
            new Detalle_Factura__c(Factura__c = factura.Id, SKU__c = 'SKU-CJ', Cantidad__c = 5, Peso_neto__c = 0,
                Conversion_UM__c = 12, Unidad_de_Medida__c = 'CJ', Valor_Neto__c = 60000, valore_Rappel__c = 1000, Posicion__c = 20)
        };

        insert new Case(Subject = 'Caso test detalle factura', AccountId = negocio.Id, Factura__c = factura.Id);
    }

    private static Facturas__c factura(String name) {
        return [SELECT Id, Cliente__c, Sucursal__c FROM Facturas__c WHERE Numero_de_Factura__c = :name LIMIT 1];
    }

    @IsTest
    static void porFacturaYCuenta() {
        Facturas__c f = factura('999001');
        Test.startTest();
        seidor_DetalleFacturaSelector.Result res = seidor_DetalleFacturaSelector.obtenerDetalles(null, f.Id, f.Cliente__c, null);
        Test.stopTest();

        Assert.areEqual(f.Id, res.facturaId);
        Assert.areEqual(2, res.cantidadDetalles);
        Assert.isTrue(res.tieneDetalles);
        Assert.areEqual('SKU-KG', res.detalles[0].SKU__c, 'Debe ordenar por Posicion__c');
    }

    @IsTest
    static void porCasoSinFactura() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        Test.startTest();
        List<seidor_DetalleFacturaSelector.Result> res = seidor_DetalleFacturaSelector.obtenerDetallesInvocable(
            new List<seidor_DetalleFacturaSelector.Request>{ request(c.Id, null, null, null) }
        );
        Test.stopTest();

        Assert.areEqual(factura('999001').Id, res[0].facturaId);
        Assert.areEqual(2, res[0].cantidadDetalles);
        Assert.isNull(res[0].mensajeError);
    }

    @IsTest
    static void porSucursalYCuentaPadre() {
        Facturas__c f = factura('999001');
        seidor_DetalleFacturaSelector.Result porSucursal = seidor_DetalleFacturaSelector.resolver(null, f.Id, null, f.Sucursal__c);
        seidor_DetalleFacturaSelector.Result porPadre = seidor_DetalleFacturaSelector.resolver(null, f.Id, f.Sucursal__c, null);

        Assert.isNull(porSucursal.mensajeError);
        Assert.areEqual(2, porSucursal.cantidadDetalles);
        Assert.isNull(porPadre.mensajeError, 'La sucursal también es válida como cuenta');
    }

    @IsTest
    static void facturaSinDetalles() {
        Facturas__c f = factura('999002');
        seidor_DetalleFacturaSelector.Result res = seidor_DetalleFacturaSelector.resolver(null, f.Id, f.Cliente__c, null);
        Assert.isNull(res.mensajeError);
        Assert.isFalse(res.tieneDetalles);
        Assert.areEqual(0, res.cantidadDetalles);
    }

    @IsTest
    static void validaciones() {
        Facturas__c f = factura('999001');
        Id otraCuenta = [SELECT Id FROM Account WHERE Name = 'Otra Cuenta Test' LIMIT 1].Id;

        Assert.areEqual(seidor_DetalleFacturaSelector.MSG_SIN_FACTURA,
            seidor_DetalleFacturaSelector.resolver(null, null, null, null).mensajeError);
        Assert.areEqual(seidor_DetalleFacturaSelector.MSG_FACTURA_OTRA_CUENTA,
            seidor_DetalleFacturaSelector.resolver(null, f.Id, otraCuenta, null).mensajeError);
        Assert.areEqual(seidor_DetalleFacturaSelector.MSG_FACTURA_OTRA_SUCURSAL,
            seidor_DetalleFacturaSelector.resolver(null, f.Id, null, otraCuenta).mensajeError);

        Id facturaInexistente = f.Id;
        delete [SELECT Id FROM Case];
        delete new Facturas__c(Id = facturaInexistente);
        Assert.areEqual(seidor_DetalleFacturaSelector.MSG_FACTURA_NO_EXISTE,
            seidor_DetalleFacturaSelector.resolver(null, facturaInexistente, null, null).mensajeError);
    }

    @IsTest
    static void lwcLanzaExcepcionConMensaje() {
        try {
            seidor_DetalleFacturaSelector.obtenerDetalles(null, null, null, null);
            Assert.fail('Debió lanzar AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.areEqual(seidor_DetalleFacturaSelector.MSG_SIN_FACTURA, e.getMessage());
        }
    }

    private static seidor_DetalleFacturaSelector.Request request(Id caseId, Id facturaId, Id accountId, Id sucursalId) {
        seidor_DetalleFacturaSelector.Request r = new seidor_DetalleFacturaSelector.Request();
        r.caseId = caseId;
        r.facturaId = facturaId;
        r.accountId = accountId;
        r.sucursalId = sucursalId;
        return r;
    }
}