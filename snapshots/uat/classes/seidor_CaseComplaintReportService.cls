public with sharing class seidor_CaseComplaintReportService {

    public Case caseRecord { get; set; }

    public seidor_CaseComplaintReportService() {
        Id caseId = ApexPages.currentPage().getParameters().get('id');
        if (caseId != null) {
            caseRecord = [
                SELECT Id, CaseNumber, Motivo__c, Investigacion__c,
                       Acciones_Correctivas__c, Acciones_Preventivas__c, Conclusiones__c,
                       Product.Name, Marca__c, AccountId, Account.Name
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
        }
    }

    public class ResultadoPDF {
        @InvocableVariable(label='Mensaje de estado' description='OK o mensaje de error')
        public String mensaje;

        @InvocableVariable(label='Id de ContentVersion' description='Id del ContentVersion generado para adjuntar a un correo')
        public Id contentVersionId;

        public ResultadoPDF(String mensaje, Id contentVersionId) {
            this.mensaje = mensaje;
            this.contentVersionId = contentVersionId;
        }
    }

    @InvocableMethod(label='Generar PDF Reclamo' description='Genera y adjunta el PDF de informe de reclamo al caso. Retorna el Id del ContentVersion.')
    public static List<ResultadoPDF> generarPDF(List<Id> caseIds) {
        List<ResultadoPDF> resultados = new List<ResultadoPDF>();

        for (Id caseId : caseIds) {
            try {
                if (caseId == null) {
                    resultados.add(new ResultadoPDF('ERROR: El Id del caso es obligatorio.', null));
                    continue;
                }

                PageReference pdfPage = Page.seidor_CaseComplaintReportPDF;
                pdfPage.getParameters().put('id', caseId);

                Blob pdfContent;
                if (Test.isRunningTest()) {
                    pdfContent = Blob.valueOf('TEST PDF');
                } else {
                    pdfContent = pdfPage.getContentAsPDF();
                }

                Case c = [
                    SELECT Id, CaseNumber
                    FROM Case
                    WHERE Id = :caseId
                    LIMIT 1
                ];

                ContentVersion cv = new ContentVersion();
                cv.Title = 'Informe_Reclamo_' + c.CaseNumber;
                cv.PathOnClient = 'Informe_Reclamo_' + c.CaseNumber + '.pdf';
                cv.VersionData = pdfContent;
                insert cv;

                ContentVersion inserted = [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                    LIMIT 1
                ];

                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = inserted.ContentDocumentId;
                link.LinkedEntityId = caseId;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                insert link;

                resultados.add(new ResultadoPDF('OK: PDF generado y adjuntado correctamente.', inserted.Id));

            } catch (Exception e) {
                resultados.add(new ResultadoPDF('ERROR: ' + e.getMessage(), null));
            }
        }

        return resultados;
    }
}