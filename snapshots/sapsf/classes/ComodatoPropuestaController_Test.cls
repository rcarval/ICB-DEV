@IsTest
private class ComodatoPropuestaController_Test {

    @IsTest
    static void testControllerLoadsFichaTecnicaAndPreviewHtml() {
        Product2 machine = new Product2(
            Name = 'MAQUINA TEST PDF',
            IsActive = true,
            Codigo__c = 'MTESTPDF',
            Descripci_n_Larga__c =
                'Ideal uso de filtro, duracion 6 meses.\n' +
                'Espacio requerido filtro de agua 50cm\n' +
                'Requiere desague.'
        );
        insert machine;

        Product2 supply = new Product2(
            Name = 'CAFE TEST',
            IsActive = true,
            Codigo__c = 'CTESTPDF'
        );
        insert supply;

        insert new Comodato__c(
            Maquina__c = machine.Id,
            Producto_Asociado__c = supply.Id,
            Tipo_de_Asociacion__c = 'Insumo Mensual',
            Cantidad_Minima_Mensual__c = 6,
            Unidad_de_Medida__c = 'Cajas',
            Precio_Unitario_Neto__c = 64000
        );

        insert new Comodato__c(
            Maquina__c = machine.Id,
            Producto_Asociado__c = supply.Id,
            Tipo_de_Asociacion__c = 'Aporte de Marca',
            Cantidad_Aporte__c = 2,
            Unidad_de_Medida__c = 'Unidades'
        );

        Test.setCurrentPage(Page.ComodatoPropuesta);
        ApexPages.currentPage().getParameters().put('machineId', machine.Id);

        ComodatoPropuestaController ctrl = new ComodatoPropuestaController();

        System.assertEquals(machine.Id, ctrl.machine.Id, 'Debe cargar la maquina');
        System.assertEquals(true, ctrl.getHasFichaTecnica(), 'Debe detectar ficha tecnica');
        System.assert(ctrl.getFichaTecnicaHtml().contains('Ideal uso de filtro'), 'Debe formatear la ficha tecnica');
        System.assertEquals(1, ctrl.serviceLines.size(), 'Debe separar insumos mensuales');
        System.assertEquals(1, ctrl.aporteLines.size(), 'Debe separar aportes');

        String html = ComodatoPropuestaController.getPreviewHtml(machine.Id);
        System.assert(html.contains('FICHA TECNICA'), 'La vista previa debe incluir el titulo');
        System.assert(html.contains('Espacio requerido filtro de agua 50cm'), 'La vista previa debe incluir la ficha tecnica');
        System.assert(html.contains('CAFE TEST'), 'La vista previa debe incluir los insumos');
    }
}