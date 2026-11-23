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

            String fuente = 'Verdana,Geneva,Arial,sans-serif';
            String oscuro = '#2B2B2B';
            String cuerpo = '#4A4A4A';
            String acento = '#E40147';
            String filaAlt = '#F7F7F8';

           
            String htmlBody =
                  '<!DOCTYPE html>'
                + '<html lang="es-CL" xmlns="http://www.w3.org/1999/xhtml">'
                + '<head>'
                + '<meta charset="UTF-8">'
                + '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
                + '<meta http-equiv="X-UA-Compatible" content="IE=edge">'
                + '<meta name="format-detection" content="telephone=no">'
                + '<title>ICB Food Service - ' + tipoRechazo + '</title>'
                + '<!--[if mso]><style>body,table,td,div,span,a{font-family:Verdana,Geneva,Arial,sans-serif !important;}</style><![endif]-->'
                + '<style>'
                + 'body{margin:0;padding:0;background:#F5F5F5;-webkit-text-size-adjust:100%;-ms-text-size-adjust:100%;}'
                + 'img{border:0;outline:none;text-decoration:none;-ms-interpolation-mode:bicubic;}'
                + 'table{border-collapse:collapse;}'
                + 'a{color:#007AF5;text-decoration:underline;}'
                + 'a:hover{color:#0061C4;}'
                + '@media only screen and (max-width:600px){'
                + '.container{width:100% !important;max-width:100% !important;}'
                + '.pad{padding-left:20px !important;padding-right:20px !important;}'
                + '}'
                + '</style>'
                + '</head>'
                + '<body style="margin:0;padding:0;background:#F5F5F5;">'
                + '<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">Se confirma el ingreso de su caso N° '
                + escapeHtml(c.CaseNumber) + ' por ' + tipoRechazo + '.</div>'
                + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F5F5F5;">'
                + '<tr><td align="center" style="padding:24px 12px 40px;font-family:' + fuente + ';">'
                + '<table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background:#FFFFFF;">'
                + '<tr><td style="padding:0;line-height:0;font-size:0;">'
                + '<a href="https://www.icbfs.cl" target="_blank" style="display:block;line-height:0;">'
                + '<img src="https://raw.githubusercontent.com/sebaCode0297/ICBFS_IMG/main/header.png" alt="ICBFS" '
                + 'style="display:block;width:100%;max-width:600px;height:auto;border:0;">'
                + '</a></td></tr>'
                + '<tr><td class="pad" style="padding:34px 32px 0;">'
                + '<div style="font:bold 28px/1.2 ' + fuente + ';color:' + oscuro + ';padding-bottom:6px;">Tu caso ha sido registrado ' + '</div>'
                + '<p style="font:bold 14px/1.5 ' + fuente + ';color:' + acento + ';margin:0 0 16px;">' + escapeHtml(tipoRechazo) + '</p>'
                + '<div style="font:bold 15px/1.5 ' + fuente + ';color:' + acento + ';padding-bottom:16px;">Estimado/a ' + escapeHtml(c.Account.Name) + ':</div>'
                + '<div style="background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid ' + acento + ';border-radius:8px;margin-bottom:16px;">'
                + '<div style="padding:16px;">'
                + '<div style="font:bold 11px/1.4 ' + fuente + ';letter-spacing:1.2px;color:' + acento + ';text-transform:uppercase;padding-bottom:6px;">Detalle del ingreso</div>'
                + '<div style="font:14.5px/1.7 ' + fuente + ';color:' + oscuro + ';">Se confirma el ingreso del caso N° <strong>' + escapeHtml(c.CaseNumber)
                + '</strong>, de tipo <strong>' + escapeHtml(c.Tipo_de_Requerimiento__c) + '</strong>, correspondiente al cliente <strong>' + escapeHtml(c.Account.Name) + '</strong>.</div>'
                + '</div></div>'
                + '<div style="font:14.5px/1.7 ' + fuente + ';color:' + cuerpo + ';padding-bottom:14px;">'
                + 'A continuación, compartimos el detalle del reclamo ingresado:</div>'
                + '</td></tr>'
                + '<tr><td class="pad" style="padding:26px 32px 0;">'
                + '<div style="font:14.5px/1.7 ' + fuente + ';color:' + cuerpo + ';padding-bottom:12px;">'
                + 'Detalle de productos asociados al <strong style="color:' + oscuro + ';">' + tipoRechazo + ':</strong></div>'
                + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;font:12px/1.5 ' + fuente + ';">'
                + '<thead>'
                + '<tr>'
                + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:10px 12px;text-align:center;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">#</th>'
                + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:10px 12px;text-align:left;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">SKU</th>'
                + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:10px 12px;text-align:left;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Producto</th>'
                + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:10px 12px;text-align:center;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Cant. | UM</th>'
                + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:10px 12px;text-align:right;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Valor Neto</th>'
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
                htmlBody += '<tr>'
                    + '<td style="padding:9px 12px;border-bottom:1px solid #ECECEF;text-align:center;color:' + cuerpo + ';">' + rowNum + '</td>'
                    + '<td style="padding:9px 12px;border-bottom:1px solid #ECECEF;color:' + oscuro + ';">' + escapeHtml(det.SKU__c) + '</td>'
                    + '<td style="padding:9px 12px;border-bottom:1px solid #ECECEF;color:' + cuerpo + ';">' + escapeHtml(det.Product__r.Name) + '</td>'
                    + '<td style="padding:9px 12px;border-bottom:1px solid #ECECEF;text-align:center;color:' + cuerpo + ';">' + det.Cantidad__c + ' | ' + escapeHtml(det.Unidad_de_Medida__c) + '</td>'
                    + '<td style="padding:9px 12px;border-bottom:1px solid #ECECEF;text-align:right;color:' + oscuro + ';">$' + valor.setScale(0).format() + '</td>'
                    + '</tr>';
                rowNum++;
            }

            htmlBody += '</tbody>'
                + '<tfoot>'
                + '<tr>'
                + '<td colspan="4" style="padding:10px 12px;background:' + filaAlt + ';text-align:right;font-weight:700;color:' + oscuro + ';">Total</td>'
                + '<td style="padding:10px 12px;background:' + filaAlt + ';text-align:right;font-weight:700;color:' + oscuro + ';">$' + totalNeto.setScale(0).format() + '</td>'
                + '</tr>'
                + '</tfoot>'
                + '</table>'
                + '</td></tr>'
                + '<tr><td class="pad" style="padding:26px 32px 0;">'
                + '<div style="font:bold 19px/1.3 ' + fuente + ';color:' + oscuro + ';padding-bottom:14px;">Motivo del reclamo</div>'
                + '<div style="background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid ' + acento + ';border-radius:8px;margin-bottom:16px;">'
                + '<div style="padding:16px;">'
                + '<div style="font:bold 11px/1.4 ' + fuente + ';letter-spacing:1.2px;color:' + acento + ';text-transform:uppercase;padding-bottom:6px;">Detalle del motivo</div>'
                + '<div style="font:14.5px/1.7 ' + fuente + ';color:' + oscuro + ';">' + escapeHtml(c.Motivo__c) + '</div>'
                + '</div></div>'
                + '<div style="font:14.5px/1.7 ' + fuente + ';color:' + cuerpo + ';padding-bottom:14px;">'
                + 'En las próximas etapas le mantendremos informado/a sobre los avances y la resolución correspondiente.</div>'
                + '<div style="font:12px/1.6 ' + fuente + ';color:#666666;padding-bottom:14px;">Este es un correo automático. Por favor, no responder a esta casilla.</div>'
                + '</td></tr>'
                + '<tr><td class="pad" style="padding:26px 32px 0;">'
                + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#EFF5FC;border:1px solid #D6E4F3;border-radius:8px;">'
                + '<tr><td style="padding:18px 20px;font:13.5px/1.75 ' + fuente + ';color:' + cuerpo + ';">'
                + 'Si tienes dudas o necesitas soporte, escríbenos.<br>'
                + 'Correo electrónico: <a href="mailto:ccc@icbfs.cl" style="color:#007AF5;text-decoration:underline;">ccc@icbfs.cl</a><br>'
                + 'WhatsApp al <a href="https://wa.me/56966490324" target="_blank" style="color:#007AF5;text-decoration:underline;">+56 9 6649 0324</a> (Lunes a Viernes 9:00 - 18:00 hrs, Sábados 09:00 - 14:00 hrs).'
                + '</td></tr>'
                + '</table>'
                + '</td></tr>'
                + '<tr><td style="padding:0 32px 34px;font-size:0;line-height:0;">&nbsp;</td></tr>'
                + '<tr><td bgcolor="#2E2E2E" align="center" class="pad" style="background:#2E2E2E;padding:32px 32px 28px;text-align:center;">'
                + '<img src="https://raw.githubusercontent.com/sebaCode0297/ICBFS_IMG/main/logo-footer.png" width="84" alt="ICB Food Service" style="display:block;margin:0 auto 18px;width:84px;height:auto;border:0;">'
                + '<div style="font:bold 14px/1.4 ' + fuente + ';color:#FFFFFF;letter-spacing:0.5px;text-transform:uppercase;padding-bottom:6px;">ICB Food Service</div>'
                + '<div style="font:bold 13px/1.5 ' + fuente + ';color:#FFFFFF;padding-bottom:6px;">Proveedor líder en la industria gastronómica</div>'
                + '<div style="font:12.5px/1.6 ' + fuente + ';color:#E6E6E6;">Compra 24/7 en <a href="https://pia.icbfs.cl" target="_blank" style="color:#FFFFFF;text-decoration:underline;">PIA</a>, nuestra plataforma integral de atención.</div>'
                + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:20px;"><tr><td style="border-top:1px solid #4A4A4A;padding-top:16px;font:11px/1.6 ' + fuente + ';color:#9A9A9A;text-align:center;">ICB Food Service · Santiago, Chile · Recibes este correo porque eres cliente de ICB Food Service.<br>Contacto · <a href="mailto:ccc@icbfs.cl" style="color:#CCCCCC;text-decoration:underline;">ccc@icbfs.cl</a> · WhatsApp +56 9 6649 0324</td></tr></table>'
                + '</td></tr>'
                + '</table>'
                + '</td></tr>'
                + '</table>'
                + '</body>'
                + '</html>';

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