@IsTest
private with sharing class EmailB2B_ManagerTest {

    private static final String MAESTRO_HTML =
        '<html><title>{{TITLE}}</title><div>{{PREVIEW}}</div>'
        + '<img src="{{URL_HEADER}}"><h1>{{H1}}</h1>'
        + '<div>Estimado/a {{ACCOUNT_NAME}}:</div><div>{{INTRO}}</div>'
        + '<div style="padding:26px 32px 0;{{CARD_VIS}}">'
        + '<table width="{{COL_IZQ}}">{{CARD_LABEL}}</table>'
        + '<table width="{{COL_DER}}">Caso N° {{CASE_NUMBER}}</table>'
        + '<div>{{LBL_CANTIDAD}}</div>'
        + '<div>{{PRODUCT}}</div><div>{{CANTIDAD}} {{UNIDAD}}</div>'
        + '</div>'
        + '<div>{{BODY}}</div><img src="{{URL_LOGO}}">';

    private static final String CASO_REGISTRADO_HTML =
        '<html><body>'
        + '<div>Tu caso N° {{CASE_NUMBER}} fue registrado y ya está en gestión.</div>'
        + '<div>Tu caso ha sido registrado</div>'
        + '<div>Estimado/a {{ACCOUNT_NAME}}:</div>'
        + '<div>{{FECHA_INGRESO}}</div><div>{{ESTADO}}</div>'
        + '<div>{{TIPO_CASO}}</div><div>{{MOTIVO}}</div>'
        + '<div>{{PRODUCT}}</div><div>{{CANTIDAD}} {{UNIDAD}}</div>'
        + '<div>{{DESCRIPCION}}</div>'
        + '<div>1 Registro del caso · Completado</div>'
        + '<img src="{{URL_LOGO}}">'
        + '</body></html>';

    @TestSetup
    static void setup() {
        Account cuenta = new Account(Name = 'Cliente B2B Test');
        insert cuenta;

        Product2 producto = new Product2(
            Name = 'Salmon fresco',
            ProductCode = 'SAL-001',
            Codigo__c = 'SAL-001',
            IsActive = true
        );
        insert producto;
    }

    static Account getCuenta() {
        return [SELECT Id, Name FROM Account LIMIT 1];
    }

    static Product2 getProducto() {
        return [SELECT Id, Name FROM Product2 LIMIT 1];
    }

    static Case crearCaso(String status, String procede, Boolean cumplePlazos,
            String motivoNoProcede, String respuestaProveedor, String comentarioDev) {
        Case c = new Case(
            AccountId = getCuenta().Id,
            ProductId = getProducto().Id,
            Subject = 'Caso B2B Test',
            Status = status,
            Origin = 'Email',
            Tipo_de_Requerimiento__c = 'Reclamo',
            Sub_Categoria__c = 'Rechazo total',
            Cantidad_reclamada__c = 5,
            UM_Unidad_de_Medida__c = 'Kilogramos',
            Tipo_UM_Reclamo__c = 'Kilos',
            Motivo__c = 'Producto vencido',
            Procede_el_Reclamo__c = procede,
            Cumple_los_plazos__c = (cumplePlazos == false) ? 'NO' : 'SI',
            Motivo_No_procede__c = motivoNoProcede,
            Respuesta_Proveedor__c = respuestaProveedor,
            Comentario_devolucion_sin_producto__c = comentarioDev
        );

        if (status == 'En retiro') {
            c.Fecha_retiro__c = Date.newInstance(2026, 9, 30);
            c.Horario_retiro__c = '09:00 - 12:00';
        }

        insert c;
        return c;
    }

    static Facturas__c crearFactura(String direccion) {
        Facturas__c factura = new Facturas__c(
            Cliente__c = getCuenta().Id,
            Direccion__c = direccion
        );
        insert factura;
        return factura;
    }

    static void crearDetalles(Case c, Id facturaId) {
        insert new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c = facturaId, Caso__c = c.Id, SKU__c = 'DP-A',
                Unidad_de_Medida__c = 'KG', Cantidad__c = 2, Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = facturaId, Caso__c = c.Id, SKU__c = 'DP-B',
                Unidad_de_Medida__c = 'KG', Cantidad__c = 4, Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = facturaId, Caso__c = c.Id, SKU__c = 'DP-C',
                Unidad_de_Medida__c = 'CA', Cantidad__c = 9, Proceso_de_reclamo__c = false
            )
        };
    }

    static Case crearCasoCierreDevolucion(String subCategoria, String respuestaProveedor) {
        Case c = crearCaso('Escalamiento', 'Si, sin retiro', true, null, respuestaProveedor, null);
        Facturas__c factura = crearFactura('DIR-CIERRE');
        c.Tipo_de_Requerimiento__c = 'Devoluciones';
        c.Sub_Categoria__c = subCategoria;
        c.Factura__c = factura.Id;
        update c;
        crearDetalles(c, factura.Id);
        return c;
    }

    static Case crearCasoCierreDevolucionConDetalleAjeno(String subCategoria) {
        Case c = crearCasoCierreDevolucion(subCategoria, null);
        Case otro = crearCaso('Escalamiento', 'Si, con retiro', true, null, null, null);
        otro.Tipo_de_Requerimiento__c = 'Devoluciones';
        otro.Sub_Categoria__c = subCategoria;
        otro.Factura__c = c.Factura__c;
        update otro;
        insert new Detalle_Factura__c(
            Factura__c = c.Factura__c, Caso__c = otro.Id, SKU__c = 'DP-AJENO',
            Unidad_de_Medida__c = 'KG', Cantidad__c = 99, Proceso_de_reclamo__c = true
        );
        return c;
    }

    static List<Correo_B2B_Config__mdt> buildConfigs() {
        List<Correo_B2B_Config__mdt> configs = new List<Correo_B2B_Config__mdt>();

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CIERRE_DEVOLUCION_RECHAZO',
            MasterLabel = 'Cierre de devolución por rechazo',
            Activo__c = true,
            Subject__c = 'Cierre de caso N° {{CASE_NUMBER}} – ICB Food Service',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Le informamos que su caso N° {{CASE_NUMBER}} ha finalizado su gestión y se da por cerrado.',
            Body__c = '{{TABLA_DETALLES}}'
                + '<p>Ante cualquier duda respecto a la resolución de su caso, puede contactarnos a través de los canales indicados a continuación.</p>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Escalamiento',
            Procede_Criterio__c = 'Si, con retiro|Si, sin retiro',
            Condicion_Campo__c = 'NULL|Respuesta_Proveedor__c;EQ|Tipo_de_Requerimiento__c|Devoluciones;IN|Sub_Categoria__c|Rechazo parcial,Rechazo total',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME',
            Adjuntar_NC__c = true,
            Orden__c = 0
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'RETIRO_PROGRAMADO',
            MasterLabel = 'Tu retiro ha sido programado',
            Activo__c = true,
            Subject__c = 'Tu retiro ha sido programado - Caso N° {{CASE_NUMBER}}',
            Title__c = 'ICB Food Service — Tu retiro ha sido programado',
            Preview__c = 'Su caso ha sido aprobado.',
            H1__c = 'Tu retiro ha sido programado',
            Intro__c = 'Le informamos que su caso N° {{CASE_NUMBER}} fue aprobado.',
            Card_Label__c = 'Detalle del retiro',
            Body__c = '<h2>Datos del retiro</h2>'
                + '<div style="background:#F7F7F8;border-top:3px solid #E40147;border-radius:8px;">'
                + '<table role="presentation" width="100%"><tr>'
                + '<td width="33%" style="padding:16px;"><div style="color:#E40147;text-transform:uppercase;">Fecha</div><div style="color:#2B2B2B;">{{FECHA_RETIRO}}</div></td>'
                + '<td width="34%" style="padding:16px;"><div style="color:#E40147;text-transform:uppercase;">Horario</div><div style="color:#2B2B2B;">{{HORARIO}}</div></td>'
                + '<td width="33%" style="padding:16px;"><div style="color:#E40147;text-transform:uppercase;">Dirección</div><div style="color:#2B2B2B;">{{DIRECCION}}</div></td>'
                + '</tr></table></div>'
                + '<div class="body-txt" style="padding-top:16px;">Le solicitamos mantener el producto disponible.</div>',
            Col_Ancho_Izq__c = 42,
            Col_Ancho_Der__c = 58,
            Card_Pad__c = 22,
            Lbl_Cantidad__c = 'Cantidad',
            Status_Criterio__c = 'En retiro',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;FECHA_RETIRO;HORARIO',
            Orden__c = 1,
            URL_Header__c = 'https://img.example/header.png',
            URL_Logo__c = 'https://img.example/logo.png'
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'DEVOLUCION_PROCESADA',
            MasterLabel = 'Tu devolución ha sido procesada',
            Activo__c = true,
            Subject__c = 'Tu devolución ha sido procesada - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu devolución ha sido procesada',
            Intro__c = 'Le informamos que su devolución fue procesada.',
            Body__c = '<h2>Forma de abono</h2>'
                + '<div style="background:#F7F7F8;border-left:4px solid #E40147;border-radius:8px;padding:16px;">'
                + '<div style="color:#E40147;text-transform:uppercase;">Nota de Crédito</div>'
                + '<div style="color:#2B2B2B;">Crédito a [X] días, transferencia, cheque o contado</div>'
                + '<div style="color:#4A4A4A;">Se emite una Nota de Crédito, la cual se abona a su cuenta.</div></div>'
                + '<div style="background:#F7F7F8;border-left:4px solid #E40147;border-radius:8px;padding:16px;">'
                + '<div style="color:#E40147;text-transform:uppercase;">Reembolso a tu medio de pago</div>'
                + '<div style="color:#2B2B2B;">OneClick (débito o crédito)</div>'
                + '<div style="color:#4A4A4A;">El monto se reembolsa al mismo medio de pago.</div></div>',
            Col_Ancho_Izq__c = 42,
            Col_Ancho_Der__c = 58,
            Card_Pad__c = 22,
            Lbl_Cantidad__c = 'Cantidad',
            Status_Criterio__c = 'En devolución',
            Condicion_Campo__c = 'NE|Tipo_de_Requerimiento__c|Devoluciones',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD',
            Adjuntar_NC__c = false,
            Orden__c = 2
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CASO_DEVOLUCION_PROCESADA',
            MasterLabel = 'Caso de devolución procesado',
            Activo__c = true,
            Subject__c = 'Tu caso de devolución ha sido procesado - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso de devolución ha sido procesado',
            Intro__c = 'Le informamos que su caso de devolución fue procesado.',
            Body__c = '{{TABLA_DETALLES}}<h2>Forma de abono</h2>'
                + '<div style="background:#F7F7F8;border-left:4px solid #E40147;border-radius:8px;padding:16px;">'
                + '<div style="color:#E40147;text-transform:uppercase;">Nota de Crédito</div>'
                + '<div style="color:#2B2B2B;">Crédito, transferencia, cheque o contado</div></div>',
            Col_Ancho_Izq__c = 42,
            Col_Ancho_Der__c = 58,
            Card_Pad__c = 22,
            Lbl_Cantidad__c = 'Cantidad',
            Status_Criterio__c = 'En devolución',
            Condicion_Campo__c = 'EQ|Tipo_de_Requerimiento__c|Devoluciones',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD',
            Adjuntar_NC__c = false,
            Orden__c = 2
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CASO_REGISTRADO',
            MasterLabel = 'Tu caso ha sido registrado',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido registrado - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha sido registrado',
            Intro__c = 'Su caso N° {{CASE_NUMBER}} fue registrado.',
            Body__c = '<h2>Motivo del reclamo</h2><p>{{MOTIVO}}</p>',
            Col_Ancho_Izq__c = 42,
            Col_Ancho_Der__c = 58,
            Card_Pad__c = 22,
            Lbl_Cantidad__c = 'Cantidad',
            Status_Criterio__c = 'Análisis',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;MOTIVO',
            URL_Logo__c = 'https://raw.githubusercontent.com/sebaCode0297/ICBFS_IMG/main/logo-footer.png',
            Orden__c = 3
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CASO_CERRADO_SIN_RETIRO',
            MasterLabel = 'Tu caso ha sido cerrado sin retiro',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido cerrado - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Su caso finalizó su gestión.',
            Body__c = '<h2>Motivo del cierre</h2><p>Observación: {{OBSERVACION}}</p>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Closed',
            Condicion_Campo__c = 'SET|Comentario_devolucion_sin_producto__c',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;OBSERVACION',
            Adjuntar_NC__c = true,
            Orden__c = 4
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CIERRE_NO_PROCEDE_PLAZO',
            MasterLabel = 'Tu caso ha sido cerrado - No procede por plazo',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido cerrado - No procede por plazo - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Su caso finalizó su gestión.',
            Body__c = '<h2>Resolución: No procede por plazo</h2><p>Fue ingresado fuera de plazo.</p>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Closed',
            Procede_Criterio__c = 'No, no procede',
            Condicion_Campo__c = 'FALSE|Cumple_los_plazos__c',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD',
            Adjuntar_NC__c = true,
            Orden__c = 5
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CIERRE_NO_PROCEDE_CALIDAD',
            MasterLabel = 'Tu caso ha sido cerrado - No procede por análisis de calidad',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido cerrado - No procede por análisis de calidad - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Su caso finalizó su gestión.',
            Body__c = '<h2>Resolución: No procede por análisis de calidad</h2><p>{{MOTIVO_NO_PROCEDE}}</p>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Escalamiento',
            Procede_Criterio__c = 'No, no procede',
            Condicion_Campo__c = 'SET|Motivo_No_procede__c',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;MOTIVO_NO_PROCEDE',
            Adjuntar_NC__c = true,
            Orden__c = 6
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CIERRE_PROCEDE_CON_PROVEEDOR',
            MasterLabel = 'Tu caso ha sido cerrado - Procede con respuesta del proveedor',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido cerrado - Procede con respuesta del proveedor - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Su caso finalizó su gestión.',
            Body__c = '<h2>Resolución del caso</h2><div style="background:#F7F7F8;border-left:4px solid #E40147;border-radius:6px;padding:14px 16px;">{{RESPUESTA_PROVEEDOR}}</div><h2>Detalle del caso</h2><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;"><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;border-bottom:1px solid #EBEBEE;">Código de producto</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;border-bottom:1px solid #EBEBEE;">{{CODIGO_PRODUCTO}}</td></tr><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;border-bottom:1px solid #EBEBEE;">Nombre y marca</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;border-bottom:1px solid #EBEBEE;">{{PRODUCT}} | {{MARCA}}</td></tr><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;border-bottom:1px solid #EBEBEE;">Fecha de elaboración o lote</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;border-bottom:1px solid #EBEBEE;">{{LOTE}}</td></tr><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;border-bottom:1px solid #EBEBEE;">Fecha de vencimiento</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;border-bottom:1px solid #EBEBEE;">{{FECHA_VENCIMIENTO}}</td></tr><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;border-bottom:1px solid #EBEBEE;">Cantidad recepcionada</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;border-bottom:1px solid #EBEBEE;">{{CANTIDAD_RECEPCIONADA}}</td></tr><tr><td style="padding:10px 14px;background:#F7F7F8;font:bold 11px/1.4 Verdana, Geneva, Arial, sans-serif;color:#8A8A93;text-transform:uppercase;">Stock actual</td><td style="padding:10px 14px;font:13.5px/1.6 Verdana, Geneva, Arial, sans-serif;">{{STOCK_ACTUAL}}</td></tr></table><div class="h2" style="font:bold 19px/1.3 Verdana, Geneva, Arial, sans-serif;color:#2B2B2B;padding-bottom:12px;">Informe de la investigación</div><div style="margin:0 0 10px;background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid #E40147;border-radius:8px;"><div style="padding:12px 16px 0;font:bold 12.5px/1.4 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;color:#2B2B2B;text-transform:uppercase;"><span style="display:inline-block;background:#E40147;color:#FFFFFF;font:bold 11.5px/1.2 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;padding:4px 9px;border-radius:999px;margin-right:9px;">1</span>Investigación</div><div style="padding:8px 16px 13px;font:13.5px/1.7 Verdana, Geneva, Arial, sans-serif;color:#4A4A4A;">{{INVESTIGACION}}</div></div><div style="margin:0 0 10px;background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid #E40147;border-radius:8px;"><div style="padding:12px 16px 0;font:bold 12.5px/1.4 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;color:#2B2B2B;text-transform:uppercase;"><span style="display:inline-block;background:#E40147;color:#FFFFFF;font:bold 11.5px/1.2 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;padding:4px 9px;border-radius:999px;margin-right:9px;">2</span>Acciones correctivas</div><div style="padding:8px 16px 13px;font:13.5px/1.7 Verdana, Geneva, Arial, sans-serif;color:#4A4A4A;">{{ACCIONES_CORRECTIVAS}}</div></div><div style="margin:0 0 10px;background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid #E40147;border-radius:8px;"><div style="padding:12px 16px 0;font:bold 12.5px/1.4 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;color:#2B2B2B;text-transform:uppercase;"><span style="display:inline-block;background:#E40147;color:#FFFFFF;font:bold 11.5px/1.2 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;padding:4px 9px;border-radius:999px;margin-right:9px;">3</span>Acciones preventivas</div><div style="padding:8px 16px 13px;font:13.5px/1.7 Verdana, Geneva, Arial, sans-serif;color:#4A4A4A;">{{ACCIONES_PREVENTIVAS}}</div></div><div style="margin:0 0 10px;background:#F7F7F8;border:1px solid #EBEBEE;border-left:4px solid #E40147;border-radius:8px;"><div style="padding:12px 16px 0;font:bold 12.5px/1.4 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;color:#2B2B2B;text-transform:uppercase;"><span style="display:inline-block;background:#E40147;color:#FFFFFF;font:bold 11.5px/1.2 Verdana, Geneva, Arial, sans-serif;letter-spacing:0.5px;padding:4px 9px;border-radius:999px;margin-right:9px;">4</span>Conclusiones</div><div style="padding:8px 16px 13px;font:13.5px/1.7 Verdana, Geneva, Arial, sans-serif;color:#4A4A4A;">{{CONCLUSIONES}}</div></div>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Escalamiento',
            Procede_Criterio__c = 'Si, con retiro|Si, sin retiro',
            Condicion_Campo__c = 'SET|Respuesta_Proveedor__c',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;RESPUESTA_PROVEEDOR',
            Adjuntar_NC__c = true,
            Orden__c = 7
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'CIERRE_PROCEDE_SIN_PROVEEDOR',
            MasterLabel = 'Tu caso ha sido cerrado - Procede sin respuesta del proveedor',
            Activo__c = true,
            Subject__c = 'Tu caso ha sido cerrado - Procede sin respuesta del proveedor - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu caso ha finalizado',
            Intro__c = 'Su caso finalizó su gestión.',
            Body__c = '<p>Su reclamo ha sido acogido favorablemente y con esto el caso se da por cerrado.</p>'
                + '{{TABLA_DETALLES}}'
                + '<p>Ante cualquier duda respecto a la resolución de su caso, puede contactarnos a través de los canales indicados a continuación.</p>',
            Col_Ancho_Izq__c = 38,
            Col_Ancho_Der__c = 62,
            Card_Pad__c = 16,
            Lbl_Cantidad__c = 'Cant.',
            Status_Criterio__c = 'Escalamiento',
            Procede_Criterio__c = 'Si, con retiro|Si, sin retiro',
            Condicion_Campo__c = 'NULL|Respuesta_Proveedor__c',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD',
            Adjuntar_NC__c = true,
            Orden__c = 8
        ));

        configs.add(new Correo_B2B_Config__mdt(
            DeveloperName = 'RETIRO_REPROGRAMADO',
            MasterLabel = 'Tu retiro ha sido reprogramado',
            Activo__c = true,
            Subject__c = 'Tu retiro ha sido reprogramado - Caso N° {{CASE_NUMBER}}',
            H1__c = 'Tu retiro ha sido reprogramado',
            Intro__c = 'Le informamos que el retiro del producto de su caso N° {{CASE_NUMBER}} ha sido reprogramado y se ha coordinado la gestión correspondiente.',
            Body__c = '<h2>Detalle del retiro</h2><p>Producto: {{PRODUCT}}<br>Cantidad: {{CANTIDAD}} | {{UNIDAD}}<br>Fecha de retiro: {{FECHA_RETIRO}}<br>Horario de retiro: {{HORARIO}}<br>Dirección: {{DIRECCION}}</p><p>Le solicitamos mantener el producto disponible y conservado bajo las mismas condiciones de temperatura en que fue recibido, a fin de concretar la gestión sin inconvenientes.</p>',
            Col_Ancho_Izq__c = 42,
            Col_Ancho_Der__c = 58,
            Card_Pad__c = 22,
            Lbl_Cantidad__c = 'Cantidad',
            Status_Criterio__c = 'En retiro',
            Campos_Obligatorios__c = 'CASE_NUMBER;ACCOUNT_NAME;PRODUCT;CANTIDAD;UNIDAD;FECHA_RETIRO;HORARIO',
            Orden__c = 9
        ));

        return configs;
    }

    static void inyectarMocks() {
        EmailB2B_Manager.testConfigs = buildConfigs();
        EmailB2B_Manager.testMaestroHtml = MAESTRO_HTML;
        EmailB2B_Manager.testMaestroPorConfig = new Map<String, String>{
            EmailB2B_Manager.CASO_REGISTRADO_RESOURCE_NAME => CASO_REGISTRADO_HTML
        };
    }

    static List<EmailB2B_Manager.Result> invocar(Id casoId) {
        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = casoId;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        return EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req });
    }

    @IsTest
    static void testRetiroProgramado() {
        inyectarMocks();
        Case c = crearCaso('En retiro', null, null, null, null, null);

        Test.startTest();
        EmailB2B_Manager.Result r = invocar(c.Id).get(0);
        Test.stopTest();

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        String numeroCaso = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
        System.assert(r.subject.contains('Tu retiro ha sido programado'), r.subject);
        System.assert(r.subject.contains('Caso N° ' + numeroCaso), r.subject);
        System.assert(r.bodyHtml.contains('Tu retiro ha sido programado'), 'H1 esperado');
        System.assert(r.bodyHtml.contains(numeroCaso), 'CASE_NUMBER en card');
        System.assert(r.bodyHtml.contains('Cliente B2B Test'), 'ACCOUNT_NAME');
        System.assert(r.bodyHtml.contains('Salmon fresco'), 'PRODUCT');
        System.assert(r.bodyHtml.contains('5'), 'CANTIDAD');
        System.assert(r.bodyHtml.contains('Kilogramos'), 'UNIDAD');
        System.assert(r.bodyHtml.contains('30 de septiembre de 2026'), 'FECHA_RETIRO');
        System.assert(r.bodyHtml.contains('09:00 - 12:00'), 'HORARIO');
        System.assert(r.bodyHtml.contains('border-top:3px solid #E40147'), 'Banda de datos con acento');
        System.assert(r.bodyHtml.contains('Dirección'), 'Micro-label Dirección');
    }

    @IsTest
    static void testDevolucionProcesada() {
        inyectarMocks();
        Case c = crearCaso('En devolución', null, null, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu devolución ha sido procesada'), r.subject);
        System.assert(r.bodyHtml.contains('Forma de abono'), 'BODY esperado');
        System.assert(r.bodyHtml.contains('Nota de Crédito'), 'Panel 1');
        System.assert(r.bodyHtml.contains('Reembolso a tu medio de pago'), 'Panel 2');
        System.assert(r.bodyHtml.contains('border-left:4px solid #E40147'), 'Paneles con acento');
        System.assert(r.bodyHtml.contains('Cantidad'), 'LBL_CANTIDAD 42/58');
        System.assert(!r.subject.contains('Tu caso de devolución'), 'Reclamo no debe usar la plantilla de Caso Devolución');
    }

    @IsTest
    static void testCasoDevolucionProcesada() {
        inyectarMocks();
        Case c = crearCaso('En devolución', null, null, null, null, null);
        c.Tipo_de_Requerimiento__c = 'Devoluciones';
        update c;

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu caso de devolución ha sido procesado'), r.subject);
        System.assert(r.bodyHtml.contains('Forma de abono'), 'BODY esperado');
        System.assert(r.bodyHtml.contains('Nota de Crédito'), 'Panel 1');
    }

    @IsTest
    static void testCasoDevolucionProcesadaRechazoParcialTabla() {
        inyectarMocks();

        Facturas__c factura = new Facturas__c(
            Cliente__c = getCuenta().Id,
            Direccion__c = 'FS-DEVO-001'
        );
        insert factura;

        Case c = crearCaso('En devolución', null, null, null, null, null);
        c.Tipo_de_Requerimiento__c = 'Devoluciones';
        c.Sub_Categoria__c = 'Rechazo parcial';
        c.Factura__c = factura.Id;
        update c;

        insert new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'DP-A', Unidad_de_Medida__c = 'KG', Cantidad__c = 2,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'DP-B', Unidad_de_Medida__c = 'KG', Cantidad__c = 4,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'DP-C', Unidad_de_Medida__c = 'CA', Cantidad__c = 9,
                Proceso_de_reclamo__c = false
            )
        };

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu caso de devolución ha sido procesado'), r.subject);
        System.assert(r.bodyHtml.contains('Detalle de productos de la factura'), 'Titulo tabla');
        System.assert(r.bodyHtml.contains('DP-A') && r.bodyHtml.contains('DP-B'), 'Incluye lineas reclamadas');
        System.assert(!r.bodyHtml.contains('DP-C'), 'Rechazo parcial no incluye lineas fuera del reclamo');
    }

    @IsTest
    static void testCasoDevolucionProcesadaRechazoParcialCantidadFallback() {
        inyectarMocks();

        Facturas__c factura = new Facturas__c(
            Cliente__c = getCuenta().Id,
            Direccion__c = 'FS-DEVO-002'
        );
        insert factura;

        Case c = crearCaso('En devolución', null, null, null, null, null);
        c.Tipo_de_Requerimiento__c = 'Devoluciones';
        c.Sub_Categoria__c = 'Rechazo parcial';
        c.Factura__c = factura.Id;
        c.Cantidad_reclamada__c = 7;
        update c;

        insert new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'DP-UNICA', Unidad_de_Medida__c = 'KG', Cantidad__c = null,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'DP-FUERA', Unidad_de_Medida__c = 'CA', Cantidad__c = 3,
                Proceso_de_reclamo__c = false
            )
        };

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('DP-UNICA'), 'Renderiza la unica linea reclamada');
        System.assert(!r.bodyHtml.contains('DP-FUERA'), 'No renderiza lineas fuera del reclamo');
        System.assert(r.bodyHtml.contains('7 | KG'), 'Cantidad tomada del caso cuando la linea viene vacia');
    }

    @IsTest
    static void testCierreDevolucionRechazoParcialTablaYSinTarjeta() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucion('Rechazo parcial', null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.startsWith('Cierre de caso N'), 'Debe usar CIERRE_DEVOLUCION_RECHAZO: ' + r.subject);
        System.assert(r.bodyHtml.contains('Detalle de productos de la factura'), 'Renderiza la tabla');
        System.assert(r.bodyHtml.contains('DP-A') && r.bodyHtml.contains('DP-B'), 'Incluye lineas reclamadas');
        System.assert(!r.bodyHtml.contains('DP-C'), 'Parcial no incluye lineas fuera del reclamo');
        System.assert(r.bodyHtml.contains('padding:26px 32px 0;display:none;">'), 'Oculta la tarjeta de producto');
    }

    @IsTest
    static void testCierreDevolucionRechazoTotalTablaCompleta() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucion('Rechazo total', null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.startsWith('Cierre de caso N'), 'Debe usar CIERRE_DEVOLUCION_RECHAZO: ' + r.subject);
        System.assert(r.bodyHtml.contains('DP-A') && r.bodyHtml.contains('DP-B') && r.bodyHtml.contains('DP-C'),
            'Rechazo total incluye todas las lineas de la factura');
        System.assert(r.bodyHtml.contains('padding:26px 32px 0;display:none;">'), 'Oculta la tarjeta de producto');
    }

    @IsTest
    static void testCierreDevolucionRechazoNoAplicaConRespuestaDeProveedor() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucion('Rechazo parcial', 'SI');

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Procede con respuesta del proveedor'),
            'Debe caer en CIERRE_PROCEDE_CON_PROVEEDOR: ' + r.subject);
    }

    @IsTest
    static void testCierreDevolucionRechazoNoAplicaConOtrasSubCategorias() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucion('Otro motivo', null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Procede sin respuesta del proveedor'),
            'Debe caer en CIERRE_PROCEDE_SIN_PROVEEDOR: ' + r.subject);
        System.assert(!r.bodyHtml.contains('{{'), 'No deben quedar tokens sin reemplazar');
    }

    @IsTest
    static void testCierreSinProveedorNoDevolucionConservaTarjeta() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Procede sin respuesta del proveedor'),
            'Debe caer en CIERRE_PROCEDE_SIN_PROVEEDOR: ' + r.subject);
        System.assert(r.bodyHtml.contains('padding:26px 32px 0;">'), 'Conserva la tarjeta de producto');
    }

    @IsTest
    static void testCasoDevolucionProcesadaConservaTarjetaConTabla() {
        inyectarMocks();
        Facturas__c factura = crearFactura('DIR-DEVPROC');
        Case c = crearCaso('En devolución', null, null, null, null, null);
        c.Tipo_de_Requerimiento__c = 'Devoluciones';
        c.Sub_Categoria__c = 'Rechazo parcial';
        c.Factura__c = factura.Id;
        update c;
        crearDetalles(c, factura.Id);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('Detalle de productos de la factura'), 'Renderiza la tabla');
        System.assert(r.bodyHtml.contains('padding:26px 32px 0;">'), 'Conserva la tarjeta de producto');
    }

    @IsTest
    static void testTablaParcialExcluyeDetallesDeOtroCaso() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucionConDetalleAjeno('Rechazo parcial');

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('DP-A') && r.bodyHtml.contains('DP-B'),
            'Incluye las lineas reclamadas del caso');
        System.assert(!r.bodyHtml.contains('DP-AJENO'),
            'Excluye lineas de otro caso que comparten la misma factura');
        System.assert(!r.bodyHtml.contains('DP-C'), 'Excluye lineas no reclamadas');
    }

    @IsTest
    static void testTablaTotalExcluyeDetallesDeOtroCaso() {
        inyectarMocks();
        Case c = crearCasoCierreDevolucionConDetalleAjeno('Rechazo total');

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.startsWith('Cierre de caso N'), 'Debe usar CIERRE_DEVOLUCION_RECHAZO: ' + r.subject);
        System.assert(r.bodyHtml.contains('DP-C'), 'Rechazo total incluye tambien las no reclamadas del caso');
        System.assert(!r.bodyHtml.contains('DP-AJENO'),
            'Excluye lineas de otro caso que comparten la misma factura');
    }

    @IsTest
    static void testCasoRegistrado() {
        inyectarMocks();
        Case c = crearCaso('Análisis', null, null, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu caso ha sido registrado'), r.subject);
        System.assert(r.bodyHtml.contains('Producto vencido'), 'MOTIVO esperado');
    }

    @IsTest
    static void testCasoRegistradoFaltaMotivo() {
        inyectarMocks();
        Case c = crearCaso('Análisis', null, null, null, null, null);
        c.Motivo__c = null;
        update c;

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(!r.ok, 'Debe fallar por token obligatorio');
        System.assert(!r.errors.isEmpty(), 'Debe reportar error');
        System.assert(String.join(r.errors, ' ').contains('MOTIVO'), r.errors.toString());
    }

    @IsTest
    static void testNoProcedePorPlazo() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'No, no procede', false, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('por plazo'), 'El criterio plazo manda si Cumple_los_plazos=false');
        System.assert(r.bodyHtml.contains('No procede por plazo'), r.bodyHtml);
    }

    @IsTest
    static void testNoProcedePorCalidad() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'No, no procede', true, 'Producto en buen estado', null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('análisis de calidad'), r.subject);
        System.assert(r.bodyHtml.contains('Producto en buen estado'), 'MOTIVO_NO_PROCEDE');
    }

    @IsTest
    static void testProcedeConProveedor() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('con respuesta del proveedor'), r.subject);
        System.assert(r.bodyHtml.contains('>SI<'), 'RESPUESTA_PROVEEDOR');
    }

    @IsTest
    static void testProcedeConProveedorDetalle() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);
        c.Marca__c = 'ACME';
        c.Fecha_Elaboracion_o_Lote__c = 'LOTE-2026';
        c.Fecha_de_Vencimiento__c = Date.newInstance(2026, 12, 31);
        c.Cantidad_Recepcionada__c = '3';
        c.Stock_Actual__c = '2';
        c.Investigacion__c = 'Se confirmó vencimiento del lote';
        c.Acciones_Correctivas__c = 'Cambio de lote';
        c.Acciones_Preventivas__c = 'Revisión en recepción';
        c.Conclusiones__c = 'Cierre favorable del caso';
        update c;

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('SAL-001'), 'CODIGO_PRODUCTO');
        System.assert(r.bodyHtml.contains('ACME'), 'MARCA');
        System.assert(r.bodyHtml.contains('LOTE-2026'), 'LOTE');
        System.assert(r.bodyHtml.contains('31 de diciembre de 2026'), 'FECHA_VENCIMIENTO');
        System.assert(r.bodyHtml.contains('Cantidad recepcionada') && r.bodyHtml.contains('>3</td>'), 'CANTIDAD_RECEPCIONADA en tabla de detalle');
        System.assert(r.bodyHtml.contains('Stock actual') && r.bodyHtml.contains('>2</td>'), 'STOCK_ACTUAL en tabla de detalle');
        System.assert(r.bodyHtml.contains('Informe de la investigación') && !r.bodyHtml.contains('<details'), 'Informe siempre visible sin colapsable');
        System.assert(r.bodyHtml.contains('border-radius:999px') && r.bodyHtml.contains('>1</span>Investigación'), 'Tarjeta 1 con píldora');
        System.assert(r.bodyHtml.contains('Se confirmó vencimiento del lote'), 'INVESTIGACION');
        System.assert(r.bodyHtml.contains('Cambio de lote'), 'ACCIONES_CORRECTIVAS');
        System.assert(r.bodyHtml.contains('Revisión en recepción'), 'ACCIONES_PREVENTIVAS');
        System.assert(r.bodyHtml.contains('Cierre favorable del caso'), 'CONCLUSIONES');
    }

    @IsTest
    static void testNCFileAttachment() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);

        ContentVersion cv = new ContentVersion(
            Title = 'NC_Test.pdf',
            PathOnClient = 'NC_Test.pdf',
            VersionData = Blob.valueOf('contenido NC'),
            FirstPublishLocationId = c.Id,
            NC_cargada__c = true
        );
        insert cv;

        List<Messaging.EmailFileAttachment> attachments = EmailB2B_Manager.getNCFileAttachments(c.Id);

        System.assertEquals(1, attachments.size());
        System.assertEquals('NC_Test.pdf', attachments[0].getFileName());
        System.assertEquals('contenido NC', attachments[0].getBody().toString());
    }

    @IsTest
    static void testNCFileAttachmentNoMarcado() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);

        ContentVersion cv = new ContentVersion(
            Title = 'FDR Calidad - 123.pdf',
            PathOnClient = 'FDR Calidad - 123.pdf',
            VersionData = Blob.valueOf('contenido FDR'),
            FirstPublishLocationId = c.Id
        );
        insert cv;

        List<Messaging.EmailFileAttachment> attachments = EmailB2B_Manager.getNCFileAttachments(c.Id);

        System.assertEquals(0, attachments.size(), 'Solo se adjunta si NC_cargada__c = true');
    }

    @IsTest
    static void testDevolucionNoAdjuntaNC() {
        inyectarMocks();
        Case c = crearCaso('En devolución', null, null, null, null, null);

        ContentVersion cv = new ContentVersion(
            Title = 'NC_Test.pdf',
            PathOnClient = 'NC_Test.pdf',
            VersionData = Blob.valueOf('contenido NC'),
            FirstPublishLocationId = c.Id,
            NC_cargada__c = true
        );
        insert cv;

        Correo_B2B_Config__mdt devoConfig = null;
        for (Correo_B2B_Config__mdt cfg : EmailB2B_Manager.testConfigs) {
            if (cfg.DeveloperName == 'DEVOLUCION_PROCESADA') {
                devoConfig = cfg;
            }
        }
        System.assert(devoConfig != null, 'Debe existir el config DEVOLUCION_PROCESADA');
        System.assertEquals(false, devoConfig.Adjuntar_NC__c, 'DEVO no debe adjuntar NC');

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;

        List<Messaging.EmailFileAttachment> attachments = EmailB2B_Manager.getAttachmentsFor(
            req, devoConfig.Adjuntar_NC__c == true);

        System.assertEquals(0, attachments.size(), 'DEVO: nunca se adjuntan documentos aunque exista NC marcada');
    }

    @IsTest
    static void testCierreAdjuntaSoloNC() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);

        ContentVersion nc = new ContentVersion(
            Title = 'NC_Test.pdf',
            PathOnClient = 'NC_Test.pdf',
            VersionData = Blob.valueOf('contenido NC'),
            FirstPublishLocationId = c.Id,
            NC_cargada__c = true
        );
        insert nc;

        ContentVersion fdr = new ContentVersion(
            Title = 'FDR Calidad - 123.pdf',
            PathOnClient = 'FDR Calidad - 123.pdf',
            VersionData = Blob.valueOf('contenido FDR'),
            FirstPublishLocationId = c.Id
        );
        insert fdr;

        Correo_B2B_Config__mdt cierreConfig = null;
        for (Correo_B2B_Config__mdt cfg : EmailB2B_Manager.testConfigs) {
            if (cfg.DeveloperName == 'CIERRE_PROCEDE_CON_PROVEEDOR') {
                cierreConfig = cfg;
            }
        }
        System.assert(cierreConfig != null, 'Debe existir el config de cierre');
        System.assertEquals(true, cierreConfig.Adjuntar_NC__c, 'Cierre debe adjuntar NC');

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;

        List<Messaging.EmailFileAttachment> attachments = EmailB2B_Manager.getAttachmentsFor(
            req, cierreConfig.Adjuntar_NC__c == true);

        System.assertEquals(1, attachments.size(), 'Cierre adjunta solo la NC marcada');
        System.assertEquals('NC_Test.pdf', attachments[0].getFileName());
    }

    @IsTest
    static void testProcedeSinProveedor() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, sin retiro', true, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('sin respuesta del proveedor'), r.subject);
        System.assert(r.bodyHtml.contains('y con esto el caso se da por cerrado'), r.bodyHtml);
        System.assert(r.bodyHtml.contains('Ante cualquier duda respecto a la resolución'), r.bodyHtml);
    }

    @IsTest
    static void testProcedeSinProveedorRechazoConDetalle() {
        inyectarMocks();

        Facturas__c factura = new Facturas__c(
            Cliente__c = getCuenta().Id,
            Direccion__c = 'FS-B2B-001'
        );
        insert factura;

        Case c = crearCaso('Escalamiento', 'Si, sin retiro', true, null, null, null);
        c.Sub_Categoria__c = 'Rechazo parcial';
        c.Cantidad_reclamada__c = null;
        c.UM_Unidad_de_Medida__c = null;
        c.Tipo_UM_Reclamo__c = null;
        c.Factura__c = factura.Id;
        update c;

        insert new List<Detalle_Factura__c>{
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'SKU-A', Unidad_de_Medida__c = 'KG', Cantidad__c = 3,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'SKU-B', Unidad_de_Medida__c = 'KG', Cantidad__c = 5,
                Proceso_de_reclamo__c = true
            ),
            new Detalle_Factura__c(
                Factura__c = factura.Id, Caso__c = c.Id,
                SKU__c = 'SKU-C', Unidad_de_Medida__c = 'CA', Cantidad__c = 99,
                Proceso_de_reclamo__c = false
            )
        };

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('8 KG'), 'CANTIDAD+UNIDAD desde Detalle_Factura__c en proceso');
        System.assert(r.bodyHtml.contains('Detalle de productos de la factura'), 'Titulo de la tabla de detalles');
        System.assert(r.bodyHtml.contains('SKU-A') && r.bodyHtml.contains('SKU-B') && r.bodyHtml.contains('SKU-C'),
            'Tabla incluye todos los detalles de la factura');
        System.assert(r.bodyHtml.contains('Total'), 'Fila total de la tabla');
    }

    @IsTest
    static void testProcedeSinProveedorSinFacturaSinTabla() {
        inyectarMocks();
        Case c = crearCaso('Escalamiento', 'Si, sin retiro', true, null, null, null);
        c.Sub_Categoria__c = 'Rechazo total';
        c.Factura__c = null;
        update c;

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(!r.bodyHtml.contains('Detalle de productos de la factura'),
            'Sin factura no debe renderizar tabla de detalles');
    }

    @IsTest
    static void testProcedeConProveedorRechazoConDetalle() {
        inyectarMocks();

        Facturas__c factura = new Facturas__c(
            Cliente__c = getCuenta().Id,
            Direccion__c = 'FS-B2B-002'
        );
        insert factura;

        Case c = crearCaso('Escalamiento', 'Si, con retiro', true, null, 'SI', null);
        c.Sub_Categoria__c = 'Rechazo total';
        c.Cantidad_reclamada__c = null;
        c.UM_Unidad_de_Medida__c = null;
        c.Tipo_UM_Reclamo__c = null;
        c.Factura__c = factura.Id;
        update c;

        insert new Detalle_Factura__c(
            Factura__c = factura.Id, Caso__c = c.Id,
            SKU__c = 'SKU-1', Unidad_de_Medida__c = 'UN', Cantidad__c = 4,
            Proceso_de_reclamo__c = true
        );

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.bodyHtml.contains('4 UN'), 'CANTIDAD+UNIDAD desde Detalle_Factura__c');
        System.assert(r.bodyHtml.contains('>SI<'), 'RESPUESTA_PROVEEDOR');
    }

    @IsTest
    static void testCasoCerradoSinRetiro() {
        inyectarMocks();
        Case c = crearCaso('Closed', null, null, null, null, 'No se encontró el producto');

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu caso ha sido cerrado'), r.subject);
        System.assert(r.bodyHtml.contains('No se encontró el producto'), 'OBSERVACION');
    }

    @IsTest
    static void testTipoOverride() {
        inyectarMocks();
        // Status no matchea la variante forzada, pero el override debe ganar.
        Case c = crearCaso('Análisis', null, null, null, null, null);

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        req.tipo = 'DEVOLUCION_PROCESADA';

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(
            new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('Tu devolución ha sido procesada'), r.subject);
    }

    @IsTest
    static void testRetiroReprogramado() {
        inyectarMocks();
        Case c = crearCaso('En retiro', null, null, null, null, null);

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        req.tipo = 'RETIRO_REPROGRAMADO';

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(
            new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        System.assert(r.subject.contains('reprogramado'), r.subject);
        System.assert(r.bodyHtml.contains('ha sido reprogramado'), r.bodyHtml);
        System.assert(r.bodyHtml.contains('30 de septiembre de 2026'), 'FECHA_RETIRO');
        System.assert(r.bodyHtml.contains('09:00 - 12:00'), 'HORARIO');
        System.assert(r.bodyHtml.contains('Cliente B2B Test'), 'ACCOUNT_NAME');
        System.assert(r.bodyHtml.contains('Salmon fresco'), 'PRODUCT');
    }

    @IsTest
    static void testSinVarianteAplicable() {
        inyectarMocks();
        // Status sin config asociada (New no matchea ninguna variante).
        Case c = crearCaso('New', null, null, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(!r.ok, 'Debe fallar: sin variante');
        System.assert(String.join(r.errors, ' ').contains('Ninguna variante'), r.errors.toString());
    }

    @IsTest
    static void testSinInputs() {
        inyectarMocks();

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = null;
        req.toAddress = null;

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(
            new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(!r.ok, 'Debe fallar sin inputs');
    }

    @IsTest
    static void testSinConfiguracionesActivas() {
        EmailB2B_Manager.testConfigs = new List<Correo_B2B_Config__mdt>();
        EmailB2B_Manager.testMaestroHtml = MAESTRO_HTML;
        Case c = crearCaso('En retiro', null, null, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(!r.ok, 'Debe fallar sin configuraciones');
        System.assert(String.join(r.errors, ' ').contains('configuraciones'), r.errors.toString());
    }

    @IsTest
    static void testCasoInexistente() {
        inyectarMocks();
        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = getCuenta().Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(!r.ok, 'Debe fallar: caso inexistente');
        System.assert(String.join(r.errors, ' ').contains('No se encontró'), r.errors.toString());
    }

    @IsTest
    static void testMaestroNoEncontrado() {
        EmailB2B_Manager.testConfigs = buildConfigs();
        EmailB2B_Manager.testMaestroHtml = '';
        Case c = crearCaso('En retiro', null, null, null, null, null);

        EmailB2B_Manager.Result r = invocar(c.Id).get(0);

        System.assert(!r.ok, 'Debe fallar sin maestro');
        System.assert(String.join(r.errors, ' ').contains('Static Resource'), r.errors.toString());
    }

    @IsTest
    static void testTipoOverrideInexistente() {
        inyectarMocks();
        Case c = crearCaso('En retiro', null, null, null, null, null);

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        req.tipo = 'NO_EXISTE';

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(r.ok, 'Debe caer al matching por Status: ' + r.errors);
        System.assert(r.subject.contains('Tu retiro ha sido programado'), r.subject);
    }

    @IsTest
    static void testEnvioDirectamente() {
        inyectarMocks();
        Case c = crearCaso('En retiro', null, null, null, null, null);

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = true;

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req }).get(0);

        if (r.ok) {
            System.assert(String.isNotBlank(r.bodyHtml), 'Debe retornar HTML');
        } else {
            System.assert(String.join(r.errors, ' ').contains('correo'), 'El único error debe ser de envío: ' + r.errors);
        }
    }

    @IsTest
    static void testResolveMaestroResourceName() {
        Correo_B2B_Config__mdt registrado = new Correo_B2B_Config__mdt(DeveloperName = 'CASO_REGISTRADO');
        Correo_B2B_Config__mdt retiro = new Correo_B2B_Config__mdt(DeveloperName = 'RETIRO_PROGRAMADO');

        System.assertEquals(
            EmailB2B_Manager.CASO_REGISTRADO_RESOURCE_NAME,
            EmailB2B_Manager.resolveMaestroResourceName(registrado),
            'CASO_REGISTRADO debe usar su layout dedicado'
        );
        System.assertEquals(
            EmailB2B_Manager.MAESTRO_RESOURCE_NAME,
            EmailB2B_Manager.resolveMaestroResourceName(retiro),
            'Las demas variantes deben seguir usando el maestro'
        );
        System.assertEquals(
            EmailB2B_Manager.MAESTRO_RESOURCE_NAME,
            EmailB2B_Manager.resolveMaestroResourceName(null),
            'Sin config debe caer al maestro'
        );
    }

    @IsTest
    static void testUnresolvedTokens() {
        System.assertEquals(0, EmailB2B_Manager.unresolvedTokens('<div>ok</div>').size(), 'Sin tokens');
        System.assertEquals(0, EmailB2B_Manager.unresolvedTokens(null).size(), 'HTML null');
        System.assertEquals(
            1,
            EmailB2B_Manager.unresolvedTokens('<div>{{MOTIVO}}</div>').size(),
            'Un token sin resolver'
        );
        System.assertEquals(
            2,
            EmailB2B_Manager.unresolvedTokens('{{MOTIVO}} {{PRODUCT}} {{MOTIVO}}').size(),
            'Debe deduplicar'
        );
        System.assertEquals(
            0,
            EmailB2B_Manager.unresolvedTokens('<div style="width:{{ }}">').size(),
            'No debe tomar llaves vacias'
        );
    }

    @IsTest
    static void testLoadMaestroPorConfig() {
        inyectarMocks();

        System.assertEquals(
            CASO_REGISTRADO_HTML,
            EmailB2B_Manager.loadMaestro(EmailB2B_Manager.CASO_REGISTRADO_RESOURCE_NAME),
            'Debe devolver el HTML inyectado para la variante'
        );
        System.assertEquals(
            MAESTRO_HTML,
            EmailB2B_Manager.loadMaestro(EmailB2B_Manager.MAESTRO_RESOURCE_NAME),
            'Sin override debe caer al maestro inyectado'
        );
    }

    @IsTest
    static void testCasoRegistradoUsaLayoutPropio() {
        inyectarMocks();
        Case c = crearCaso('Análisis', null, null, null, null, null);
        c.Descripcion_Reclamo__c = 'Producto<Vinagre> sin etiqueta';
        update c;

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        req.tipo = 'CASO_REGISTRADO';

        Test.startTest();
        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req }).get(0);
        Test.stopTest();

        System.assert(r.ok, 'Debe resultar ok: ' + r.errors);
        String numeroCaso = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
        System.assert(r.bodyHtml.contains(numeroCaso), 'CASE_NUMBER');
        System.assert(r.bodyHtml.contains('Cliente B2B Test'), 'ACCOUNT_NAME');
        System.assert(r.bodyHtml.contains('Salmon fresco'), 'PRODUCT');
        System.assert(r.bodyHtml.contains('5 Kilogramos'), 'CANTIDAD + UNIDAD');
        System.assert(r.bodyHtml.contains('Producto vencido'), 'MOTIVO');
        System.assert(r.bodyHtml.contains('Producto&lt;Vinagre&gt; sin etiqueta'), 'DESCRIPCION escapada');
        System.assert(r.bodyHtml.contains('Análisis'), 'ESTADO');
        System.assert(r.bodyHtml.contains('Reclamo'), 'TIPO_CASO');
        System.assert(r.bodyHtml.contains('Registro del caso · Completado'), 'Nuevo bloque de pasos');
        System.assert(r.bodyHtml.contains(String.valueOf(Date.today().year())), 'FECHA_INGRESO con anio actual');
        System.assert(
            r.bodyHtml.contains('logo-footer.png'),
            'URL_LOGO debe venir del metadata y no quedar como placeholder'
        );
        System.assertEquals(0, EmailB2B_Manager.unresolvedTokens(r.bodyHtml).size(), 'Sin tokens sin resolver');
    }

    @IsTest
    static void testCasoRegistradoFallaCerradoConTokenSinResolver() {
        inyectarMocks();
        EmailB2B_Manager.testMaestroPorConfig = new Map<String, String>{
            EmailB2B_Manager.CASO_REGISTRADO_RESOURCE_NAME
                => '<html><body><div>{{MOTIVO}}</div><div>{{TOKEN_NUEVO}}</div></body></html>'
        };
        Case c = crearCaso('Análisis', null, null, null, null, null);

        EmailB2B_Manager.Request req = new EmailB2B_Manager.Request();
        req.recordId = c.Id;
        req.toAddress = 'cliente@test.cl';
        req.enviarDirectamente = false;
        req.tipo = 'CASO_REGISTRADO';

        EmailB2B_Manager.Result r = EmailB2B_Manager.generateEmails(new List<EmailB2B_Manager.Request>{ req }).get(0);

        System.assert(!r.ok, 'Debe abortar si queda un token sin resolver');
        String err = String.join(r.errors, ' ');
        System.assert(err.contains('Tokens sin resolver'), err);
        System.assert(err.contains('TOKEN_NUEVO'), 'Debe nombrar el token: ' + err);
    }
}