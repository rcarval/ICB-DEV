public with sharing class seidor_CaseMonthlyReportService {

    private static final List<String> MONTH_NAMES = new List<String>{
        '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
        'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    };

    // Reusable field list for report rows and per-case detail.
    private static final String CASE_FIELDS =
        'SELECT Id, CaseNumber, Tipo_de_Requerimiento__c, CreatedDate, ClosedDate, '
        + 'Account.Name, Sucursal_de_Retiro__r.Cliente_Despacho__c, '
        + 'Nombre_Direcci_n__c, '
        + 'Sucursal_de_Retiro__r.Comuna_Despacho__r.Name, '
        + 'Region_Cliente__c, SKU__c, Product.Name, '
        + 'Cantidad_reclamada__c, UM_Unidad_de_Medida__c, Tipo_UM_Reclamo__c, '
        + 'Valor_Neto__c, Motivo__c, Categoria__c, Sub_Categoria__c, Tipo_de_Reclamo__c, '
        + 'Procede_el_Reclamo__c, Motivo_No_procede__c, Status, '
        + 'CreatedBy.Name, '
        + 'Account.Owner.Name, Account.Codigo_del_asesor__c, '
        + 'Tipo_de_Nota_de_Credito__c, Cumple_los_plazos__c, '
        + 'Estado_Nota_de_Credito__c, Estado_de_Producto__c, Horario_retiro__c, '
        + 'Fecha_retiro__c, Fecha_recepcion__c ';

    public static seidor_CaseMonthlyReportDTO.ReportResult getReport() {
        String baseQuery = CASE_FIELDS + 'FROM Case ORDER BY CreatedDate DESC, CaseNumber DESC';

        List<Case> cases = Database.query(baseQuery);

        List<String> orderedKeys = new List<String>();
        Map<String, seidor_CaseMonthlyReportDTO.MonthGroup> groupMap =
            new Map<String, seidor_CaseMonthlyReportDTO.MonthGroup>();

        for (Case c : cases) {
            Integer m = c.CreatedDate.month();
            Integer y = c.CreatedDate.year();
            String key = y + '-' + String.valueOf(m).leftPad(2, '0');

            if (!groupMap.containsKey(key)) {
                orderedKeys.add(key);
                groupMap.put(key, new seidor_CaseMonthlyReportDTO.MonthGroup(
                    m, y, MONTH_NAMES[m] + ' ' + y
                ));
            }

            seidor_CaseMonthlyReportDTO.MonthGroup grp = groupMap.get(key);
            grp.records.add(wrapCase(c));
            grp.totalCases = grp.records.size();
        }

        List<seidor_CaseMonthlyReportDTO.MonthGroup> groups =
            new List<seidor_CaseMonthlyReportDTO.MonthGroup>();
        for (String k : orderedKeys) {
            groups.add(groupMap.get(k));
        }

        seidor_CaseMonthlyReportDTO.ReportResult result =
            new seidor_CaseMonthlyReportDTO.ReportResult();
        result.groups = groups;
        result.totalRecords = cases.size();
        result.hasMore = false;
        result.currentPage = 1;
        result.totalPages = 1;

        return result;
    }

    public static seidor_CaseMonthlyReportDTO.CaseWrapper getCaseById(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Debe indicar un caso.');
        }
        List<Case> cases = Database.query(CASE_FIELDS + 'FROM Case WHERE Id = :caseId LIMIT 1');
        if (cases.isEmpty()) {
            throw new AuraHandledException('No se encontró el caso solicitado.');
        }
        return wrapCase(cases.get(0));
    }

    private static seidor_CaseMonthlyReportDTO.CaseWrapper wrapCase(Case c) {
        seidor_CaseMonthlyReportDTO.CaseWrapper w =
            new seidor_CaseMonthlyReportDTO.CaseWrapper();

        w.id = c.Id;
        w.caseNumber = c.CaseNumber;
        w.tipoRequerimiento = c.Tipo_de_Requerimiento__c;
        w.createdDate = c.CreatedDate;
        w.closedDate = c.ClosedDate != null ? c.ClosedDate.date() : null;
        w.periodoAtencion = calcDias(c.CreatedDate, c.ClosedDate);
        w.accountName = c.Account != null ? c.Account.Name : null;
        w.clienteDespacho = c.Sucursal_de_Retiro__r != null
            ? c.Sucursal_de_Retiro__r.Cliente_Despacho__c : null;
        w.nombreDireccion = c.Nombre_Direcci_n__c;
        w.comunaSucursal = (c.Sucursal_de_Retiro__r != null
            && c.Sucursal_de_Retiro__r.Comuna_Despacho__r != null)
            ? c.Sucursal_de_Retiro__r.Comuna_Despacho__r.Name : null;
        w.regionCliente = c.Region_Cliente__c;
        w.sku = c.SKU__c;
        w.nombreProducto = c.Product != null ? c.Product.Name : null;
        w.cantidadReclamada = c.Cantidad_reclamada__c;
        w.um = c.UM_Unidad_de_Medida__c;
        w.tipoUMReclamo = c.Tipo_UM_Reclamo__c;
        w.valorNeto = c.Valor_Neto__c;
        w.motivo = c.Motivo__c;
        w.categoria = c.Categoria__c;
        w.causa = c.Sub_Categoria__c;
        w.categoriaReclamo = c.Tipo_de_Reclamo__c;
        w.procedeReclamo = c.Procede_el_Reclamo__c;
        w.motivoNoProcede = c.Motivo_No_procede__c;
        w.status = c.Status;
        w.creadoPor = c.CreatedBy != null ? c.CreatedBy.Name : null;
        w.asesor = c.Account != null && c.Account.Owner != null ? c.Account.Owner.Name : null;
        w.codigoAsesor = c.Account != null && c.Account.Codigo_del_asesor__c != null
            ? String.valueOf((Integer) c.Account.Codigo_del_asesor__c) : null;
        w.tipoNotaCredito = c.Tipo_de_Nota_de_Credito__c;
        w.cumplePlazos = c.Cumple_los_plazos__c;
        w.fechaRetiro = c.Fecha_retiro__c != null ? c.Fecha_retiro__c.format() : null;
        w.fechaRecepcion = c.Fecha_recepcion__c != null ? c.Fecha_recepcion__c.format() : null;
        w.estadoNotaCredito = c.Estado_Nota_de_Credito__c;
        w.estadoProducto = c.Estado_de_Producto__c;
        w.horarioRetiro = c.Horario_retiro__c;

        return w;
    }

    private static String calcDias(DateTime s, DateTime e) {
        if (s == null || e == null) return null;
        Integer d = (Integer) ((e.getTime() - s.getTime()) / 86400000);
        return d < 0 ? null : d + ' días';
    }
}