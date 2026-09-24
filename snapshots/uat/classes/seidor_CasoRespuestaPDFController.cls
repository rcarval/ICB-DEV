public with sharing class seidor_CasoRespuestaPDFController {

    public Case caso {
        get {
            if (caso == null) {
                Id caseId = ApexPages.currentPage().getParameters().get('id');
                if (caseId != null) {
                    caso = [
                        SELECT Id, CaseNumber, Subject, Investigacion__c,
                               Acciones_Correctivas__c, Acciones_Preventivas__c,
                               Conclusiones__c
                        FROM Case
                        WHERE Id = :caseId
                        LIMIT 1
                    ];
                }
            }
            return caso;
        }
        set;
    }

    public class FlowInput {

        @InvocableVariable(required=true)
        public Id caseId;
    }

    public class FlowOutput {

        @InvocableVariable
        public String message;

        @InvocableVariable
        public Id contentDocumentId;
    }

    @InvocableMethod(
        label='Generar PDF Respuesta Reclamo'
        description='Genera PDF desde Caso y lo adjunta automáticamente'
    )
    public static List<FlowOutput> generarPDF(List<FlowInput> inputs) {

        List<FlowOutput> outputs = new List<FlowOutput>();

        for(FlowInput input : inputs) {

            FlowOutput output = new FlowOutput();

            try {

                Case caso = [
                    SELECT Id,
                           CaseNumber,
                           Subject,
                           Investigacion__c,
                           Acciones_Correctivas__c,
                           Acciones_Preventivas__c,
                           Conclusiones__c
                    FROM Case
                    WHERE Id = :input.caseId
                    LIMIT 1
                ];

                PageReference pdfPage = Page.seidor_PDFResumenCaso;

                pdfPage.getParameters().put('id', caso.Id);

                Blob pdfBlob = pdfPage.getContentAsPDF();

                ContentVersion cv = new ContentVersion();

                cv.Title = 'Respuesta Reclamo - ' + caso.CaseNumber;
                cv.PathOnClient = 'RespuestaReclamo.pdf';
                cv.VersionData = pdfBlob;

                insert cv;

                ContentVersion insertedCV = [
                    SELECT Id,
                           ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                    LIMIT 1
                ];

                ContentDocumentLink cdl = new ContentDocumentLink();

                cdl.LinkedEntityId = caso.Id;
                cdl.ContentDocumentId = insertedCV.ContentDocumentId;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';

                insert cdl;

                output.message = 'PDF generado correctamente';
                output.contentDocumentId = insertedCV.ContentDocumentId;

            } catch(Exception e) {

                output.message = 'Error: ' + e.getMessage();
            }

            outputs.add(output);
        }

        return outputs;
    }
}