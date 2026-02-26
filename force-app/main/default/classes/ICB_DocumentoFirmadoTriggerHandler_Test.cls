/**********************************************************************************
 * ICB_DocumentoFirmadoTriggerHandler_Test - Tests del handler DocumentoFirmado__e. SEIDOR - RCG
 **********************************************************************************/
@IsTest
public class ICB_DocumentoFirmadoTriggerHandler_Test {

    @TestSetup
    static void setup() {
        Contrato_Digital__c c = new Contrato_Digital__c();
        c.Contrato_ID__c = 'FD-PE-TEST-001';
        c.Estado__c = 'Enviado';
        insert c;
    }

    @IsTest
    static void testOnAfterInsert_actualizaContrato() {
        List<DocumentoFirmado__e> events = new List<DocumentoFirmado__e>();
        DocumentoFirmado__e e = new DocumentoFirmado__e();
        e.ContratoId__c = 'FD-PE-TEST-001';
        e.Estado__c = 'Firmado';
        e.ExternalTransactionId__c = 'TF-EXT-123';
        e.FechaFirma__c = DateTime.now();
        e.PdfFirmadoUrl__c = 'https://ejemplo.com/firmado.pdf';
        e.RawPayload__c = '{"test":true}';
        events.add(e);

        Test.startTest();
        ICB_DocumentoFirmadoTriggerHandler.onAfterInsert(events);
        Test.stopTest();

        Contrato_Digital__c updated = [SELECT Id, Estado__c, Documento_ID_TuFirma_del__c, PDF_Firmado_URL__c, Fecha_Firma__c FROM Contrato_Digital__c WHERE Contrato_ID__c = 'FD-PE-TEST-001' LIMIT 1];
        System.assertEquals('Firmado', updated.Estado__c, 'Estado__c');
        System.assertEquals('TF-EXT-123', updated.Documento_ID_TuFirma_del__c, 'Documento_ID_TuFirma_del__c');
        System.assertEquals('https://ejemplo.com/firmado.pdf', updated.PDF_Firmado_URL__c, 'PDF_Firmado_URL__c');
        System.assert(updated.Fecha_Firma__c != null, 'Fecha_Firma__c');
        //System.assertEquals('{"test":true}', updated.Raw_Payload__c, 'Raw_Payload__c');
    }

    @IsTest
    static void testOnAfterInsert_contratoNoEncontrado_noFalla() {
        List<DocumentoFirmado__e> events = new List<DocumentoFirmado__e>();
        DocumentoFirmado__e e = new DocumentoFirmado__e();
        e.ContratoId__c = 'NO-EXISTE';
        e.Estado__c = 'Firmado';
        events.add(e);

        Test.startTest();
        ICB_DocumentoFirmadoTriggerHandler.onAfterInsert(events);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Contrato_Digital__c WHERE Contrato_ID__c = 'NO-EXISTE'];
        System.assertEquals(0, count);
    }

    @IsTest
    static void testOnAfterInsert_listaVacia() {
        ICB_DocumentoFirmadoTriggerHandler.onAfterInsert(new List<DocumentoFirmado__e>());
    }

    @IsTest
    static void testOnAfterInsert_contratoIdBlank() {
        List<DocumentoFirmado__e> events = new List<DocumentoFirmado__e>();
        events.add(new DocumentoFirmado__e());
        ICB_DocumentoFirmadoTriggerHandler.onAfterInsert(events);
    }
}
