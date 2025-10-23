import { LightningElement, api, track} from 'lwc';
import { helper } from './maestraPreciosHelper';
import obtenerRegistrosUnificados from '@salesforce/apex/MaestraPreciosController.obtenerRegistrosUnificados';

export default class MaestraPrecios extends LightningElement {
    @api accountIdValue;
    @api accountName;
    @track allProductData = [];
    @track filteredData = [];
    @track sortedBy = '';
    @track sortedDirection = 'asc';
    @track productsAvailable = false;
    @track searchTerm = '';
    @track noResultsFound = false;
    isActualizarClicked = false;
    columns = [];
    encabezado = '';
    initialProductData;

    connectedCallback() {
        this.encabezado = helper.generarEncabezado();
        this.columns = helper.initializeColumns();
        if (this.accountIdValue) {
            this.cargarDatosMaestra();
        }
    }

    cargarDatosMaestra() {
        obtenerRegistrosUnificados({ accountId: this.accountIdValue })
            .then((result) => {
                this.allProductData = result;
                helper.transformarDatos(this.allProductData);
                this.filteredData = [...this.allProductData];
                this.sortData('sku', 'asc');
                this.productsAvailable = true;
            })
            .catch((error) => {
                console.error('Error al cargar datos de maestra:', error);
            });
    }

    handleActualizar() {
        this.isActualizarClicked = true;
        this.initialProductData = [...this.allProductData];
    }

    handleAtrasClicked() {
        this.isActualizarClicked = false;
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedDirection = sortDirection;
        this.sortedBy = sortedBy;
        this.sortData(sortedBy, sortDirection);
    }

    sortData(columnName, direction) {
        const reverse = direction === 'desc' ? 1 : -1;
        const data = [...this.filteredData];
        
        data.sort((a, b) => {
            let valueA = a[columnName];
            let valueB = b[columnName];
            
            if (valueA == null) valueA = '';
            if (valueB == null) valueB = '';
            
            if (typeof valueA === 'number' && typeof valueB === 'number') {
                return reverse * (valueA - valueB);
            }
            
            if (valueA instanceof Date && valueB instanceof Date) {
                return reverse * (valueA - valueB);
            }
            
            if (typeof valueA === 'string' && typeof valueB === 'string') {
                return reverse * valueA.localeCompare(valueB, undefined, { sensitivity: 'base' });
            }
            
            return reverse * String(valueA).localeCompare(String(valueB), undefined, { sensitivity: 'base' });
        });
        
        this.filteredData = data;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value.toUpperCase();
        this.filterData();
    }

    filterData() {
        if (!this.searchTerm) {
            this.filteredData = [...this.allProductData];
            this.noResultsFound = false;
        } else {
            this.filteredData = this.allProductData.filter(product => 
                (product.sku && product.sku.toUpperCase().includes(this.searchTerm)) ||
                (product.descripcion && product.descripcion.toUpperCase().includes(this.searchTerm))
            );
            
            this.noResultsFound = this.filteredData.length === 0;
        }
        
        if (this.sortedBy) {
            this.sortData(this.sortedBy, this.sortedDirection);
        }
    }

    // Método para limpiar la búsqueda
    clearSearch() {
        this.searchTerm = '';
        this.filteredData = [...this.allProductData];
        this.noResultsFound = false;
        
        // Reenfocar el campo de búsqueda
        const searchInput = this.template.querySelector('input');
        if (searchInput) {
            searchInput.focus();
        }
        
        // Reaplicar ordenamiento si existe
        if (this.sortedBy) {
            this.sortData(this.sortedBy, this.sortedDirection);
        }
    }
}