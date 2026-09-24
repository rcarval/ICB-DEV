@IsTest
private class ICBFD_FacturaDetalleInsertTest {

    @IsTest
    static void test_insert_factura_y_detalle_con_cuenta_base() {
        Account cuenta = new Account(
            Name = 'Cuenta Base Factura',
            Cliente_Despacho__c = 'FS70000-1'
        );
        insert cuenta;

        Domicilio_de_Cliente__c domicilio = new Domicilio_de_Cliente__c(
            Cliente__c = cuenta.Id,
            Cliente_Despacho__c = 'FS70000-1'
        );
        insert domicilio;

        Facturas__c factura = new Facturas__c(
            Cliente__c = cuenta.Id,
            Direccion__c = 'FS70000-1'
        );
        insert factura;

        Product2 producto = new Product2(
            Name = 'Producto Test Factura 1',
            IsActive = true,
            Codigo__c = '70000001'
        );
        insert producto;

        Detalle_Factura__c detalle = new Detalle_Factura__c(
            Factura__c = factura.Id,
            Product__c = producto.Id,
            SKU__c = 'SKU-70000',
            Unidad_de_Medida__c = 'UND',
            Descripcion__c = 'Detalle base',
            Valor_Neto__c = 1000
        );
        insert detalle;

        Facturas__c facturaDb = [
            SELECT Id, Cliente__c, Domicilio_Cliente__c, Sucursal__c,
                (SELECT Id, Factura__c, Product__c, SKU__c, Valor_Neto__c FROM Detalles_Facturas__r)
            FROM Facturas__c
            WHERE Id = :factura.Id
        ];

        System.assertEquals(cuenta.Id, facturaDb.Cliente__c, 'La factura debe mantener la cuenta cliente');
        System.assertEquals(domicilio.Id, facturaDb.Domicilio_Cliente__c, 'La factura debe resolver el domicilio');
        System.assertEquals(cuenta.Id, facturaDb.Sucursal__c, 'La factura debe usar la misma cuenta como sucursal cuando el despacho pertenece a la cuenta base');
        System.assertEquals(1, facturaDb.Detalles_Facturas__r.size(), 'Debe insertar un detalle factura');
        System.assertEquals(detalle.Id, facturaDb.Detalles_Facturas__r[0].Id, 'Debe recuperar el detalle insertado');
    }

    @IsTest
    static void test_insert_factura_y_detalles_con_sucursal_hija() {
        Id negocioRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Negocio').getRecordTypeId();
        Id sucursalRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Sucursal').getRecordTypeId();

        Account matriz = new Account(
            Name = 'Cuenta Matriz Factura',
            RecordTypeId = negocioRtId,
            Cliente_Despacho__c = 'FS70001-1',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert matriz;

        Account sucursal = new Account(
            Name = 'Sucursal Factura',
            RecordTypeId = sucursalRtId,
            ParentId = matriz.Id,
            Cliente_Despacho__c = 'FS70001-1',
            Sucursal__c = 'S001 - Suc Santiago'
        );
        insert sucursal;

        Domicilio_de_Cliente__c domicilio = new Domicilio_de_Cliente__c(
            Cliente__c = matriz.Id,
            Cliente_Despacho__c = 'FS70001-1'
        );
        insert domicilio;

        Facturas__c factura = new Facturas__c(
            Cliente__c = matriz.Id,
            Direccion__c = 'FS70001-1'
        );
        insert factura;

        Product2 productoA = new Product2(
            Name = 'Producto Test Factura 2A',
            IsActive = true,
            Codigo__c = '70001001'
        );
        Product2 productoB = new Product2(
            Name = 'Producto Test Factura 2B',
            IsActive = true,
            Codigo__c = '70001002'
        );
        insert new List<Product2>{ productoA, productoB };

        List<Detalle_Factura__c> detalles = new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c = factura.Id,
                Product__c = productoA.Id,
                SKU__c = 'SKU-70001-A',
                Unidad_de_Medida__c = 'UND',
                Descripcion__c = 'Detalle A',
                Valor_Neto__c = 2500
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id,
                Product__c = productoB.Id,
                SKU__c = 'SKU-70001-B',
                Unidad_de_Medida__c = 'UND',
                Descripcion__c = 'Detalle B',
                Valor_Neto__c = 3500
            )
        };
        insert detalles;

        Facturas__c facturaDb = [
            SELECT Id, Cliente__c, Domicilio_Cliente__c, Sucursal__c,
                (SELECT Id, Factura__c, Product__c, SKU__c, Valor_Neto__c FROM Detalles_Facturas__r ORDER BY SKU__c)
            FROM Facturas__c
            WHERE Id = :factura.Id
        ];

        System.assertEquals(matriz.Id, facturaDb.Cliente__c, 'La factura debe mantener la cuenta matriz en Cliente__c');
        System.assertEquals(domicilio.Id, facturaDb.Domicilio_Cliente__c, 'La factura debe resolver el domicilio histórico');
        System.assertEquals(sucursal.Id, facturaDb.Sucursal__c, 'La factura debe apuntar a la sucursal hija correcta');
        System.assertEquals(2, facturaDb.Detalles_Facturas__r.size(), 'Debe insertar dos detalles factura');
        System.assertEquals('SKU-70001-A', facturaDb.Detalles_Facturas__r[0].SKU__c, 'Debe conservar el primer detalle');
        System.assertEquals('SKU-70001-B', facturaDb.Detalles_Facturas__r[1].SKU__c, 'Debe conservar el segundo detalle');
    }
}