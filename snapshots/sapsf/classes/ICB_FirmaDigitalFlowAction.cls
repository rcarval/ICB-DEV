/**********************************************************************************
 * ICB_FirmaDigitalFlowAction
 * Accion invocable desde Flow: envia PDF a TuFirma y crea Contrato_Digital__c.
 * SEIDOR - RCG - Integracion Firma Digital TuFirma/AWS
 **********************************************************************************/
public with sharing class ICB_FirmaDigitalFlowAction {

    // Picklist Estado__c en Contrato_Digital__c debe tener estos valores
    private static final String ESTADO_ENVIADO = 'Enviado';
    private static final String ESTADO_ERROR = 'Rechazado';
    private static final String DEFAULT_FILE_BASENAME = 'CONTRATO_COMODATO';

    public class InvocableInput {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;
        @InvocableVariable(required=true label='PDF en base64')
        public String pdfBase64;
        @InvocableVariable(label='Nombre del archivo PDF')
        public String pdfFileName;
        @InvocableVariable(label='Opportunity Id')
        public String opportunityId;
    }

    public class InvocableOutput {
        @InvocableVariable(label='Exito')
        public Boolean success;
        @InvocableVariable(label='Id Contrato Digital')
        public String contratoDigitalId;
        @InvocableVariable(label='Contrato Id (TuFirma)')
        public String contratoId;
        @InvocableVariable(label='Mensaje de error')
        public String errorMessage;
        @InvocableVariable(label='PDF recuperable en base64')
        public String pdfBase64;
        @InvocableVariable(label='Nombre del PDF recuperable')
        public String pdfFileName;
    }

    @InvocableMethod(label='Enviar PDF a Firma Digital desde Quote' description='Envia PDF a TuFirma y crea Contrato_Digital__c' callout=true)
    public static List<InvocableOutput> enviarPdfAFirmaDigital(List<InvocableInput> inputs) {
        List<InvocableOutput> outputs = new List<InvocableOutput>();
        for (InvocableInput input : inputs) {
            outputs.add(procesarUno(input));
        }
        return outputs;
    }

    private static InvocableOutput procesarUno(InvocableInput input) {
        InvocableOutput out = new InvocableOutput();
        out.success = false;
        out.contratoDigitalId = null;
        out.contratoId = null;
        out.errorMessage = null;

        Id qId = null;
        Quote q = null;
        Blob pdfBody = null;
        String fileName = null;

        if (String.isBlank(input.quoteId) || String.isBlank(input.pdfBase64)) {
            out.errorMessage = 'Quote Id y PDF en base64 son obligatorios.';
            return out;
        }

        try {
            qId = (Id) input.quoteId;

            q = obtenerQuote(qId);
            String base64Raw = quitarPrefijoDataUrl(input.pdfBase64);
            pdfBody = EncodingUtil.base64Decode(base64Raw);
            if (pdfBody == null || pdfBody.size() == 0) {
                out.errorMessage = 'El PDF en base64 esta vacio o no es valido.';
                return out;
            }

            String skuBase = obtenerSkuPrincipal(qId);
            String safeBaseName = normalizarNombreSeguro(String.isNotBlank(skuBase) ? skuBase : DEFAULT_FILE_BASENAME);
            fileName = safeBaseName + '.pdf';
            out.pdfBase64 = base64Raw;
            out.pdfFileName = fileName;

            Contact con = obtenerRepresentanteLegal(q.OpportunityId);
            if (con == null) {
                out.errorMessage = 'No se encontro un Representante Legal con RUT, movil y correo. El PDF sigue disponible para descarga manual.';
                return out;
            }

            String contratoIdExternal = 'FD-' + (String.isNotBlank(q.QuoteNumber) ? q.QuoteNumber : String.valueOf(qId).left(15));

            ICB_FirmaDigitalServiceImpl.UploadRequestDto req = new ICB_FirmaDigitalServiceImpl.UploadRequestDto();
            req.contratoId = contratoIdExternal;
            req.fileName = fileName;
            req.signatureConfig = new ICB_FirmaDigitalServiceImpl.SignatureConfigDto();
            req.signatureConfig.nombre = safeBaseName;
            req.signatureConfig.firmantes = new List<ICB_FirmaDigitalServiceImpl.FirmanteDto>();

            ICB_FirmaDigitalServiceImpl.FirmanteDto firmante = new ICB_FirmaDigitalServiceImpl.FirmanteDto();
            firmante.nombre = con.Name;
            firmante.email = String.isNotBlank(con.Email) ? con.Email : null;
            firmante.rut = String.isNotBlank(con.RUT__c) ? con.RUT__c : con.RUT_Contacto__c;
            firmante.telefono = String.isNotBlank(con.MobilePhone) ? con.MobilePhone : null;
            req.signatureConfig.firmantes.add(firmante);

            ICB_FirmaDigitalServiceImpl.UploadResponseDto uploadRes = ICB_FirmaDigitalServiceImpl.solicitarUploadUrl(req);
            ICB_FirmaDigitalServiceImpl.subirPdfAUploadUrl(uploadRes.uploadUrl, pdfBody);

            Contrato_Digital__c contrato = crearContratoDigital(
                qId, q.OpportunityId, uploadRes.contratoId, null, null, null,
                con.Name, con.Email, con.MobilePhone, DateTime.now(), null, null
            );
            insert contrato;

            update new Quote(Id = qId, Contrato_Digital__c = contrato.Id);
            if (q.OpportunityId != null) {
                update new Opportunity(Id = q.OpportunityId, Contrato_Digital_Firmado__c = contrato.Id);
            }

            out.success = true;
            out.contratoDigitalId = contrato.Id;
            out.contratoId = uploadRes.contratoId;
            ICB_LogIntegracionService.publicarLogsOutboundPendientes();
            return out;

        } catch (ICB_FirmaDigitalServiceImpl.ICB_FirmaDigitalException e) {
            ICB_LogIntegracionService.publicarLogsOutboundPendientes();
            out.errorMessage = 'Firma Digital: ' + e.getMessage();
            try {
                crearContratoDigitalConError((Id) input.quoteId, e.getMessage());
            } catch (Exception ex) {
                out.errorMessage += ' No se pudo registrar el error en Contrato_Digital__c: ' + ex.getMessage();
            }
            return out;
        } catch (Exception e) {
            ICB_LogIntegracionService.publicarLogsOutboundPendientes();
            out.errorMessage = e.getMessage();
            try {
                crearContratoDigitalConError((Id) input.quoteId, e.getMessage());
            } catch (Exception ex) {
                out.errorMessage += ' No se pudo registrar el error en Contrato_Digital__c: ' + ex.getMessage();
            }
            return out;
        }
    }

    private static Quote obtenerQuote(Id quoteId) {
        List<Quote> listQ = [
            SELECT Id, Name, QuoteNumber, ContactId, OpportunityId
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
        return listQ.isEmpty() ? null : listQ[0];
    }

    private static String obtenerSkuPrincipal(Id quoteId) {
        List<QuoteLineItem> lineas = [
            SELECT SKU__c, Product2.ProductCode, Product2.Codigo__c
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            ORDER BY CreatedDate ASC
        ];
        for (QuoteLineItem linea : lineas) {
            if (String.isNotBlank(linea.SKU__c)) {
                return linea.SKU__c;
            }
            if (linea.Product2 != null && String.isNotBlank(linea.Product2.Codigo__c)) {
                return linea.Product2.Codigo__c;
            }
            if (linea.Product2 != null && String.isNotBlank(linea.Product2.ProductCode)) {
                return linea.Product2.ProductCode;
            }
        }
        return null;
    }

    private static String normalizarNombreSeguro(String rawValue) {
        String value = String.isBlank(rawValue) ? DEFAULT_FILE_BASENAME : rawValue.trim();
        String normalized = value
            .replaceAll('[^A-Za-z0-9._-]+', '_')
            .replaceAll('_+', '_')
            .replaceAll('^[._-]+', '')
            .replaceAll('[._-]+$', '');
        return String.isBlank(normalized) ? DEFAULT_FILE_BASENAME : normalized;
    }

    private static Contact obtenerRepresentanteLegal(Id opportunityId) {
        if (opportunityId == null) return null;
        List<OpportunityContactRole> roles = [
            SELECT Role, Contact.Id, Contact.Name, Contact.Email, Contact.MobilePhone, Contact.RUT__c, Contact.RUT_Contacto__c
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND ContactId != null AND IsDeleted = false
            ORDER BY IsPrimary DESC, CreatedDate ASC
        ];
        for (OpportunityContactRole r : roles) {
            if (r.Role == null || !r.Role.toLowerCase().contains('representante legal')) continue;
            if (r.Contact == null) continue;
            String rut = String.isNotBlank(r.Contact.RUT__c) ? r.Contact.RUT__c : r.Contact.RUT_Contacto__c;
            if (String.isBlank(rut) || String.isBlank(r.Contact.MobilePhone) || String.isBlank(r.Contact.Email)) continue;
            return r.Contact;
        }
        for (OpportunityContactRole r : roles) {
            if (r.Contact == null) continue;
            String rut = String.isNotBlank(r.Contact.RUT__c) ? r.Contact.RUT__c : r.Contact.RUT_Contacto__c;
            if (String.isBlank(rut) || String.isBlank(r.Contact.MobilePhone) || String.isBlank(r.Contact.Email)) continue;
            return r.Contact;
        }
        return null;
    }

    private static String quitarPrefijoDataUrl(String base64Input) {
        if (String.isBlank(base64Input)) {
            return base64Input;
        }
        Integer idx = base64Input.indexOf(',');
        if (idx > 0 && base64Input.startsWithIgnoreCase('data:')) {
            return base64Input.substring(idx + 1);
        }
        return base64Input.trim();
    }

    private static Contrato_Digital__c crearContratoDigital(
        Id quoteId, Id opportunityId, String contratoId, String documentoIdTuFirma, String urlFirma, String errorMsg,
        String firmanteNombre, String firmanteEmail, String firmanteTelefono, DateTime fechaEnvio, String pdfFirmadoUrl, String pdfOriginalUrl
    ) {
        Contrato_Digital__c c = new Contrato_Digital__c();
        c.Presupuesto__c = quoteId;
        c.Oportunidad__c = opportunityId;
        c.Estado__c = errorMsg != null ? ESTADO_ERROR : ESTADO_ENVIADO;
        c.Contrato_ID__c = contratoId;
        if (String.isNotBlank(documentoIdTuFirma)) {
            c.Documento_ID_TuFirma_del__c = documentoIdTuFirma;
        }
        if (String.isNotBlank(urlFirma)) {
            c.URL_Firma__c = urlFirma;
        }
        if (String.isNotBlank(errorMsg)) {
            c.Error_Message__c = errorMsg;
        }
        if (String.isNotBlank(firmanteNombre)) {
            c.Firmante_Nombre__c = firmanteNombre;
        }
        if (String.isNotBlank(firmanteEmail)) {
            c.Firmante_Email__c = firmanteEmail;
        }
        if (String.isNotBlank(firmanteTelefono)) {
            c.Firmante_Telefono__c = firmanteTelefono;
        }
        if (fechaEnvio != null) {
            c.Fecha_Envio__c = fechaEnvio;
        }
        if (String.isNotBlank(pdfFirmadoUrl)) {
            c.PDF_Firmado_URL__c = pdfFirmadoUrl;
        }
        if (String.isNotBlank(pdfOriginalUrl)) {
            c.PDF_Original_URL__c = pdfOriginalUrl;
        }
        return c;
    }

    private static void crearContratoDigitalConError(Id quoteId, String errorMsg) {
        Id opportunityId = null;
        if (quoteId != null) {
            List<Quote> quotes = [
                SELECT OpportunityId
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];
            if (!quotes.isEmpty()) {
                opportunityId = quotes[0].OpportunityId;
            }
        }
        Contrato_Digital__c c = createContratoDigitalForError(quoteId, opportunityId, errorMsg);
        insert c;
    }

    private static Contrato_Digital__c createContratoDigitalForError(Id quoteId, Id opportunityId, String errorMsg) {
        return crearContratoDigital(quoteId, opportunityId, null, null, null, errorMsg, null, null, null, null, null, null);
    }
}