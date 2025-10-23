public without sharing class TestUtils {
    public static void makeTestData(){
        Comuna__c comuna = new Comuna__c(
            Name = 'PROVIDENCIA',
            Condici_n_de_expedici_n__c = 'SN',
            Incoterms__c = 'SN',
            Region__c = '13',
            RegionCompleta__c = '13 - Región Metropolitana'
        );
        insert comuna;

        Account testAccount = new Account(
            Name = 'Test Account',
            //Phone = '123-456-7890',
            Sucursal__c = 'S001 - Suc Santiago',
            Centro_de_Abastecimiento__c = 'FS00 - Santiago Maulén',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Negocio').getRecordTypeId(),
            Nombre_de_contacto__c = 'Juan Carlos Del Valle',
            Email__c = 'testaccount@test.com',
            ShippingStreet = 'Calle Los Leones',
            ShippingCity = 'Temblayork',
            BillingStreet = 'Calle Los Leones',
            BillingCity = 'Temblayork',
            RUT__c = '77086752-5',
            Region_Despacho__c = '13 - Región Metropolitana',
            Region__c = '13 - Región Metropolitana',
            Comuna_Facturaci_n__c = comuna.Id,
            Comuna_Despacho__c = comuna.Id
        );
        insert testAccount;

        // Create a Custom Pricebook
        Pricebook2 customPricebook = new Pricebook2(
            Name = 'Precios S001',
            IsActive = true
        );
        insert customPricebook;
        
        // Crear Categoria
        Categoria__c categoria = new Categoria__c(
            Name = 'Categoria Test',
            Descripcion__c = 'Categoria Test'
        );
        insert categoria;

        // Crear Familia
        Familia__c familia = new Familia__c(
            Name = 'FS342 TEST',
            Descripcion__c = 'FS342 TEST'
        );
        insert familia;

        // Crear UMV
        Unidad_de_Medida__c umv = new Unidad_de_Medida__c(
            Name = 'Unidad de Medida Test ' + String.valueOf(Datetime.now().getTime()).right(6)
            //Name = 'PFTest'
        );
        insert umv;
        System.debug('UMV creada***: ' + umv);

        // Crear Productos
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < 30; i++) {
            String codigo = i + '00000000';
            Product2 product = new Product2(
                Name = 'Test Product ' + i,
                IsActive = true,
                Categoria__c = categoria.Id,
                Codigo_Identificador__c = codigo + 'PF',
                Codigo__c = codigo,
                TextoUMV__c = 'PF',
                Descuento_Autonomo_SubGerente__c = 50,
                Descuento_Autonomo_de_Asesor__c = 7.5,
                Descuento_Autonomo_de_Mediocampo__c = 10.5,
                Familia__c = familia.Id,
                Marca__c = 'ACME',
                Peso__c = 350,
                Sub_gerente_de_categoria_responsable__c = 'F8 María de los Ángeles Quiróz',
                Temperatura__c = 'Seco',
                UMV__c = umv.Id,
                Fecha_maxima_de_descuento__c = Date.today().addMonths(1)
            );
            products.add(product);
        }
        insert products;

        // Create Pricebook Entries for both Standard and Custom Pricebooks
        List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
        List<PricebookEntry> standardPricebookEntries = new List<PricebookEntry>();
            for (Product2 product : products) {
                // Pricebook Entry for Standard Pricebook
                PricebookEntry standardPbe = new PricebookEntry(
                    Pricebook2Id = Test.getStandardPricebookId(),
                    Product2Id = product.Id,
                    UnitPrice = Math.round(Math.random() * 100 + 50), // Random price between 50 and 150
                    IsActive = false
                );
                standardPricebookEntries.add(standardPbe);
        
                // Pricebook Entry for Custom Pricebook
                PricebookEntry customPbe = new PricebookEntry(
                    Pricebook2Id = customPricebook.Id,
                    Product2Id = product.Id,
                    UnitPrice = Math.round(Math.random() * 100 + 50), // Random price between 50 and 150
                    IsActive = true
                );
                pricebookEntries.add(customPbe);
            }
        insert standardPricebookEntries;
        insert pricebookEntries;

        if (!pricebookEntries.isEmpty()) {
            Integer toFlip = Math.min(2, pricebookEntries.size());
            List<PricebookEntry> toUpdate = new List<PricebookEntry>();
            for (Integer j = 0; j < toFlip; j++) {
                PricebookEntry p = pricebookEntries[j];
                p.IsActive = false;
                toUpdate.add(p);
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        }

        // Create Descuento_Cliente__c records
        List<Descuento_Cliente__c> descuentos = new List<Descuento_Cliente__c>();
        for (Integer i = 0; i < 15; i++) {
            Product2 relatedProduct = products[i];
            PricebookEntry relatedPricebookEntry = pricebookEntries[i];

            Descuento_Cliente__c descuento = new Descuento_Cliente__c(
                Es_recargo__c = true,
                Descuento_gestionado__c = 15,
                Fecha_desde__c = Date.today().addDays(-10),
                Fecha_hasta__c = Date.today().addDays(60),
                Producto__c = relatedProduct.Id,
                Cliente__c = testAccount.Id
            );
            descuentos.add(descuento);
        }
        insert descuentos;

        // Create Costo__c records
        List<Costo__c> costos = new List<Costo__c>();
        for (Product2 product : products) {
            Costo__c costo = new Costo__c(
                CostoProducto__c = 500,
                Codigo_del_Producto__c = product.Id,
                Centro_de_Abastecimiento__c = 'FS00',
                TextoUMV__c = product.TextoUMV__c,
                TextoSKU__c = product.Codigo__c
            );
            costos.add(costo);
        }
        insert costos;

        // Create Relacion_Rappel_Detalle__c records
        List<Rappel__c> rappels = new List<Rappel__c>();
        for (Integer i = 0; i < 10; i++) {
            Rappel__c rappelDetalle = new Rappel__c(
                Cliente__c = testAccount.Id,
                Product__c = products[i].Id,
                Rappel__c = 5 + i,
                Fecha_Vigencia_Desde__c = Date.today().addDays(-20),
                Fecha_Vigencia_Hasta__c = Date.today().addDays(20)
            );
            rappels.add(rappelDetalle);
        }
        insert rappels;

        // Create Venta__c records
        List<Venta__c> ventas = new List<Venta__c>();
        for (Integer i = 0; i < 10; i++) {
            Venta__c venta = new Venta__c(
                Cliente__c = testAccount.Id,
                Fecha_de_Venta__c = Date.today().addDays(-5)
            );
            ventas.add(venta);
        }
        insert ventas;

        // Create Detalle__c records and associate related records
        List<Detalle__c> detalles = new List<Detalle__c>();
        for (Integer i = 0; i < 10; i++) {
            Product2 product = products[i];
            PricebookEntry pricebookEntry = pricebookEntries[i];
            Descuento_Cliente__c descuento = descuentos[i];
            Costo__c costo = costos[i];
            Rappel__c rappel = rappels[i];
            Venta__c venta = ventas[i];

            Detalle__c detalle = new Detalle__c(
                SKU__c = product.Codigo__c,
                Unidad_de_Medida__c = product.TextoUMV__c,
                Descripcion__c = 'Detalle description ' + i,
                Valor_Neto__c = 100,
                Margen_Producto__c = 20 + i,
                Descuento_Cliente__c = descuento.Id,
                PrecioId__c = pricebookEntry.Id,
                Margen_de_Contribucion_por_Kilo__c = 10 + i,
                Producto__c = product.Id,
                costoId__c = costo.Id,
                Precio_Final__c = 200 + i,
                Precio_Cliente_Neto__c = 180 + i,
                Porcentaje_de_Rappel__c = 5 + i,
                Relacion_Rappel_Detalle__c = rappel.Id,
                Venta__c = venta.Id
            );
            detalles.add(detalle);
        }
        insert detalles;

        // Create Detalle__c records without Descuento
        List<Detalle__c> detallesSinDescuento = new List<Detalle__c>();
        for (Integer i = 15; i < 20; i++) {
            Product2 product = products[i];
            PricebookEntry pricebookEntry = pricebookEntries[i];
            //Costo__c costo = costos[i];
            //Venta__c venta = ventas[i];

            Detalle__c detalle = new Detalle__c(
                SKU__c = product.Codigo__c,
                Unidad_de_Medida__c = product.TextoUMV__c,
                Descripcion__c = 'Detalle description ' + i,
                Valor_Neto__c = 100 + i,
                Margen_Producto__c = 20 + i,
                PrecioId__c = pricebookEntry.Id,
                Margen_de_Contribucion_por_Kilo__c = 10 + i,
                Producto__c = product.Id,
                //costoId__c = costo.Id,
                Precio_Final__c = 200 + i,
                Precio_Cliente_Neto__c = 180 + i,
                Porcentaje_de_Rappel__c = 5 + i
                //Relacion_Rappel_Detalle__c = rappel.Id,
                //Venta__c = venta.Id
            );
            detallesSinDescuento.add(detalle);
        }
        insert detallesSinDescuento;
    }
}