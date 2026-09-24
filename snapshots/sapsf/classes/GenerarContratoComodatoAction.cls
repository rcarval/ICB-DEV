/**********************************************************************************
 * GenerarContratoComodatoAction
 * Camino A (automatico) del proyecto Firma Digital Comodato: genera el PDF final
 * del contrato (ContratoComodatoFinal.page) a partir de la Opportunity y lo envia
 * directo a Firma Digital, reusando ICB_FirmaDigitalFlowAction (mismo servicio que
 * usa hoy el Camino B de subida manual).
 **********************************************************************************/
public with sharing class GenerarContratoComodatoAction {

    public class Input {
        @InvocableVariable(label='Opportunity Id' required=true)
        public Id opportunityId;
    }

    public class Output {
        @InvocableVariable(label='Éxito')
        public Boolean success;
        @InvocableVariable(label='Id Contrato Digital')
        public String contratoDigitalId;
        @InvocableVariable(label='Mensaje de error')
        public String errorMessage;
        @InvocableVariable(label='PDF recuperable en base64')
        public String pdfBase64;
        @InvocableVariable(label='Nombre del PDF recuperable')
        public String pdfFileName;
    }

    @InvocableMethod(label='Generar Contrato Comodato y Enviar a Firma' description='Genera el PDF final del contrato de comodato a partir de la Opportunity y lo envia a Firma Digital' callout=true)
    public static List<Output> generarYEnviar(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        for (Input inp : inputs) {
            outputs.add(procesarUno(inp));
        }
        return outputs;
    }

    private static Output procesarUno(Input inp) {
        Output out = new Output();
        out.success = false;

        if (inp == null || inp.opportunityId == null) {
            out.errorMessage = 'Debe informar una Opportunity válida.';
            return out;
        }

        List<Quote> quotes = [
            SELECT Id, Name
            FROM Quote
            WHERE OpportunityId = :inp.opportunityId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            out.errorMessage = 'La Opportunity no tiene un Presupuesto (Quote) asociado.';
            return out;
        }
        Quote q = quotes[0];

        Blob pdfBlob;
        try {
            PageReference pdfPage = Page.ContratoComodatoFinal;
            pdfPage.getParameters().put('opportunityId', String.valueOf(inp.opportunityId));
            // Misma Quote que se envia a firma digital y que queda en Contrato_Digital__c.
            // Sin esto la pagina volvia a derivarla por su cuenta y podia tomar otra, con
            // ajustes distintos a los del contrato que se firma.
            pdfPage.getParameters().put('quoteId', String.valueOf(q.Id));
            pdfBlob = Test.isRunningTest() ? Blob.valueOf('Test PDF Content') : pdfPage.getContentAsPDF();
        } catch (Exception e) {
            out.errorMessage = 'No se pudo generar el PDF del contrato: ' + e.getMessage();
            return out;
        }

        ICB_FirmaDigitalFlowAction.InvocableInput firmaInput = new ICB_FirmaDigitalFlowAction.InvocableInput();
        firmaInput.quoteId = q.Id;
        firmaInput.pdfBase64 = EncodingUtil.base64Encode(pdfBlob);
        firmaInput.pdfFileName = 'Contrato_Comodato_' + q.Name + '.pdf';
        firmaInput.opportunityId = inp.opportunityId;

        List<ICB_FirmaDigitalFlowAction.InvocableOutput> firmaOutputs =
            ICB_FirmaDigitalFlowAction.enviarPdfAFirmaDigital(new List<ICB_FirmaDigitalFlowAction.InvocableInput>{ firmaInput });

        if (firmaOutputs.isEmpty()) {
            out.errorMessage = 'No se recibió respuesta del envío a Firma Digital.';
            return out;
        }

        ICB_FirmaDigitalFlowAction.InvocableOutput firmaOut = firmaOutputs[0];
        out.success = firmaOut.success;
        out.contratoDigitalId = firmaOut.contratoDigitalId;
        out.errorMessage = firmaOut.errorMessage;
        out.pdfBase64 = firmaOut.pdfBase64;
        out.pdfFileName = firmaOut.pdfFileName;
        return out;
    }
}