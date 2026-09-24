public with sharing class seidor_CaseRechazoPdfInvocable {

    @TestVisible
    private static Id testOrgWideEmailId;

    public class FlowInput {
        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable(required=true)
        public String toAddresses;

        @InvocableVariable
        public String ccAddresses;

        @InvocableVariable
        public String bccAddresses;
    }

    @InvocableMethod(label='Enviar Correo Rechazo Devolucion')
    public static void sendEmail(List<FlowInput> inputs) {
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        Id oweaId = testOrgWideEmailId;
        if (oweaId == null) {
            List<OrgWideEmailAddress> oweaList = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE Address = 'notificaciones@icbfs.cl'
                LIMIT 1
            ];
            if (!oweaList.isEmpty()) {
                oweaId = oweaList[0].Id;
            }
        }

        for (FlowInput input : inputs) {
            Case c = [
                SELECT Id, CaseNumber, Account.Name,
                       Factura__c, Factura__r.Name, Factura__r.Sucursal__c,
                       Tipo_de_Requerimiento__c, Sub_Categoria__c, Motivo__c,
                       Cantidad_reclamada__c
                FROM Case
                WHERE Id = :input.caseId
                LIMIT 1
            ];

            Boolean esRechazoTotal = c.Tipo_de_Requerimiento__c == 'Devoluciones'
                && c.Sub_Categoria__c == 'Rechazo total';
            Boolean esRechazoParcial = c.Tipo_de_Requerimiento__c == 'Devoluciones'
                && c.Sub_Categoria__c == 'Rechazo parcial';

            if (!esRechazoTotal && !esRechazoParcial) {
                continue;
            }

            String tipoRechazo = esRechazoTotal ? 'Rechazo total' : 'Rechazo parcial';
            String asunto = 'Devolucion ' + tipoRechazo + ' - ' + c.CaseNumber;

            List<Detalle_Factura__c> detalles;
            if (esRechazoTotal) {
                detalles = [
                    SELECT Name, SKU__c, Cantidad__c, Unidad_de_Medida__c,
                           Valor_Neto__c, Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__c = :c.Factura__c
                    ORDER BY Name
                ];
            } else {
                detalles = [
                    SELECT Name, SKU__c, Cantidad__c, Unidad_de_Medida__c,
                           Valor_Neto__c, Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__c = :c.Factura__c
                      AND Proceso_de_reclamo__c = true
                    ORDER BY Name
                ];
            }

            String hdrBg = '#C25050';
            String hdrTxt = '#FFFFFF';
            String rowAlt = '#FDF6F6';
            String border = '#E0D5D5';
            String totalBg = '#F5EDED';

           
            String htmlBody = ''
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">Estimado/a <strong>' + escapeHtml(c.Account.Name) + ';</strong></p>'
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">'
                + 'Se confirma el ingreso del caso N° <strong>' + escapeHtml(c.CaseNumber) + '</strong>, '
                + 'de tipo <strong>' + escapeHtml(c.Tipo_de_Requerimiento__c) + '</strong>, '
                + 'correspondiente al cliente <strong>' + escapeHtml(c.Account.Name) + '</strong>.</p>'
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">A continuación, compartimos el detalle del reclamo ingresado:</p>'
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">'
                + '<strong>Motivo del reclamo:</strong> ' + escapeHtml(c.Motivo__c) + '</p>'
                + '<p style="margin:0 0 10px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">'
                + 'Detalle de productos asociados al <strong>' + escapeHtml(tipoRechazo) + '</strong>:</p>'
                + '<table cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;font-family:Arial,Helvetica,sans-serif;font-size:12px;margin-bottom:16px;">'
                + '<thead>'
                + '<tr>'
                + '<th style="background:' + hdrBg + ';color:' + hdrTxt + ';padding:6px 8px;text-align:center;font-weight:600;border:1px solid ' + hdrBg + ';">#</th>'
                + '<th style="background:' + hdrBg + ';color:' + hdrTxt + ';padding:6px 8px;text-align:left;font-weight:600;border:1px solid ' + hdrBg + ';">SKU</th>'
                + '<th style="background:' + hdrBg + ';color:' + hdrTxt + ';padding:6px 8px;text-align:left;font-weight:600;border:1px solid ' + hdrBg + ';">Producto</th>'
                + '<th style="background:' + hdrBg + ';color:' + hdrTxt + ';padding:6px 8px;text-align:center;font-weight:600;border:1px solid ' + hdrBg + ';">Cant. | UM</th>'
                + '<th style="background:' + hdrBg + ';color:' + hdrTxt + ';padding:6px 8px;text-align:right;font-weight:600;border:1px solid ' + hdrBg + ';">Valor Neto</th>'
                + '</tr>'
                + '</thead>'
                + '<tbody>';

            Integer rowNum = 1;
            Decimal totalNeto = 0;
            for (Detalle_Factura__c det : detalles) {
                if (esRechazoParcial && det.Cantidad__c == null) {
                    det.Cantidad__c = c.Cantidad_reclamada__c;
                }
                Decimal valor = det.Valor_Neto__c != null ? det.Valor_Neto__c : 0;
                totalNeto += valor;
                String bg = Math.mod(rowNum, 2) == 0 ? rowAlt : '#FFFFFF';
                htmlBody += '<tr>'
                    + '<td style="padding:5px 8px;border:1px solid ' + border + ';background:' + bg + ';text-align:center;color:#333;">' + rowNum + '</td>'
                    + '<td style="padding:5px 8px;border:1px solid ' + border + ';background:' + bg + ';color:#333;">' + escapeHtml(det.SKU__c) + '</td>'
                    + '<td style="padding:5px 8px;border:1px solid ' + border + ';background:' + bg + ';color:#333;">' + escapeHtml(det.Product__r.Name) + '</td>'
                    + '<td style="padding:5px 8px;border:1px solid ' + border + ';background:' + bg + ';text-align:center;color:#333;">' + det.Cantidad__c + ' | ' + escapeHtml(det.Unidad_de_Medida__c) + '</td>'
                    + '<td style="padding:5px 8px;border:1px solid ' + border + ';background:' + bg + ';text-align:right;color:#333;">$' + valor.setScale(0).format() + '</td>'
                    + '</tr>';
                rowNum++;
            }

            htmlBody += '</tbody>'
                + '<tfoot>'
                + '<tr>'
                + '<td colspan="4" style="padding:6px 8px;border:1px solid ' + border + ';background:' + totalBg + ';text-align:right;font-weight:700;color:#8B4040;">Total</td>'
                + '<td style="padding:6px 8px;border:1px solid ' + border + ';background:' + totalBg + ';text-align:right;font-weight:700;color:#8B4040;">$' + totalNeto.setScale(0).format() + '</td>'
                + '</tr>'
                + '</tfoot>'
                + '</table>'
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">En las próximas etapas le mantendremos informado/a sobre los avances y la resolución correspondiente.</p>'
                + '<p style="margin:0 0 14px;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#666;">Este es un correo automático. Por favor, no responder a esta casilla.<br/>'
                + 'Para consultas, contactar al <a href="mailto:ccc@icbfs.cl" style="color:#1B3A5C;">ccc@icbfs.cl</a> '
                + 'o al WhatsApp +56 9 6649 0324.</p>'
                + '<p style="margin:0 0 6px;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#333;">Saludos cordiales,<br/>'
                + '<strong>Equipo de Atención al Cliente</strong><br/>'
                + 'ICB Food Service</p>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }
            email.setSubject(asunto);
            email.setHtmlBody(htmlBody);
            email.setToAddresses(input.toAddresses.split(','));

            if (String.isNotBlank(input.ccAddresses)) {
                email.setCcAddresses(input.ccAddresses.split(','));
            }
            if (String.isNotBlank(input.bccAddresses)) {
                email.setBccAddresses(input.bccAddresses.split(','));
            }

            emailsToSend.add(email);
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend);
        }
    }

    private static String escapeHtml(String value) {
        if (value == null) return '';
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}