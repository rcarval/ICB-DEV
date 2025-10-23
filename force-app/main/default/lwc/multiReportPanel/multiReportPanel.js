import { LightningElement, api, wire, track } from 'lwc';
import getUserFacturasLast3Months from '@salesforce/apex/ICBFS_MyReportController.getUserFacturasLast3Months';
// import { refreshApex } from '@salesforce/apex';
// import userId from '@salesforce/user/Id';

export default class MultiReportPanel extends LightningElement {
    @api userId = '005Hn00000Iy7s3IAB';
    
    @track rawData = [];
    @track pivotData = [];
    @track pivotColumns = [];
    @track error;

    wiredFacturasResult;  // para guardar la referencia del wire y poder refrescarlo

    @wire(getUserFacturasLast3Months, { userId: '$userId' })
    wired_facturas(result) {
        console.log('OUTPUT : ', 'UserId actual: ' + this.userId);
        this.wiredFacturasResult = result;
        const { data, error } = result;
        if (data) {
            this.rawData = data;
            this.error = undefined;
            this.buildPivot();
        } else if (error) {
            this.error = error;
            this.rawData = [];
        }
    }

    get datatableColumns() {
        const fixedCols = [
            { label: 'Cliente', fieldName: 'clienteName', type: 'text' },
            { label: 'Código Cliente', fieldName: 'clienteCodigo', type: 'text' },
            { label: 'Nombre de Fantasía', fieldName: 'clienteFantasia', type: 'text' },
            // { label: 'Ventas últimos 3 meses', fieldName: 'ventas3Meses', type: 'number' },
        ];
        return fixedCols.concat(this.pivotColumns);
    }
    get groupedByFecha() {
        // Agrupa los registros por fechaDocumento (formato ISO)
        const grupos = {};
        this.rawData.forEach(r => {
            const fecha = new Date(r.fechaDocumento).toISOString().split('T')[0]; // Solo la fecha
            if (!grupos[fecha]) {
                grupos[fecha] = [];
            }
            grupos[fecha].push(r);
        });
        return grupos;
    }
buildPivot() {

    const grupos = this.groupedByFecha;
    Object.keys(grupos).forEach(fecha => {
        console.log('Fecha:', fecha, 'Registros:', grupos[fecha]);
    });
    // construir columnas dinámicas basadas en fechas
    const fechasSet = new Set(this.rawData.map(r => new Date(r.fechaDocumento)));
    const fechas = Array.from(fechasSet).sort((a, b) => b - a);

    this.pivotColumns = fechas.map(dt => {
        return {
            label: dt.toISOString().split('T')[0],
            fieldName: dt.toISOString(),
            type: 'text'
        };
    });

    const mapCliente = new Map();
    this.rawData.forEach(r => {
        const key = r.clienteName + '|' + r.clienteCodigo;
        if (!mapCliente.has(key)) {
            mapCliente.set(key, {
                clienteName: r.clienteName,
                clienteCodigo: r.clienteCodigo,
                clienteFantasia: r.clienteFantasia,
                ventas3Meses: r.ventas3MesesCliente
            });
        }
        const fila = mapCliente.get(key);
        // convertir fechaDocumento a Date y luego a ISO string
        const fechaIso = new Date(r.fechaDocumento).toISOString();
        fila[fechaIso] = r.totalVenta != null ? r.totalVenta : '';
    });

    this.pivotData = Array.from(mapCliente.values());
}

    handleRefresh() {
        // refrescar el wire
        if (this.wiredFacturasResult) {
            refreshApex(this.wiredFacturasResult);
            console.log('OUTPUT : ', 'Refrescando datos...');
        } else {
            console.log('OUTPUT : ', 'No hay datos para refrescar...');
        }
    }
}