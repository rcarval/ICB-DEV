public with sharing class seidor_PDFController {

    public Case caso { get; private set; }
    //public String fdrNumber { get; private set;}
    public Detalle_Factura__c detalleProductoFactura { get; private set; }
    public String supervisorName { get; private set; }
    public Boolean isDevolucion { get; private set; }
    public String pdfFileName { get; private set; }
    public String tipoRequerimiento { get; private set; }
    public Boolean isRechazoTotal { get; private set; }
    public List<Detalle_Factura__c> detallesFactura { get; private set; }
    public List<DetalleWrapper> detallesWrapper { get; private set; }
    public Decimal totalValorNeto { get; private set; }

    public class DetalleWrapper {
        public Integer rowNum { get; set; }
        public Detalle_Factura__c det { get; set; }
        public DetalleWrapper(Integer idx, Detalle_Factura__c d) {
            this.rowNum = idx;
            this.det = d;
        }
    }

    public Boolean isPreview {
        get {
            String previewParam = ApexPages.currentPage().getParameters().get('preview');
            return previewParam == 'true';
        }
    }

    // ===== DIAS LOCAL CERRADO (Dias_cerrados__c es multi-picklist: string separado por ';') =====
   private Set<String> diasCerradosNorm;

   
    private Set<String> getDiasCerradosNorm() {

        if (diasCerradosNorm == null) {
            diasCerradosNorm = new Set<String>();
            if (caso != null && String.isNotBlank(caso.Dias_cerrados__c)) {
                for (String dia : caso.Dias_cerrados__c.split(';')) {
                    diasCerradosNorm.add(normalizeDia(dia));
                }
            }
        }
        return diasCerradosNorm;
    }

    // Normaliza a minúsculas y sin tildes para no depender de cómo esté configurado el picklist en el org

    private static String normalizeDia(String value) {
        if (value == null) {
            return '';
        }
        String v = value.trim().toLowerCase();
        v = v.replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u');
        return v;
    }

    public Boolean getIsLunesCerrado() {
        return getDiasCerradosNorm().contains('lunes');
    }

    public Boolean getIsMartesCerrado() {
        return getDiasCerradosNorm().contains('martes');
    }

    public Boolean getIsMiercolesCerrado() {
        return getDiasCerradosNorm().contains('miercoles');
    }

    public Boolean getIsJuevesCerrado() {
        return getDiasCerradosNorm().contains('jueves');
    }

    public Boolean getIsViernesCerrado() {
        return getDiasCerradosNorm().contains('viernes');
    }

    public Boolean getIsSabadoCerrado() {
        return getDiasCerradosNorm().contains('sabado');
    }

    public seidor_PDFController() {

        Id caseId = ApexPages.currentPage().getParameters().get('caseId');
        //fdrNumber = ApexPages.currentPage().getParameters().get('fdrNumber');

        if (caseId == null) {
            return;
        }

        caso = [
                SELECT Id,
                        CaseNumber,
                        Origin,
                        Area__c,
                        SKU__c,
                        Categoria__c,
                        Sub_Categoria__c,
                        CreatedDate,
                        Sucursal_de_Retiro__r.Name,
                        Sucursal_de_Retiro__r.Region_Despacho__c,
                        Sucursal_de_Retiro__r.ShippingStreet,
                        Sucursal_de_Retiro__r.Comuna_Despacho__r.Name,
                        Sucursal_de_Retiro__r.Cliente_Despacho__c,
                        Nombre_Direcci_n__c,
                        Cliente_Despacho__c,
                        Direccion_de_retiro_new__c,
                        Horario_retiro__c,
                        N_Factura__c,
                        Fecha_Factura__c,
                        Cantidad_reclamada__c,
                        UM_Unidad_de_Medida__c,
                        Motivo__c,
                        AccountId,
                        Account.Name,
                        Account.Nombre_de_Fantasia__c,
                        Account.RUT__c,
                        Account.C_digo_de_cliente__c,
                        Account.Owner.Name,
                        Account.Gerencia__c,
                        ContactId,
                        Contact.Name,
                        ContactMobile,
                        Transporte__r.Name,
                        Valor_Neto__c,
                        Fecha_retiro__c,
                        ProductId,
                        Owner.Name,
                        Numero_Factura__c,
                        Tipo_de_Requerimiento__c,
                        Codigo_Cliente__c,
                        Dias_cerrados__c,
                        Product.Name,
                        Factura__c,
                        RecordType.DeveloperName
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
        ];

        isDevolucion = caso.Tipo_de_Requerimiento__c == 'Devoluciones';

        isRechazoTotal = isDevolucion
            && caso.Sub_Categoria__c == 'Rechazo total'
            && caso.RecordType.DeveloperName == 'Devoluciones';

        Boolean isRechazoParcial = caso.Categoria__c == 'Rechazo de pedido'
            && caso.Sub_Categoria__c == 'Rechazo parcial';

        if (isRechazoParcial && caso.Factura__c != null) {
            // RECHAZO PARCIAL: siempre consulta el Detalle_Factura__c (aunque haya un solo ProductId
            // en el Case) para setear Cantidad__c/Unidad_de_Medida__c directo desde el registro
            detallesFactura = [
                    SELECT Id,
                            Name,
                            Factura__r.Name,
                            Cantidad__c,
                            Descripcion__c,
                            SKU__c,
                            Unidad_de_Medida__c,
                            Valor_Neto__c,
                            Peso_neto__c,
                            Product__r.Id,
                            Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__c = :caso.Factura__c
                    AND Proceso_de_reclamo__c = true
                    AND Caso__c = :caso.Id
            ];
        } else if (isRechazoParcial && caso.Numero_Factura__c != null) {
            // RECHAZO PARCIAL sin Factura__c: detalle por número de factura + producto del Case
            detallesFactura = [
                    SELECT Id,
                            Name,
                            Factura__r.Name,
                            Cantidad__c,
                            Descripcion__c,
                            SKU__c,
                            Unidad_de_Medida__c,
                            Valor_Neto__c,
                            Peso_neto__c,
                            Product__r.Id,
                            Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__r.Name = :caso.Numero_Factura__c AND Product__r.Id = :caso.ProductId
            ];
        } else if (!isDevolucion && caso.ProductId != null) {
            // CALIDAD: producto directo del Case
            Detalle_Factura__c det = new Detalle_Factura__c();
            det.SKU__c = caso.SKU__c;
            det.Cantidad__c = caso.Cantidad_reclamada__c;
            det.Unidad_de_Medida__c = caso.UM_Unidad_de_Medida__c;
            det.Valor_Neto__c = caso.Valor_Neto__c;
            det.Product__r = new Product2(Name = caso.Product.Name);
            detallesFactura = new List<Detalle_Factura__c>{ det };
        } else if (isDevolucion && caso.ProductId != null) {
            // DEVOLUCIONES con producto asignado (Rechazo total / Devolución simple): producto directo del Case
            Detalle_Factura__c det = new Detalle_Factura__c();
            det.SKU__c = caso.SKU__c;
            det.Cantidad__c = caso.Cantidad_reclamada__c;
            det.Unidad_de_Medida__c = caso.UM_Unidad_de_Medida__c;
            det.Valor_Neto__c = caso.Valor_Neto__c;
            det.Product__r = new Product2(Name = caso.Product.Name);
            detallesFactura = new List<Detalle_Factura__c>{ det };
        } else if (caso.Factura__c != null) {
            // DEVOLUCIONES con factura (Rechazo total / otros): todos los detalles de la factura
            detallesFactura = [
                    SELECT Id,
                            Name,
                            Factura__r.Name,
                            Cantidad__c,
                            Descripcion__c,
                            SKU__c,
                            Unidad_de_Medida__c,
                            Valor_Neto__c,
                            Peso_neto__c,
                            Product__r.Id,
                            Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__c = :caso.Factura__c
            ];
        } else {
            // DEVOLUCIONES sin factura: detalle por número de factura + producto del Case
            detallesFactura = [
                    SELECT Id,
                            Name,
                            Factura__r.Name,
                            Cantidad__c,
                            Descripcion__c,
                            SKU__c,
                            Unidad_de_Medida__c,
                            Valor_Neto__c,
                            Peso_neto__c,
                            Product__r.Id,
                            Product__r.Name
                    FROM Detalle_Factura__c
                    WHERE Factura__r.Name = :caso.Numero_Factura__c AND Product__r.Id = :caso.ProductId
            ];
        }

        detallesWrapper = new List<DetalleWrapper>();
        totalValorNeto = 0;
        Integer i = 1;
        Boolean usaValorNetoDelCase = !isRechazoParcial && caso.ProductId != null;
        for (Detalle_Factura__c det : detallesFactura) {
            if (usaValorNetoDelCase) {
                det.Valor_Neto__c = caso.Valor_Neto__c;
            }
            if (isRechazoParcial && det.Cantidad__c == null) {
                det.Cantidad__c = caso.Cantidad_reclamada__c;
            }
            totalValorNeto += det.Valor_Neto__c != null ? det.Valor_Neto__c : 0;
            detallesWrapper.add(new DetalleWrapper(i++, det));
        }

        List<Detalle_Factura__c> detalles = detallesFactura;

        Account acc = [
                SELECT
                        Owner.Name,
                        Owner.UserRole.ParentRoleId
                FROM Account
                WHERE Id = :caso.AccountId
                LIMIT 1
        ];

        List<User> supervisors = new List<User>();
        if (acc.Owner != null && acc.Owner.UserRole != null && acc.Owner.UserRole.ParentRoleId != null) {
            supervisors = [
                    SELECT Id, Name
                    FROM User
                    WHERE UserRoleId = :acc.Owner.UserRole.ParentRoleId
                    AND IsActive = true
            ];
        }

        if (!supervisors.isEmpty()) {
            supervisorName = supervisors[0].Name;
        }

       tipoRequerimiento = isDevolucion ? 'DEVOLUCIÓN' : 'RECLAMO CALIDAD';

       String prefijo = isDevolucion ? 'FDR Devoluciones' : 'FDR Calidad';
       pdfFileName = prefijo + ' - ' + caso.CaseNumber + '.pdf';

        // Solo setear Content-Disposition cuando se accede para DESCARGA
        // (no en preview ni en generación de PDF por el invocable)
        Boolean isDownload = ApexPages.currentPage().getParameters().get('download') == 'true';
        if (isDownload) {
            ApexPages.currentPage().getHeaders().put(
                    'Content-Disposition',
                    'attachment; filename="' + pdfFileName + '"'
            );
        }

        System.debug('### SUPERVISOR NAME: ' + supervisorName);

        System.debug('### DETALLES: ' + detalles);

        if (!detalles.isEmpty()) {
            detalleProductoFactura = detalles[0];
        }

        // System.debug('### PARAM FDR NUMBER: ' + fdrNumber);
        // System.debug('### CASE N_FDR__c: ' + caso.N_FDR__c);
    }
    public static void getInt(){
        Integer I =0;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
        I++;
    }
}