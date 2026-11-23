public with sharing class seidor_CaseMonthlyReportDTO {

    public class CaseWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String tipoRequerimiento;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Date closedDate;
        @AuraEnabled public String periodoAtencion;
        @AuraEnabled public String accountName;
        @AuraEnabled public String clienteDespacho;
        @AuraEnabled public String nombreDireccion;
        @AuraEnabled public String comunaSucursal;
        @AuraEnabled public String centroAbastecimiento;
        @AuraEnabled public String regionCliente;
        @AuraEnabled public String sku;
        @AuraEnabled public String nombreProducto;
        @AuraEnabled public Decimal cantidadReclamada;
        @AuraEnabled public String um;
        @AuraEnabled public String tipoUMReclamo;
        @AuraEnabled public Decimal valorNeto;
        @AuraEnabled public String motivo;
        @AuraEnabled public String categoria;
        @AuraEnabled public String causa;
        @AuraEnabled public String categoriaReclamo;
        @AuraEnabled public String procedeReclamo;
        @AuraEnabled public String motivoNoProcede;
        @AuraEnabled public String status;
        @AuraEnabled public String creadoPor;
        @AuraEnabled public String asesor;
        @AuraEnabled public String codigoAsesor;
        @AuraEnabled public String tipoNotaCredito;
        @AuraEnabled public String cumplePlazos;
        @AuraEnabled public String fechaRetiro;
        @AuraEnabled public String fechaRecepcion;
        @AuraEnabled public String estadoNotaCredito;
        @AuraEnabled public String estadoProducto;
        @AuraEnabled public String horarioRetiro;

        public CaseWrapper() {}
    }

    public class MonthGroup {
        @AuraEnabled public Integer month;
        @AuraEnabled public Integer year;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Integer totalCases;
        @AuraEnabled public List<CaseWrapper> records;

        public MonthGroup(Integer m, Integer y, String label) {
            this.month = m;
            this.year = y;
            this.monthLabel = label;
            this.totalCases = 0;
            this.records = new List<CaseWrapper>();
        }
    }

    public class ReportResult {
        @AuraEnabled public List<MonthGroup> groups;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public Integer currentPage;

        public ReportResult() {
            this.groups = new List<MonthGroup>();
            this.totalRecords = 0;
            this.hasMore = false;
            this.totalPages = 0;
            this.currentPage = 1;
        }
    }
}