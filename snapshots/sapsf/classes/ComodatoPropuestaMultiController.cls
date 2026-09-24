/**
 * Controller para generar propuestas de Comodato multi-máquina.
 * Soporta: VF Page renderAs=pdf y @AuraEnabled para LWC preview.
 * Lógica: Cada máquina distinta = sección separada en el PDF.
 * Si hay N de la misma máquina, se muestra 1 sola sección (la config no cambia por cantidad).
 */
public with sharing class ComodatoPropuestaMultiController {

    public List<MachineSection> sections { get; private set; }
    public Boolean hasMultipleSections { get; private set; }

    // Constructor para VF Page
    public ComodatoPropuestaMultiController() {
        PageReference pg = ApexPages.currentPage();
        if (pg == null) return;

        String machineIdsParam = pg.getParameters().get('machineIds');
        String quantitiesParam = pg.getParameters().get('quantities');
        String quoteIdParam    = pg.getParameters().get('quoteId');
        // getContentAsPDF() renderiza la pagina en un contexto aparte, donde los
        // Comodato_Override__c recien creados todavia no estan comprometidos. Por eso los
        // ajustes llegan tambien por parametro y no se depende solo de leerlos en base.
        String ajustesParam    = pg.getParameters().get('ajustesJson');

        if (String.isBlank(machineIdsParam)) return;

        List<String> idStrings = machineIdsParam.split(',');
        List<String> qtyStrings = String.isNotBlank(quantitiesParam) ? quantitiesParam.split(',') : new List<String>();

        Set<Id> machineIds = new Set<Id>();
        Map<Id, Integer> quantities = new Map<Id, Integer>();

        for (Integer i = 0; i < idStrings.size(); i++) {
            Id mid = Id.valueOf(idStrings[i].trim());
            machineIds.add(mid);
            Integer qty = (i < qtyStrings.size()) ? Integer.valueOf(qtyStrings[i].trim()) : 1;
            quantities.put(mid, qty);
        }

        Id quoteId = String.isNotBlank(quoteIdParam) ? (Id) quoteIdParam : null;
        sections = buildSections(machineIds, quantities, quoteId, ajustesParam);
        hasMultipleSections = sections.size() > 1;
    }

    // Método estático para generar HTML del PDF (usado por la Invocable Action)
    public static String buildMultiMachinePdfHtml(Set<Id> machineIds, Map<Id, Integer> quantities) {
        return buildMultiMachinePdfHtml(machineIds, quantities, null);
    }

    /** Overload con Quote: aplica los ajustes excepcionales vigentes para esa Quote. */
    public static String buildMultiMachinePdfHtml(Set<Id> machineIds, Map<Id, Integer> quantities, Id quoteId) {
        List<MachineSection> secs = buildSections(machineIds, quantities, quoteId);
        return buildFullHtml(secs);
    }

    // Método @AuraEnabled para preview en LWC
    @AuraEnabled
    public static String getMultiMachinePreviewHtml(String machineSelectionsJson) {
        return getMultiMachinePreviewHtmlParaQuote(machineSelectionsJson, null);
    }

    /**
     * Vista previa con los ajustes que el usuario acaba de hacer y que todavia no estan
     * guardados (aun no existe la Quote). Es lo que hace que la cotizacion en pantalla sea
     * identica a la que se va a guardar.
     */
    @AuraEnabled
    public static String getMultiMachinePreviewHtmlConAjustes(String machineSelectionsJson, String ajustesJson) {
        if (String.isBlank(machineSelectionsJson)) {
            return '<div style="color:#666;padding:20px;text-align:center;">Selecciona al menos una máquina para ver la vista previa.</div>';
        }
        try {
            List<GenerarPDFComodatoMultiAction.MachineSelection> selections =
                (List<GenerarPDFComodatoMultiAction.MachineSelection>)
                JSON.deserialize(machineSelectionsJson, List<GenerarPDFComodatoMultiAction.MachineSelection>.class);

            Map<Id, Integer> quantities = new Map<Id, Integer>();
            Set<Id> machineIds = new Set<Id>();
            for (GenerarPDFComodatoMultiAction.MachineSelection sel : selections) {
                machineIds.add(sel.machineId);
                Integer existing = quantities.containsKey(sel.machineId) ? quantities.get(sel.machineId) : 0;
                quantities.put(sel.machineId, existing + sel.quantity);
            }

            List<MachineSection> secs = buildSections(machineIds, quantities, null, ajustesJson);
            return buildFullHtml(secs);
        } catch (Exception e) {
            return '<div style="color:red;padding:20px;border:1px solid red;">'
                + '<b>Error:</b> ' + escapeHtml(e.getMessage()) + '</div>';
        }
    }

    /** Variante con Quote: la vista previa refleja los ajustes excepcionales de esa Quote.
     *  Apex no admite overloads de metodos @AuraEnabled, por eso lleva nombre propio. */
    @AuraEnabled
    public static String getMultiMachinePreviewHtmlParaQuote(String machineSelectionsJson, Id quoteId) {
        if (String.isBlank(machineSelectionsJson)) {
            return '<div style="color:#666;padding:20px;text-align:center;">Selecciona al menos una máquina para ver la vista previa.</div>';
        }
        try {
            List<GenerarPDFComodatoMultiAction.MachineSelection> selections =
                (List<GenerarPDFComodatoMultiAction.MachineSelection>)
                JSON.deserialize(machineSelectionsJson, List<GenerarPDFComodatoMultiAction.MachineSelection>.class);

            Map<Id, Integer> quantities = new Map<Id, Integer>();
            Set<Id> machineIds = new Set<Id>();
            for (GenerarPDFComodatoMultiAction.MachineSelection sel : selections) {
                machineIds.add(sel.machineId);
                Integer existing = quantities.containsKey(sel.machineId) ? quantities.get(sel.machineId) : 0;
                quantities.put(sel.machineId, existing + sel.quantity);
            }

            return buildMultiMachinePdfHtml(machineIds, quantities, quoteId);
        } catch (Exception e) {
            return '<div style="color:red;padding:20px;border:1px solid red;">'
                + '<b>Error:</b> ' + escapeHtml(e.getMessage()) + '</div>';
        }
    }

    // ═══════════════════════════════════════════════════════
    // Lógica de construcción de secciones
    // ═══════════════════════════════════════════════════════

    private static List<MachineSection> buildSections(Set<Id> machineIds, Map<Id, Integer> quantities, Id quoteId) {
        return buildSections(machineIds, quantities, quoteId, null);
    }

    private static List<MachineSection> buildSections(Set<Id> machineIds, Map<Id, Integer> quantities, Id quoteId, String ajustesJson) {
        // Consultar productos (máquinas)
        Map<Id, Product2> machines = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, Precio_de_Lista__c, Imagen_Propuesta__c, Descripci_n_Larga__c
            FROM Product2
            WHERE Id IN :machineIds
        ]);

        // Configuraciones Comodato__c YA RESUELTAS: si la Quote tiene un ajuste excepcional
        // activo, estas lineas traen los valores ajustados. Nunca se lee Comodato__c directo.
        List<ComodatoOverrideResolver.LineaResuelta> allComodatos =
            ComodatoOverrideResolver.resolver(machineIds, quoteId, ajustesJson);

        // Agrupar comodatos por máquina
        Map<Id, List<ComodatoOverrideResolver.LineaResuelta>> comodatosByMachine =
            new Map<Id, List<ComodatoOverrideResolver.LineaResuelta>>();
        for (ComodatoOverrideResolver.LineaResuelta c : allComodatos) {
            if (!comodatosByMachine.containsKey(c.maquinaId)) {
                comodatosByMachine.put(c.maquinaId, new List<ComodatoOverrideResolver.LineaResuelta>());
            }
            comodatosByMachine.get(c.maquinaId).add(c);
        }

        // Construir secciones
        List<MachineSection> sections = new List<MachineSection>();
        for (Id machineId : machineIds) {
            Product2 machine = machines.get(machineId);
            if (machine == null) continue;

            Integer qty = quantities.containsKey(machineId) ? quantities.get(machineId) : 1;
            List<ComodatoOverrideResolver.LineaResuelta> comodatos = comodatosByMachine.containsKey(machineId)
                ? comodatosByMachine.get(machineId) : new List<ComodatoOverrideResolver.LineaResuelta>();

            sections.add(new MachineSection(machine, qty, comodatos));
        }

        return sections;
    }

    // ═══════════════════════════════════════════════════════
    // Generación de HTML
    // ═══════════════════════════════════════════════════════

    private static String buildFullHtml(List<MachineSection> sections) {
        String html = '<div style="font-family:Arial,sans-serif;background:white;padding:24px;color:#333;">';

        // Header con logos: se arma en ComodatoCabecera para que la vista previa y el PDF
        // no puedan mostrar cabeceras distintas.
        html += ComodatoCabecera.html();
        html += ComodatoCabecera.banner();

        // Secciones por máquina
        for (Integer i = 0; i < sections.size(); i++) {
            MachineSection sec = sections[i];

            // Separador entre secciones (no en la primera)
            if (i > 0) {
                html += '<div style="border-top:3px solid #0000A0;margin:30px 0;"></div>';
            }

            // Cantidad si es > 1
            String qtyLabel = sec.quantity > 1
                ? '<div style="text-align:center;font-size:11pt;color:#0000A0;font-weight:bold;margin-bottom:20px;">(x' + sec.quantity + ' unidades)</div>'
                : '';

            // Imagen de la máquina
            if (String.isNotBlank(sec.machineImage)) {
                html += '<table style="width:100%;margin:20px 0;border-collapse:collapse;"><tr><td style="text-align:center;padding:0;"><div style="display:inline-block;max-width:250px;text-align:center;">'
                    + sec.machineImage + '</div></td></tr></table>';
            }

            // Nombre de la máquina
            html += '<div style="text-align:center;font-size:13pt;font-weight:bold;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">'
                + escapeHtml(sec.machineName) + '</div>' + qtyLabel;

            // Tabla de servicios
            if (!sec.serviceLines.isEmpty()) {
                html += '<div style="border:1px solid #0000A0;margin-bottom:24px;">'
                    + '<table style="width:100%;border-collapse:collapse;">'
                    + '<thead><tr>'
                    + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:40%;">DESCRIPCION</th>'
                    + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:30%;">PRECIO UN NETO (KG)</th>'
                    + '<th style="background:#0000A0;color:white;padding:10px 14px;font-size:9pt;text-align:left;width:30%;">CANTIDAD MINIMA MENSUAL</th>'
                    + '</tr></thead><tbody>';

                for (ServiceLine sl : sec.serviceLines) {
                    String fondo = sl.esAjustada ? 'background:#fef8e7;' : '';
                    html += '<tr>'
                        + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;' + fondo + '">' + escapeHtml(sl.serviceName) + '</td>'
                        + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;' + fondo + '">' + escapeHtml(sl.formattedPrice) + '</td>'
                        + '<td style="padding:10px 14px;border-bottom:1px solid #eee;font-size:9pt;' + fondo + '">' + escapeHtml(sl.formattedQty) + '</td>'
                        + '</tr>';
                    if (sl.esAjustada && String.isNotBlank(sl.notaAjuste)) {
                        html += '<tr><td colspan="3" style="padding:2px 14px 8px;border-bottom:1px solid #eee;'
                            + 'font-size:7.5pt;color:#8a6d3b;background:#fef8e7;font-style:italic;">'
                            + escapeHtml(sl.notaAjuste) + '</td></tr>';
                    }
                }

                html += '</tbody></table></div>';
            }

            // Aportes de marca
            if (!sec.aporteLines.isEmpty()) {
                html += '<div style="margin-top:20px;page-break-inside:avoid;">'
                    + '<p style="font-weight:bold;margin-bottom:12px;">Aporte por Marca Lavazza:</p><ul style="padding-left:20px;">';
                for (String aporte : sec.aporteLines) {
                    html += '<li style="margin-bottom:6px;">' + escapeHtml(aporte) + '</li>';
                }
                html += '</ul></div>';
            }

            // Ficha técnica
            if (String.isNotBlank(sec.fichaTecnica)) {
                html += '<div style="margin-top:24px;page-break-inside:avoid;">'
                    + '<p style="font-weight:bold;margin-bottom:10px;font-size:10pt;">FICHA TECNICA</p>'
                    + '<div style="font-size:9pt;line-height:1.5;">' + formatMultilineText(sec.fichaTecnica) + '</div>'
                    + '</div>';
            }
        }

        // Disclaimer
        html += '<div style="margin-top:40px;font-size:8pt;text-align:center;color:#666;">'
            + '&quot;La entrega del equipo en comodato esta sujeta a la aprobacion de una linea de credito con la empresa.<br/>'
            + 'El contrato de comodato tendra una vigencia de 3 anos.&quot;</div>';

        html += '</div>';
        return html;
    }

    // ═══════════════════════════════════════════════════════
    // Clases internas
    // ═══════════════════════════════════════════════════════

    public class MachineSection {
        public String machineName { get; private set; }
        public String machineImage { get; private set; }
        public String fichaTecnica { get; private set; }
        public Integer quantity { get; private set; }
        public List<ServiceLine> serviceLines { get; private set; }
        public List<String> aporteLines { get; private set; }

        public MachineSection(Product2 machine, Integer qty, List<ComodatoOverrideResolver.LineaResuelta> comodatos) {
            this.machineName = machine.Name;
            this.machineImage = machine.Imagen_Propuesta__c;
            this.fichaTecnica = machine.Descripci_n_Larga__c;
            this.quantity = qty;
            this.serviceLines = new List<ServiceLine>();
            this.aporteLines = new List<String>();

            for (ComodatoOverrideResolver.LineaResuelta c : comodatos) {
                if (c.tipoDeAsociacion == 'Insumo Mensual') {
                    serviceLines.add(new ServiceLine(c));
                } else {
                    String qtyStr = (c.cantidadAporte != null && c.cantidadAporte > 0)
                        ? String.valueOf(Integer.valueOf(c.cantidadAporte)) + ' ' : '';
                    aporteLines.add(qtyStr + (c.productoAsociadoNombre != null ? c.productoAsociadoNombre : ''));
                }
            }
        }
    }

    public class ServiceLine {
        public String serviceName { get; private set; }
        public String formattedPrice { get; private set; }
        public String formattedQty { get; private set; }

        // Transparencia del ajuste excepcional: la propuesta debe dejar ver que esta linea
        // difiere de la configuracion estandar, con que valores venia y por que se cambio.
        public Boolean esAjustada { get; private set; }
        public String notaAjuste { get; private set; }

        public ServiceLine(ComodatoOverrideResolver.LineaResuelta c) {
            this.serviceName = c.productoAsociadoNombre != null ? c.productoAsociadoNombre : '';
            Decimal price = c.precioUnitarioNeto != null ? c.precioUnitarioNeto : 0;
            Decimal qty = c.cantidadMinimaMensual != null ? c.cantidadMinimaMensual : 0;
            String uom = c.unidadDeMedida != null ? c.unidadDeMedida : '';
            this.esAjustada = c.tieneAjuste == true;
            this.notaAjuste = this.esAjustada ? construirNota(c) : null;
            this.formattedPrice = formatCLP(price);
            this.formattedQty = String.valueOf(qty.setScale(0)) + ' ' + uom;
        }

        /** Detalle del ajuste: valores anteriores y motivo, solo lo que efectivamente cambio. */
        private String construirNota(ComodatoOverrideResolver.LineaResuelta c) {
            List<String> cambios = new List<String>();
            if (c.getCantidadFueAjustada()) {
                Decimal antes = c.cantidadMinimaMensualOriginal != null ? c.cantidadMinimaMensualOriginal : 0;
                String uomAntes = c.unidadDeMedidaOriginal != null ? c.unidadDeMedidaOriginal : '';
                cambios.add('cantidad estandar ' + String.valueOf(antes.setScale(0)) + ' ' + uomAntes);
            }
            if (c.getUnidadFueAjustada()) {
                cambios.add('unidad estandar ' + (c.unidadDeMedidaOriginal != null ? c.unidadDeMedidaOriginal : ''));
            }
            if (c.getPrecioFueAjustado()) {
                Decimal antes = c.precioUnitarioNetoOriginal != null ? c.precioUnitarioNetoOriginal : 0;
                cambios.add('precio estandar ' + formatCLP(antes));
            }

            String nota = 'Ajuste excepcional';
            if (!cambios.isEmpty()) {
                nota += ' (' + String.join(cambios, '; ') + ')';
            }
            if (String.isNotBlank(c.motivoAjuste)) {
                nota += '. Motivo: ' + c.motivoAjuste;
            }
            if (String.isNotBlank(c.ajustadoPorNombre)) {
                nota += ' \u2014 ' + c.ajustadoPorNombre;
            }
            return nota;
        }
    }

    // ═══════════════════════════════════════════════════════
    // Utilidades
    // ═══════════════════════════════════════════════════════

    private static String formatCLP(Decimal amount) {
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

    private static String formatMultilineText(String value) {
        if (String.isBlank(value)) return '';
        List<String> escapedLines = new List<String>();
        for (String line : value.replace('\r\n', '\n').replace('\r', '\n').split('\n')) {
            escapedLines.add(escapeHtml(line));
        }
        return String.join(escapedLines, '<br/>');
    }

    private static String escapeHtml(String value) {
        if (value == null) return '';
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }
}