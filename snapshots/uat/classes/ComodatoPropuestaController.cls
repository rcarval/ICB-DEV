public with sharing class ComodatoPropuestaController {
    public Id machineId { get; set; }
    public String aportesMarca { get; set; }
    public String fichaTecnica { get; private set; }

    public Product2 machine { get; private set; }
    public List<ServiceWrapper> serviceLines { get; private set; }
    public List<String> aporteLines { get; private set; }

    public ComodatoPropuestaController() {
        PageReference pg = ApexPages.currentPage();
        if (pg != null && pg.getParameters().containsKey('machineId')) {
            String mid = pg.getParameters().get('machineId');
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

        List<Comodato__c> allComodatos = [
            SELECT Producto_Asociado__r.Name, Precio_Unitario_Neto__c,
                   Cantidad_Minima_Mensual__c, Unidad_de_Medida__c,
                   Tipo_de_Asociacion__c, Cantidad_Aporte__c
            FROM Comodato__c
            WHERE Maquina__c = :machineId
        ];

        serviceLines = new List<ServiceWrapper>();
        List<String> aportesList = new List<String>();
        aporteLines = new List<String>();

        for (Comodato__c c : allComodatos) {
            if (c.Tipo_de_Asociacion__c == 'Insumo Mensual') {
                serviceLines.add(new ServiceWrapper(c));
            } else {
                String qty = (c.Cantidad_Aporte__c != null && c.Cantidad_Aporte__c > 0)
                    ? String.valueOf(Integer.valueOf(c.Cantidad_Aporte__c)) + ' '
                    : '';
                String line = qty + c.Producto_Asociado__r.Name;
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

        public ServiceWrapper(Comodato__c c) {
            this.ServiceName = c.Producto_Asociado__r.Name != null ? c.Producto_Asociado__r.Name : '';
            Decimal price = c.Precio_Unitario_Neto__c != null ? c.Precio_Unitario_Neto__c : 0;
            Decimal qty = c.Cantidad_Minima_Mensual__c != null ? c.Cantidad_Minima_Mensual__c : 0;
            String uom = c.Unidad_de_Medida__c != null ? c.Unidad_de_Medida__c : '';
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
        if (machineId == null) {
            return '<div style="color:red;padding:20px;">Error: machineId es nulo.</div>';
        }
        try {
            ComodatoPropuestaController ctrl = new ComodatoPropuestaController();
            ctrl.machineId = machineId;
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

        return '<div style="font-family:Arial,sans-serif;background:white;padding:24px;color:#333;">'
            + '<table style="width:100%;border-collapse:collapse;margin-bottom:20px;"><tr>'
            + '<td style="text-align:left;vertical-align:middle;"><img src="/resource/ICBLogo" style="height:70px;" alt="ICB Food Service"/></td>'
            + '<td style="text-align:right;vertical-align:middle;"><img src="/resource/LavazzaLogo" style="height:70px;" alt="Lavazza"/></td>'
            + '</tr></table>'
            + '<div style="background-color:#0000A0;color:white;text-align:center;padding:8px 0;font-size:14pt;font-weight:bold;letter-spacing:3px;margin-bottom:20px;">PROPUESTA</div>'
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