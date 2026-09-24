/**
 * Acción invocable que envía un correo HTML maquetado por usuario y por zona
 * con el resumen de cambios de lista de precios.
 * Versión: v4 - 2026-09-23
 */
public with sharing class NotificacionCambioPrecioAction {
    private static final String ASUNTO_CORREO = '🔔 Actualización de Precios — [[NOMBRE]]';
    private static final String TOKEN_NOMBRE = '[[NOMBRE]]';
    private static final String TOKEN_ZONA = '[[ZONA]]';
    private static final String TOKEN_CANTIDAD = '[[CANTIDAD]]';
    private static final String TOKEN_URL = '[[URL]]';

    // Plantilla HTML con estilos en línea (兼容 con Outlook y Gmail)
    private static final String CUERPO_HTML =
        '<!DOCTYPE html><html><head><meta charset="utf-8"></head>' +
        '<body style="margin:0;padding:0;background-color:#f3f4f6;font-family:Arial,Helvetica,sans-serif;">' +
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f3f4f6;padding:24px 0;">' +
        '<tr><td align="center">' +
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" ' +
        'style="max-width:560px;background-color:#ffffff;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;">' +
        '<tr><td style="background-color:#E1003F;padding:30px 35px;color:#ffffff;font-size:18px;font-weight:bold;">' +
        '🔔 Actualización de Precios</td></tr>' +
        '<tr><td style="padding:24px;font-size:14px;line-height:22px;color:#1f2937;">' +
        '<p style="margin:0 0 16px 0;">Hola,</p>' +
        '<p style="margin:0 0 20px 0;">Se detectó una actualización de cambio de precios</p>' +
        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" ' +
        'style="background-color:#f9fafb;border:1px solid #e5e7eb;border-radius:6px;margin-bottom:24px;">' +
        '<tr><td style="padding:12px 16px;border-bottom:1px solid #e5e7eb;color:#4b5563;"><strong>Zona:</strong></td>' +
        '<td style="padding:12px 16px;border-bottom:1px solid #e5e7eb;color:#111827;text-align:right;"><strong>[[ZONA]]</strong></td></tr>' +
        '<tr><td style="padding:12px 16px;color:#4b5563;"><strong>Cantidad de productos:</strong></td>' +
        '<td style="padding:12px 16px;color:#111827;text-align:right;"><strong>[[CANTIDAD]]</strong></td></tr>' +
        '</table>' +
        '<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:24px auto 8px auto;">' +
        '<tr><td align="center" style="background-color:#E1003F;border-radius:6px;">' +
        '<a href="[[URL]]" target="_blank" style="display:inline-block;padding:12px 28px;font-size:14px;' +
        'font-weight:bold;color:#ffffff;text-decoration:none;border-radius:6px;">Ver detalles en Salesforce</a>' +
        '</td></tr></table>' +
        '</td></tr>' +
        '<tr><td style="padding:16px;border-top:1px solid #e5e7eb;font-size:12px;color:#9ca3af;text-align:center;background-color:#f9fafb;">' +
        'Este es un mensaje automático, por favor no respondas a este correo.</td></tr>' +
        '</table></td></tr></table></body></html>';

    private static final String CUERPO_TEXTO =
        'Hola,\n\n' +
        'Se detectó una actualización en la lista de precios.\n\n' +
        '• Zona: [[ZONA]]\n' +
        '• Cantidad de productos: [[CANTIDAD]]\n\n' +
        'Ver detalle en Salesforce: [[URL]]\n\n' +
        'Este es un mensaje automático, por favor no respondas este correo.';

    public class Request {
        @InvocableVariable(label='Id Cambio Lista Precios' required=true)
        public Id cambioListaPreciosId;


        @InvocableVariable(label='Ids de Usuarios' description='Usuario a notificar en cada posición')
        public List<String> usuarioIds;

        @InvocableVariable(label='Zonas' description='Zona de la notificación en cada posición')
        public List<String> zonas;

        @InvocableVariable(label='Cantidades de Productos' description='Productos con cambio de la zona en cada posición')
        public List<Decimal> cantidadesProductos;
    }

    @InvocableMethod(
        label='Enviar Notificación Cambio Precio por Zona'
        description='Envía un correo HTML por usuario y por zona con la cantidad de productos que cambiaron de precio'
        category='Lista de Precios'
    )
    public static void enviarNotificaciones(List<Request> requests) {
        String urlBase = Url.getOrgDomainUrl().toExternalForm() + '/';

        List<Messaging.SingleEmailMessage> correos = new List<Messaging.SingleEmailMessage>();
        for (Request req : requests) {
            if (req.usuarioIds == null || req.zonas == null || req.cantidadesProductos == null) {
                continue;
            }
            String urlCambio = urlBase + 'lightning/n/CambiosDePrecios';
            Integer total = Math.min(req.usuarioIds.size(), Math.min(req.zonas.size(), req.cantidadesProductos.size()));

            for (Integer i = 0; i < total; i++) {
                correos.add(construirCorreo(urlCambio,  req.usuarioIds[i], req.zonas[i], req.cantidadesProductos[i]));
            }
        }

        if (!correos.isEmpty()) {
            Messaging.sendEmail(correos);
        }
    }

    private static Messaging.SingleEmailMessage construirCorreo(
        String urlCambio,
        String usuarioId,
        String zona,
        Decimal cantidadProductos
    ) {
        String zonaTexto = zona != null ? zona : '';
        String cantidad = cantidadProductos != null ? String.valueOf(cantidadProductos.intValue()) : '0';

        Messaging.SingleEmailMessage correo = new Messaging.SingleEmailMessage();
        correo.setTargetObjectId(usuarioId);
        correo.setSaveAsActivity(false);


        // Cuerpo en HTML Enriquecido
        correo.setHtmlBody(
            CUERPO_HTML
                .replace(TOKEN_ZONA, zonaTexto.escapeHtml4())
                .replace(TOKEN_CANTIDAD, cantidad)
                .replace(TOKEN_URL, urlCambio)
        );

        // Respaldo Texto Plano
        correo.setPlainTextBody(
            CUERPO_TEXTO
                .replace(TOKEN_ZONA, zonaTexto)
                .replace(TOKEN_CANTIDAD, cantidad)
                .replace(TOKEN_URL, urlCambio)
        );

        return correo;
    }
}