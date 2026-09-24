public with sharing class ComodatoPropuestaController {
    public Id machineId { get; set; }
    public String aportesMarca { get; set; }
    public String fichaTecnica { get; private set; }

    public Product2 machine { get; private set; }
    public List<ServiceWrapper> serviceLines { get; private set; }
    public List<String> aporteLines { get; private set; }

    /** Quote de contexto: define que ajuste excepcional aplica. Null = valores maestros. */
    @TestVisible
    private Id quoteId;

    /** Ajustes capturados en pantalla y todavia no guardados. */
    @TestVisible
    private String ajustesJson;

    public ComodatoPropuestaController() {
        PageReference pg = ApexPages.currentPage();
        if (pg != null && pg.getParameters().containsKey('machineId')) {
            String mid = pg.getParameters().get('machineId');
            String qid = pg.getParameters().get('quoteId');
            // Ver nota en ComodatoPropuestaMultiController: el PDF se renderiza aparte.
            this.ajustesJson = pg.getParameters().get('ajustesJson');
            if (String.isNotBlank(qid)) {
                quoteId = Id.valueOf(qid);
            }
            if (String.isNotBlank(mid)) {
                machineId = Id.valueOf(mid);
                loadData();
            }
        }
    }

    @TestVisible
    private void loadData() {
        machine = [
            SELECT Id, Name, ProductCode, Precio_de_Lista__c, Imagen_Propuesta__c, Descripci_n_Larga__c
            FROM Product2
            WHERE Id = :machineId
            LIMIT 1
        ];

        // Lineas YA RESUELTAS: reflejan el ajuste excepcional vigente para esta Quote.
        List<ComodatoOverrideResolver.LineaResuelta> allComodatos =
            ComodatoOverrideResolver.resolver(new Set<Id>{ machineId }, quoteId, ajustesJson);

        serviceLines = new List<ServiceWrapper>();
        List<String> aportesList = new List<String>();
        aporteLines = new List<String>();

        for (ComodatoOverrideResolver.LineaResuelta c : allComodatos) {
            if (c.tipoDeAsociacion == 'Insumo Mensual') {
                serviceLines.add(new ServiceWrapper(c));
            } else {
                String qty = (c.cantidadAporte != null && c.cantidadAporte > 0)
                    ? String.valueOf(Integer.valueOf(c.cantidadAporte)) + ' '
                    : '';
                String line = qty + (c.productoAsociadoNombre != null ? c.productoAsociadoNombre : '');
                aportesList.add(line);
                aporteLines.add(line);
            }
        }

        if (!aportesList.isEmpty()) {
            aportesMarca = String.join(aportesList, '\n');
        }

        fichaTecnica = machine.Descripci_n_Larga__c;
    }

    public Boolean getHasFichaTecnica() {
        return String.isNotBlank(fichaTecnica);
    }

    public String getFichaTecnicaHtml() {
        return formatMultilineText(fichaTecnica);
    }

    public class ServiceWrapper {
        public String ServiceName { get; private set; }
        public String FormattedPrice { get; private set; }
        public String FormattedQty { get; private set; }

        public ServiceWrapper(ComodatoOverrideResolver.LineaResuelta c) {
            this.ServiceName = c.productoAsociadoNombre != null ? c.productoAsociadoNombre : '';
            Decimal price = c.precioUnitarioNeto != null ? c.precioUnitarioNeto : 0;
            Decimal qty = c.cantidadMinimaMensual != null ? c.cantidadMinimaMensual : 0;
            String uom = c.unidadDeMedida != null ? c.unidadDeMedida : '';
            this.FormattedPrice = formatCLP(price);
            this.FormattedQty = String.valueOf(qty.setScale(0)) + ' ' + uom;
        }

        private String formatCLP(Decimal amount) {
            Long intPart = amount.setScale(0).longValue();
            String s = String.valueOf(intPart);
            String result = '';
            Integer cnt = 0;
            for (Integer i = s.length() - 1; i >= 0; i--) {
                if (cnt > 0 && Math.mod(cnt, 3) == 0) {
                    result = '.' + result;
                }
                result = s.substring(i, i + 1) + result;
                cnt++;
            }
            return '$' + result;
        }
    }

    @AuraEnabled
    public static String getPreviewHtml(Id machineId) {
        return getPreviewHtmlParaQuote(machineId, null);
    }

    /** Vista previa con ajustes aun no guardados (modo guiado / una sola maquina). */
    @AuraEnabled
    public static String getPreviewHtmlConAjustes(Id machineId, String ajustesJson) {
        if (machineId == null) {
            return '<div style="color:red;padding:20px;">Error: machineId es nulo.</div>';
        }
        try {
            ComodatoPropuestaController ctrl = new ComodatoPropuestaController();
            ctrl.machineId = machineId;
            ctrl.ajustesJson = ajustesJson;
            ctrl.loadData();
            return buildPreviewHtml(ctrl);
        } catch (Exception e) {
            return '<div style="color:red; padding:20px; border:1px solid red;">'
                + '<b>Error al generar vista previa:</b><br/>' + escapeHtml(e.getMessage()) + '</div>';
        }
    }

    /** Variante con Quote: la vista previa refleja el ajuste excepcional de esa Quote.
     *  Apex no admite overloads de metodos @AuraEnabled, por eso lleva nombre propio. */
    @AuraEnabled
    public static String getPreviewHtmlParaQuote(Id machineId, Id quoteId) {
        if (machineId == null) {
            return '<div style="color:red;padding:20px;">Error: machineId es nulo.</div>';
        }
        try {
            ComodatoPropuestaController ctrl = new ComodatoPropuestaController();
            ctrl.machineId = machineId;
            ctrl.quoteId = quoteId;
            ctrl.loadData();
            return buildPreviewHtml(ctrl);
        } catch (Exception e) {
            return '<div style="color:red; padding:20px; border:1px solid red;">'
                + '<b>Error al generar vista previa:</b><br/>' + escapeHtml(e.getMessage())
                + '<br/><small>' + escapeHtml(e.getStackTraceString()) + '</small></div>';
        }
    }

    private static String buildPreviewHtml(ComodatoPropuestaController ctrl) {
        String machineName = ctrl.machine != null ? ctrl.machine.Name : '';
        String machineImage = ctrl.machine != null && String.isNotBlank(ctrl.machine.Imagen_Propuesta__c)
            ? ctrl.machine.Imagen_Propuesta__c
            : '';
        String technicalSheetHtml = formatMultilineText(ctrl.fichaTecnica);

        String rows = '';
        if (ctrl.serviceLines != null) {
            for (ServiceWrapper s : ctrl.serviceLines) {
                rows += '<tr>'
                    + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;">' + escapeHtml(s.ServiceName) + '</td>'
                    + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;">' + escapeHtml(s.FormattedPrice) + '</td>'
                    + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;">' + escapeHtml(s.FormattedQty) + '</td>'
                    + '</tr>';
            }
        }

        String aporteItems = '';
        if (String.isNotBlank(ctrl.aportesMarca)) {
            for (String aporte : ctrl.aportesMarca.split('\n')) {
                if (String.isNotBlank(aporte)) {
                    aporteItems += '<li style="margin-bottom:6px;">' + escapeHtml(aporte.trim()) + '</li>';
                }
            }
        }

        String aporteSection = String.isNotBlank(aporteItems)
            ? '<div style="margin-top:20px;page-break-inside:avoid;">'
              + '<p style="font-weight:bold;margin-bottom:12px;">Aporte por Marca Lavazza, que contempla los siguientes elementos para potenciar la experiencia de cafe en su negocio:</p>'
              + '<ul style="padding-left:20px;">' + aporteItems + '</ul>'
              + '</div>'
            : '';

        String fichaTecnicaSection = String.isNotBlank(technicalSheetHtml)
            ? '<div style="margin-top:24px;page-break-inside:avoid;">'
              + '<p style="font-weight:bold;margin-bottom:10px;font-size:10pt;">FICHA TECNICA</p>'
              + '<div style="font-size:9pt;line-height:1.5;">' + technicalSheetHtml + '</div>'
              + '</div>'
            : '';

        // La cabecera se arma en ComodatoCabecera para que la vista previa y el PDF no
        // puedan mostrar cabeceras distintas.
        return '<div style="font-family:Arial,sans-serif;background:white;padding:24px;color:#333;">'
            + ComodatoCabecera.html()
            + ComodatoCabecera.banner()
            + (String.isNotBlank(machineImage)
                ? '<table style="width:100%;margin:20px 0 30px 0;border-collapse:collapse;"><tr><td style="text-align:center;padding:0;"><div style="display:inline-block;max-width:300px;text-align:center;">'
                  + machineImage
                  + '</div></td></tr></table>'
                : '')
            + '<div style="text-align:center;font-size:13pt;font-weight:bold;letter-spacing:1px;text-transform:uppercase;margin-bottom:24px;">' + escapeHtml(machineName) + '</div>'
            + '<div style="border:1px solid #0000A0;margin-bottom:24px;">'
            + '<table style="width:100%;border-collapse:collapse;">'
            + '<thead><tr>'
            + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:40%;">DESCRIPCION</th>'
            + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:30%;">PRECIO UN NETO (KG)</th>'
            + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:30%;">CANTIDAD MINIMA MENSUAL</th>'
            + '</tr></thead>'
            + '<tbody>' + rows + '</tbody>'
            + '</table>'
            + '</div>'
            + aporteSection
            + fichaTecnicaSection
            + '<div style="margin-top:40px;font-size:8pt;text-align:center;color:#666;">'
            + '&quot;La entrega del equipo en comodato esta sujeta a la aprobacion de una linea de credito con la empresa.<br/>'
            + 'El contrato de comodato tendra una vigencia de 3 anos.&quot;'
            + '</div>'
            + '</div>';
    }

    private static String formatMultilineText(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        List<String> escapedLines = new List<String>();
        for (String line : value.replace('\r\n', '\n').replace('\r', '\n').split('\n')) {
            escapedLines.add(escapeHtml(line));
        }
        return String.join(escapedLines, '<br/>');
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }

        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}