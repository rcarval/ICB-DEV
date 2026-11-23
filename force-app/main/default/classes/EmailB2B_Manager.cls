global with sharing class EmailB2B_Manager {

    private class EmailB2B_ManagerException extends Exception {
    }

    @TestVisible
    private static final String MAESTRO_RESOURCE_NAME = 'EmailB2B_Maestro';

    private static final String CASO_DEVOLUCION_CONFIG = 'CASO_DEVOLUCION_PROCESADA';
    private static final String CIERRE_DEVOLUCION_RECHAZO_CONFIG = 'CIERRE_DEVOLUCION_RECHAZO';

    private static final Set<String> TABLA_SOLO_RECLAMADOS = new Set<String>{
        CASO_DEVOLUCION_CONFIG,
        CIERRE_DEVOLUCION_RECHAZO_CONFIG
    };

    private static final Set<String> TABLA_OCULTA_CARD = new Set<String>{
        CIERRE_DEVOLUCION_RECHAZO_CONFIG
    };

    @TestVisible
    private static String testMaestroHtml;

    @TestVisible
    private static List<Correo_B2B_Config__mdt> testConfigs;

    @TestVisible
    private static Id testOrgWideEmailId;

    global class Request {
        @InvocableVariable(label='Case Id' description='Id del Caso del que se obtienen los datos' required=true)
        public Id recordId;

        @InvocableVariable(label='Destinatario' description='Email(s) de destino separados por coma' required=true)
        public String toAddress;

        @InvocableVariable(label='Tipo (opcional)' description='DeveloperName del registro Correo_B2B_Config__mdt. Si viene vacío se discrimina automáticamente por Status/criterios')
        public String tipo;

        @InvocableVariable(label='CC' description='Email(s) en Copia separados por coma')
        public String ccAddress;

        @InvocableVariable(label='CCO' description='Email(s) en Copia oculta separados por coma')
        public String bccAddress;

        @InvocableVariable(label='URL Header (opcional)' description='Override de URL de la imagen de cabecera')
        public String urlHeader;

        @InvocableVariable(label='URL Logo (opcional)' description='Override de URL de la imagen del logo')
        public String urlLogo;

        @InvocableVariable(label='Enviar directamente' description='true = envía el correo; false = solo retorna el HTML generado')
        public Boolean enviarDirectamente;
    }

    global class Result {
        @InvocableVariable(label='OK' description='true si se generó/envio el correo sin errores')
        public Boolean ok;
        @InvocableVariable(label='Subject' description='Asunto generado del correo')
        public String subject;
        @InvocableVariable(label='HTML' description='HTML renderizado del correo')
        public String bodyHtml;
        @InvocableVariable(label='Destinatario' description='Dirección del destinatario')
        public String toAddress;
        @InvocableVariable(label='MessageId' description='MessageId del envío cuando fue fallido/neutral')
        public String messageId;
        @InvocableVariable(label='Errores' description='Errores ocurridos durante la generación')
        public List<String> errors;
    }

    @InvocableMethod(label='Generar y Enviar Correo B2B')
    public static List<Result> generateEmails(List<Request> inputs) {
        List<Result> results = new List<Result>();
        for (Request input : inputs) {
            results.add(process(input));
        }
        return results;
    }

    private static Result process(Request input) {
        Result result = new Result();
        result.ok = false;
        result.errors = new List<String>();

        if (input == null || input.recordId == null || String.isBlank(input.toAddress)) {
            result.errors.add('Debe indicar recordId y toAddress.');
            return result;
        }
        result.toAddress = input.toAddress;

        List<Correo_B2B_Config__mdt> configs = getConfigs();
        if (configs.isEmpty()) {
            result.errors.add('No hay configuraciones Correo_B2B_Config__mdt activas.');
            return result;
        }

        Case caso = queryCase(input.recordId);
        if (caso == null) {
            result.errors.add('No se encontró el Caso ' + input.recordId + '.');
            return result;
        }

        Correo_B2B_Config__mdt config = matchConfig(caso, input.tipo, configs);
        if (config == null) {
            result.errors.add('Ninguna variante Correo_B2B_Config__mdt aplica para el Caso ' + caso.CaseNumber
                + ' (Status=' + caso.Status + ', Procede=' + caso.Procede_el_Reclamo__c + ').');
            return result;
        }

        Map<String, String> dataTokens = buildDataTokens(caso, config);

        List<String> missingTokens = missingRequiredTokens(config.Campos_Obligatorios__c, dataTokens);
        if (!missingTokens.isEmpty()) {
            result.errors.add('Faltan datos obligatorios para la variante [' + config.DeveloperName + ']: '
                + String.join(missingTokens, ', ') + '.');
            return result;
        }

        String maestro = loadMaestro();
        if (String.isBlank(maestro)) {
            result.errors.add('No se encontró el Static Resource ' + MAESTRO_RESOURCE_NAME + '.');
            return result;
        }

        String subject = applyTokens(nvl(config.Subject__c), dataTokens);
        String htmlBody = applyTokens(applyConfigTokens(maestro, config, input), dataTokens);

        if (input.enviarDirectamente == true) {
            List<String> sendErrors = sendEmail(subject, htmlBody, input, config.Adjuntar_NC__c == true);
            if (!sendErrors.isEmpty()) {
                result.errors.addAll(sendErrors);
                return result;
            }
        }

        result.ok = true;
        result.subject = subject;
        result.bodyHtml = htmlBody;
        return result;
    }

    private static Case queryCase(Id recordId) {
        List<Case> casos = [
            SELECT Id, CaseNumber, Status, Account.Name, ProductId, Product.Name,
                   Factura__c,
                   Cantidad_reclamada__c, UM_Unidad_de_Medida__c, Tipo_UM_Reclamo__c,
                   Motivo__c, Motivo_No_procede__c, Procede_el_Reclamo__c, Cumple_los_plazos__c,
                   Fecha_retiro__c, Horario_retiro__c, Nombre_Direcci_n__c, Comuna_sucursal__c,
                   Comentario_devolucion_sin_producto__c, Respuesta_Proveedor__c,
                   Product.Codigo__c, Marca__c, Fecha_Elaboracion_o_Lote__c,
                   Fecha_de_Vencimiento__c, Cantidad_Recepcionada__c, Stock_Actual__c,
                   Investigacion__c, Acciones_Correctivas__c, Acciones_Preventivas__c,
                   Conclusiones__c,
                   Tipo_de_Requerimiento__c, Sub_Categoria__c
            FROM Case
            WHERE Id = :recordId
            LIMIT 1
        ];
        return casos.isEmpty() ? null : casos.get(0);
    }

    private static List<Correo_B2B_Config__mdt> getConfigs() {
        if (testConfigs != null) {
            return testConfigs;
        }
        return [
            SELECT Id, DeveloperName, MasterLabel, Activo__c, Subject__c, Title__c, Preview__c,
                   H1__c, Intro__c, Card_Label__c, Body__c,
                   Col_Ancho_Izq__c, Col_Ancho_Der__c, Card_Pad__c, Lbl_Cantidad__c,
                   Status_Criterio__c, Procede_Criterio__c, Condicion_Campo__c,
                   Campos_Obligatorios__c, Orden__c,
                   Adjuntar_NC__c,
                   URL_Header__c, URL_Logo__c
            FROM Correo_B2B_Config__mdt
            WHERE Activo__c = true
            ORDER BY Orden__c ASC
        ];
    }

    private static Correo_B2B_Config__mdt matchConfig(Case caso, String tipoOverride, List<Correo_B2B_Config__mdt> configs) {
        if (String.isNotBlank(tipoOverride)) {
            for (Correo_B2B_Config__mdt cfg : configs) {
                if (cfg.DeveloperName == tipoOverride) {
                    return cfg;
                }
            }
        }

        for (Correo_B2B_Config__mdt cfg : configs) {
            if (!matchesStatus(cfg, caso)) {
                continue;
            }
            if (!matchesProcede(cfg, caso)) {
                continue;
            }
            if (!matchesCondicion(cfg, caso)) {
                continue;
            }
            return cfg;
        }
        return null;
    }

    private static Boolean matchesStatus(Correo_B2B_Config__mdt cfg, Case caso) {
        if (String.isBlank(cfg.Status_Criterio__c)) {
            return true;
        }
        return cfg.Status_Criterio__c.trim() == caso.Status;
    }

    private static Boolean matchesProcede(Correo_B2B_Config__mdt cfg, Case caso) {
        if (String.isBlank(cfg.Procede_Criterio__c)) {
            return true;
        }
        List<String> valores = cfg.Procede_Criterio__c.split('\\|');
        return valores.contains(caso.Procede_el_Reclamo__c);
    }

    private static Boolean matchesCondicion(Correo_B2B_Config__mdt cfg, Case caso) {
        if (String.isBlank(cfg.Condicion_Campo__c)) {
            return true;
        }
        for (String condicion : cfg.Condicion_Campo__c.split('\\s*;\\s*')) {
            if (String.isBlank(condicion)) {
                continue;
            }
            if (!matchSingleCondicion(condicion, caso)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean matchSingleCondicion(String condicion, Case caso) {
        List<String> partes = condicion.split('\\|');
        if (partes.size() < 2) {
            return false;
        }
        String operador = partes.get(0).trim();
        String campo = partes.get(1).trim();
        Object valor = caso.get(campo);

        if (operador == 'SET') {
            return valor != null;
        }
        if (operador == 'NULL') {
            return valor == null;
        }
        if (operador == 'FALSE') {
            if (valor == null) {
                return true;
            }
            if (valor instanceof Boolean) {
                return !(Boolean) valor;
            }
            String texto = String.valueOf(valor);
            return texto.equalsIgnoreCase('NO') || texto.equalsIgnoreCase('false')
                || texto.equalsIgnoreCase('0') || texto.equalsIgnoreCase('');
        }
        if (operador == 'EQ' || operador == 'NE') {
            String esperado = partes.size() > 2 ? partes.get(2).trim() : '';
            Boolean igual = valor != null && String.valueOf(valor).trim() == esperado;
            return operador == 'EQ' ? igual : !igual;
        }
        if (operador == 'IN' || operador == 'NIN') {
            if (partes.size() < 3) {
                return false;
            }
            String actual = valor == null ? '' : String.valueOf(valor).trim();
            Boolean dentro = false;
            for (String esperado : partes.get(2).split(',')) {
                if (esperado.trim() == actual) {
                    dentro = true;
                    break;
                }
            }
            return operador == 'IN' ? dentro : !dentro;
        }
        return true;
    }

    private static Map<String, String> buildDataTokens(Case caso, Correo_B2B_Config__mdt config) {
        Map<String, String> tokens = new Map<String, String>();
        tokens.put('ACCOUNT_NAME', caso.Account != null ? escapeHtml(caso.Account.Name) : '');
        tokens.put('CASE_NUMBER', escapeHtml(caso.CaseNumber));
        tokens.put('PRODUCT', caso.Product != null ? escapeHtml(caso.Product.Name) : '');

        Decimal cantidad = caso.Cantidad_reclamada__c;
        String unidad = firstNonBlank(caso.UM_Unidad_de_Medida__c, caso.Tipo_UM_Reclamo__c);
        if (esRechazoParcialTotal(caso) && (cantidad == null || String.isBlank(unidad))) {
            for (Detalle_Factura__c det : getDetallesEnProceso(caso.Id)) {
                if (det.Cantidad__c == null) {
                    continue;
                }
                if (cantidad == null) {
                    cantidad = 0;
                }
                cantidad += det.Cantidad__c;
                if (String.isBlank(unidad) && String.isNotBlank(det.Unidad_de_Medida__c)) {
                    unidad = det.Unidad_de_Medida__c;
                }
            }
        }
        tokens.put('CANTIDAD', formatCantidad(cantidad));
        tokens.put('UNIDAD', escapeHtml(unidad));
        tokens.put('MOTIVO', escapeHtml(caso.Motivo__c));
        tokens.put('FECHA_RETIRO', formatDate(caso.Fecha_retiro__c));
        tokens.put('HORARIO', escapeHtml(caso.Horario_retiro__c));
        tokens.put('DIRECCION', escapeHtml(joinAddress(caso.Nombre_Direcci_n__c, caso.Comuna_sucursal__c)));
        tokens.put('OBSERVACION', escapeHtml(caso.Comentario_devolucion_sin_producto__c));
        tokens.put('MOTIVO_NO_PROCEDE', escapeHtml(caso.Motivo_No_procede__c));
        tokens.put('RESPUESTA_PROVEEDOR', escapeHtml(caso.Respuesta_Proveedor__c));
        tokens.put('CODIGO_PRODUCTO', caso.Product != null ? escapeHtml(caso.Product.Codigo__c) : '');
        tokens.put('MARCA', escapeHtml(caso.Marca__c));
        tokens.put('LOTE', formatFieldValue(caso.get('Fecha_Elaboracion_o_Lote__c')));
        tokens.put('FECHA_VENCIMIENTO', formatFieldValue(caso.get('Fecha_de_Vencimiento__c')));
        tokens.put('CANTIDAD_RECEPCIONADA', formatFieldValue(caso.get('Cantidad_Recepcionada__c')));
        tokens.put('STOCK_ACTUAL', formatFieldValue(caso.get('Stock_Actual__c')));
        tokens.put('INVESTIGACION', escapeHtml(caso.Investigacion__c));
        tokens.put('ACCIONES_CORRECTIVAS', escapeHtml(caso.Acciones_Correctivas__c));
        tokens.put('ACCIONES_PREVENTIVAS', escapeHtml(caso.Acciones_Preventivas__c));
        tokens.put('CONCLUSIONES', escapeHtml(caso.Conclusiones__c));
        String tabla = buildTablaDetalles(caso, config != null && TABLA_SOLO_RECLAMADOS.contains(config.DeveloperName));
        tokens.put('TABLA_DETALLES', tabla);
        tokens.put('CARD_VIS', config != null && TABLA_OCULTA_CARD.contains(config.DeveloperName)
            && String.isNotBlank(tabla) ? 'display:none;' : '');
        return tokens;
    }

    private static Boolean esRechazoParcialTotal(Case caso) {
        return caso != null
            && (caso.Sub_Categoria__c == 'Rechazo parcial' || caso.Sub_Categoria__c == 'Rechazo total');
    }

    private static List<Detalle_Factura__c> getDetallesEnProceso(Id caseId) {
        return [
            SELECT Cantidad__c, Unidad_de_Medida__c
            FROM Detalle_Factura__c
            WHERE Caso__c = :caseId
              AND Proceso_de_reclamo__c = true
            ORDER BY Name
        ];
    }

    private static String buildTablaDetalles(Case caso, Boolean soloReclamados) {
        if (!esRechazoParcialTotal(caso) || caso.Factura__c == null) {
            return '';
        }
        List<Detalle_Factura__c> detalles;
        if (soloReclamados && caso.Sub_Categoria__c == 'Rechazo parcial') {
            detalles = [
                SELECT Name, SKU__c, Product__r.Name, Cantidad__c, Unidad_de_Medida__c, Valor_Neto__c
                FROM Detalle_Factura__c
                WHERE Caso__c = :caso.Id
                  AND Proceso_de_reclamo__c = true
                ORDER BY Name
            ];
        } else {
            detalles = [
                SELECT Name, SKU__c, Product__r.Name, Cantidad__c, Unidad_de_Medida__c, Valor_Neto__c
                FROM Detalle_Factura__c
                WHERE Caso__c = :caso.Id
                ORDER BY Name
            ];
        }
        if (detalles.isEmpty()) {
            return '';
        }

        String fuente = 'Verdana,Geneva,Arial,sans-serif';
        String oscuro = '#2B2B2B';
        String cuerpo = '#4A4A4A';
        String filaAlt = '#F7F7F8';

        String html = '<div style="padding-bottom:16px;">'
            + '<div style="font:bold 11px/1.4 ' + fuente + ';letter-spacing:1.2px;color:#8A8A93;text-transform:uppercase;padding-bottom:8px;">Detalle de productos de la factura</div>'
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;font:12px/1.5 ' + fuente + ';">'
            + '<thead><tr>'
            + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:9px 12px;text-align:center;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">#</th>'
            + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:9px 12px;text-align:left;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">SKU</th>'
            + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:9px 12px;text-align:left;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Producto</th>'
            + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:9px 12px;text-align:center;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Cant. | UM</th>'
            + '<th style="background:' + filaAlt + ';color:#8A8A93;padding:9px 12px;text-align:right;font-weight:700;font-size:11px;letter-spacing:1.2px;text-transform:uppercase;border-bottom:1px solid #E3E3E7;">Valor Neto</th>'
            + '</tr></thead><tbody>';

        Integer rowNum = 1;
        Decimal totalNeto = 0;
        for (Detalle_Factura__c det : detalles) {
            Decimal valor = det.Valor_Neto__c != null ? det.Valor_Neto__c : 0;
            totalNeto += valor;
            Decimal cantidadLinea = det.Cantidad__c;
            if (cantidadLinea == null && caso.Sub_Categoria__c == 'Rechazo parcial') {
                cantidadLinea = caso.Cantidad_reclamada__c;
            }
            html += '<tr>'
                + '<td style="padding:8px 12px;border-bottom:1px solid #ECECEF;text-align:center;color:' + cuerpo + ';">' + rowNum + '</td>'
                + '<td style="padding:8px 12px;border-bottom:1px solid #ECECEF;color:' + oscuro + ';">' + escapeHtml(det.SKU__c) + '</td>'
                + '<td style="padding:8px 12px;border-bottom:1px solid #ECECEF;color:' + cuerpo + ';">' + escapeHtml(det.Product__r != null ? det.Product__r.Name : '') + '</td>'
                + '<td style="padding:8px 12px;border-bottom:1px solid #ECECEF;text-align:center;color:' + cuerpo + ';">' + formatCantidad(cantidadLinea)
                + (String.isNotBlank(det.Unidad_de_Medida__c) ? ' | ' + escapeHtml(det.Unidad_de_Medida__c) : '') + '</td>'
                + '<td style="padding:8px 12px;border-bottom:1px solid #ECECEF;text-align:right;color:' + oscuro + ';">$' + valor.setScale(0).format() + '</td>'
                + '</tr>';
            rowNum++;
        }

        html += '</tbody><tfoot><tr>'
            + '<td colspan="4" style="padding:9px 12px;background:' + filaAlt + ';text-align:right;font-weight:700;color:' + oscuro + ';">Total</td>'
            + '<td style="padding:9px 12px;background:' + filaAlt + ';text-align:right;font-weight:700;color:' + oscuro + ';">$' + totalNeto.setScale(0).format() + '</td>'
            + '</tr></tfoot></table></div>';
        return html;
    }

    private static String applyConfigTokens(String maestro, Correo_B2B_Config__mdt cfg, Request input) {
        Map<String, String> cfgTokens = new Map<String, String>();
        cfgTokens.put('TITLE', nvl(cfg.Title__c));
        cfgTokens.put('PREVIEW', nvl(cfg.Preview__c));
        cfgTokens.put('H1', nvl(cfg.H1__c));
        cfgTokens.put('INTRO', nvl(cfg.Intro__c));
        cfgTokens.put('CARD_LABEL', nvl(cfg.Card_Label__c));
        cfgTokens.put('BODY', nvl(cfg.Body__c));
        cfgTokens.put('COL_IZQ', intStr(cfg.Col_Ancho_Izq__c));
        cfgTokens.put('COL_DER', intStr(cfg.Col_Ancho_Der__c));
        cfgTokens.put('CARD_PAD', intStr(cfg.Card_Pad__c));
        cfgTokens.put('LBL_CANTIDAD', nvl(cfg.Lbl_Cantidad__c));
        cfgTokens.put('URL_HEADER', firstNonBlank(input != null ? input.urlHeader : null, cfg.URL_Header__c));
        cfgTokens.put('URL_LOGO', firstNonBlank(input != null ? input.urlLogo : null, cfg.URL_Logo__c));
        return applyTokens(maestro, cfgTokens);
    }

    private static String applyTokens(String content, Map<String, String> tokens) {
        String result = content;
        for (String key : tokens.keySet()) {
            result = result.replace('{{' + key + '}}', tokens.get(key));
        }
        return result;
    }

    private static List<String> missingRequiredTokens(String camposObligatorios, Map<String, String> dataTokens) {
        List<String> missing = new List<String>();
        if (String.isBlank(camposObligatorios)) {
            return missing;
        }
        for (String token : camposObligatorios.split('\\s*;\\s*')) {
            if (String.isBlank(token)) {
                continue;
            }
            String value = dataTokens.get(token.trim());
            if (String.isBlank(value)) {
                missing.add(token.trim());
            }
        }
        return missing;
    }

    private static String loadMaestro() {
        if (testMaestroHtml != null) {
            return testMaestroHtml;
        }
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :MAESTRO_RESOURCE_NAME
            LIMIT 1
        ];
        if (resources.isEmpty() || resources.get(0).Body == null) {
            return null;
        }
        return resources.get(0).Body.toString();
    }

    private static List<String> sendEmail(String subject, String htmlBody, Request input, Boolean attachNC) {
        List<String> errors = new List<String>();

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        Id oweaId = getOrgWideEmailAddressId();
        if (oweaId != null) {
            email.setOrgWideEmailAddressId(oweaId);
        }
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setToAddresses(input.toAddress.split(','));
        if (String.isNotBlank(input.ccAddress)) {
            email.setCcAddresses(input.ccAddress.split(','));
        }
        if (String.isNotBlank(input.bccAddress)) {
            email.setBccAddresses(input.bccAddress.split(','));
        }

        List<Messaging.EmailFileAttachment> attachments = getAttachmentsFor(input, attachNC);
        if (!attachments.isEmpty()) {
            email.setFileAttachments(attachments);
        }

        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            Messaging.SendEmailResult sendResult = results.isEmpty() ? null : results.get(0);
            if (sendResult == null || !sendResult.isSuccess()) {
                String errores = '';
                if (sendResult != null && sendResult.getErrors() != null) {
                    for (Messaging.SendEmailError err : sendResult.getErrors()) {
                        if (String.isNotBlank(errores)) {
                            errores += ' / ';
                        }
                        errores += err.getMessage();
                    }
                }
                errors.add('Falló el envío del correo: ' + (String.isBlank(errores) ? 'error desconocido' : errores));
            }
        } catch (Exception ex) {
            errors.add('Excepción al enviar el correo: ' + ex.getMessage());
        }
        return errors;
    }

    private static Id getOrgWideEmailAddressId() {
        if (testOrgWideEmailId != null) {
            return testOrgWideEmailId;
        }
        // José Illanes - 14/10/2026 - MCS-164: usuarios sin acceso a OrgWideEmailAddress (ej. perfil Asesor comercial)
        // provocaban un QueryException que abortaba el flujo de ingreso de caso. Si la consulta falla se usa el Id
        // configurado en la etiqueta EmailB2B_OWEA_Notificaciones_Id; si tampoco está disponible, se devuelve null
        // y el correo sale con el remitente por defecto.
        try {
            List<OrgWideEmailAddress> oweaList = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = 'notificaciones@icbfs.cl'
                LIMIT 1
            ];
            return oweaList.isEmpty() ? null : oweaList.get(0).Id;
        } catch (QueryException ex) {
            return getOrgWideEmailAddressIdRespaldo();
        }
    }

    private static Id getOrgWideEmailAddressIdRespaldo() {
        String valor = System.Label.EmailB2B_OWEA_Notificaciones_Id;
        if (String.isBlank(valor)) {
            return null;
        }
        try {
            return (Id) valor.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    private static String escapeHtml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('\n', '<br>');
    }

    private static String formatDate(Date value) {
        if (value == null) {
            return '';
        }
        List<String> meses = new List<String>{
            'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
            'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
        };
        return value.day() + ' de ' + meses[value.month() - 1] + ' de ' + value.year();
    }

    private static String formatCantidad(Decimal value) {
        if (value == null) {
            return '';
        }
        return value.stripTrailingZeros().toPlainString();
    }

    private static String formatFieldValue(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Date) {
            return formatDate((Date) value);
        }
        if (value instanceof Decimal) {
            return formatCantidad((Decimal) value);
        }
        if (value instanceof Integer) {
            return formatCantidad(Decimal.valueOf((Integer) value));
        }
        if (value instanceof Long) {
            return formatCantidad(Decimal.valueOf((Long) value));
        }
        if (value instanceof Double) {
            return formatCantidad(Decimal.valueOf((Double) value));
        }
        return escapeHtml(String.valueOf(value));
    }

    @TestVisible
    private static List<Messaging.EmailFileAttachment> getAttachmentsFor(Request input, Boolean attachNC) {
        if (attachNC != true) {
            return new List<Messaging.EmailFileAttachment>();
        }
        return getNCFileAttachments(input.recordId);
    }

    @TestVisible
    private static List<Messaging.EmailFileAttachment> getNCFileAttachments(Id caseId) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        if (caseId == null) {
            return attachments;
        }
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
        ]) {
            docIds.add(link.ContentDocumentId);
        }
        if (docIds.isEmpty()) {
            return attachments;
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, PathOnClient, FileExtension, FileType, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
                AND NC_cargada__c = true
                AND IsLatest = true
            ORDER BY CreatedDate DESC
        ];
        for (ContentVersion cv : versions) {
            String fileName = String.isNotBlank(cv.PathOnClient)
                ? cv.PathOnClient
                : cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');

            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(fileName);
            if (cv.FileExtension == 'pdf') {
                efa.setContentType('application/pdf');
            }
            efa.setBody(cv.VersionData);
            attachments.add(efa);
        }
        return attachments;
    }

    private static String joinAddress(String direccion, String comuna) {
        List<String> partes = new List<String>();
        if (String.isNotBlank(direccion)) {
            partes.add(direccion);
        }
        if (String.isNotBlank(comuna)) {
            partes.add(comuna);
        }
        return String.join(partes, ', ');
    }

    private static String intStr(Decimal value) {
        return value == null ? '' : String.valueOf(value.longValue());
    }

    private static String nvl(String value) {
        return value == null ? '' : value;
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : nvl(b);
    }
}