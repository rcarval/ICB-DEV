import { LightningElement, wire, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchData from '@salesforce/apex/MaestraPreciosController.fetchPricebookEntries';
import getTotalNumberOfRows from '@salesforce/apex/MaestraPreciosController.getTotalNumberOfPricebookEntries';
import { calculateMargen, calculateKilo } from 'c/utils';

export default class LookupDatatable extends LightningElement {
    @track data = []; // Registros que trae el metodo fetchData
    @track selectedData = []; // Registros seleccionados por el usuario
    @track queryOffset = 0;
    @track queryLimit = 10;
    @track currentCount = 0;
    @track showSpinner = true;
    @api selectedAccountId;
    totalNumberOfRows = 0;
    disableLoadMore = false;
    searchTerm = '';
    columns;
    delayTimeout; // Usado para debouncing
    loadMoreStatus;
    timerId; // Temporizador de debounce
    shouldStoreSelectedData = false; // Flag para trackear el momento en que se deben guardar los datos seleccionados

    connectedCallback() {
        this.columns = this.setColumns();
        
        // Validar que selectedAccountId no sea null antes de hacer llamadas a Apex
        if (this.selectedAccountId == null || this.selectedAccountId === undefined) {
            console.error('No se puede cargar productos: selectedAccountId es null o undefined');
            this.showSpinner = false;
            this.showError('No se puede cargar productos: La cotización no tiene un cliente asociado. Por favor, asocia un cliente a la cotización primero.');
            return;
        }
        
        getTotalNumberOfRows({accountId: this.selectedAccountId, searchTerm: this.searchTerm})
        .then(result => {
            this.totalNumberOfRows = result;
            if (this.selectedAccountId != null) {
                this.fetchRecords()
                .then(() => {
                    this.showSpinner = false;
                    if (this.totalNumberOfRows > (this.currentCount + 10)) {
                        this.currentCount = this.currentCount + 10;
                    } else {
                        this.currentCount = this.totalRecordCount;
                    }
                });
            }
        })
        .catch(error => {
            console.error('Error en getTotalNumberOfRows:', error);
            this.showSpinner = false;
            this.showError(error.body?.message || 'Error al cargar el número total de productos');
        });
    }

    setColumns() {
        return [
            { label: 'SKU', fieldName: 'sku', type: 'text' },
            { label: 'UMV', fieldName: 'umv', type: 'text' },
            { label: 'Descripción', fieldName: 'descripcion', type: 'text' },
            { label: 'Lista de Precio', fieldName: 'listaPrecio', type: 'number', typeAttributes: { maximumFractionDigits: 2 }, cellAttributes: { alignment: 'left'} },
            { label: 'Descuento %', fieldName: 'descuento', type: 'number', typeAttributes: { minimumFractionDigits: 2 }, cellAttributes: { alignment: 'left'} },
            { label: 'Precio Cliente Neto', fieldName: 'precioClienteNeto', type: 'number', typeAttributes: { maximumFractionDigits: 2 }, cellAttributes: { alignment: 'left'} },
            { label: 'Rappel', fieldName: 'rappel', type: 'number', cellAttributes: { alignment: 'left'} },
            { label: '%MG', fieldName: 'margen', type: 'number', typeAttributes: { minimumFractionDigits: 2 }, cellAttributes: { alignment: 'left'} },
            { label: 'MG Contribución x Kilo', fieldName: 'margenContribucionKilo', type: 'number', typeAttributes: { maximumFractionDigits: 0 }, cellAttributes: { alignment: 'left'} },
        ];
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;

        // Resetear valores al inicio de la búsqueda
        this.showSpinner = true;
        this.data = [];
        this.queryOffset = 0;
        this.queryLimit = 10;
        this.currentCount = 0;
        this.totalNumberOfRows = 0;
        this.disableLoadMore = false;

        // Usar debounce para retrasar la búsqueda
        this.debounce(() => {
            getTotalNumberOfRows({
                accountId: this.selectedAccountId,
                searchTerm: this.searchTerm
            })
            .then(result => {
                this.totalNumberOfRows = result;

                if (this.selectedAccountId != null) {
                    this.fetchRecords()
                    .then(() => {
                        this.showSpinner = false;
                        if (this.totalNumberOfRows > (this.currentCount + this.queryLimit)) {
                            this.currentCount += this.queryLimit;
                        } else {
                            this.currentCount = this.totalNumberOfRows;
                        }
                    });
                }
            })
            .catch(error => {
                console.error('Error en getTotalNumberOfRows:', error);
            });
        }, 800); // Ajustar delay según sea necesario
    }

    debounce(fn, delay) {
        clearTimeout(this.timerId);
        this.timerId = setTimeout(fn, delay);
    }

    handleOnLoadMore(event) {
        if (this.disableLoadMore) {
            return;
        }
        const { target } = event
        target.isLoading = true;

        
        if (this.totalNumberOfRows > this.queryOffset) {
            this.queryOffset = this.queryOffset + 10;
            this.fetchRecords()
                .then(() => {
                    target.isLoading = false;
                    if (this.totalNumberOfRows > (this.currentCount + 10)) {
                        this.currentCount = this.currentCount + 10;
                    } else {
                        this.currentCount = this.totalRecordCount;
                    }
                });
        } else {
            this.disableLoadMore = true;
            target.isLoading = false;
            //this.disableLoadMore = true;
            //this.loadMoreStatus = 'No more to load.';
            //this.showToast('Success', 'Success', 'All Account Records are Loaded!', 'success', 'dismissible');
            console.log('all records loaded');
        }

        console.log('Called from Infinite Table Handle More ' + this.queryOffset);
    }

    fetchRecords() {
        return fetchData({
            accountId: this.selectedAccountId,
            queryLimit: this.queryLimit,
            queryOffset: this.queryOffset,
            searchTerm: this.searchTerm
        })
        .then(result => {
            let newRecords = [...this.data, ...result];  
            //this.data = newRecords;  

            this.data = newRecords.map(item => ({ ...item })); // Esta es la lista que vamos a mutar
            this.data.forEach(item => {
                item.descuento = 0;
                item.precioClienteNeto = item.listaPrecio;
                item.margen = calculateMargen(item);
                item.margenContribucionKilo = calculateKilo(item);
            });
        })
        .catch(error => {  
            console.log(error);
            //this.showToast('Error', 'Error', 'Error getting records from Server', 'error', 'sticky');
        });
    }

    handleSelectedRow(event) {
        const currentlySelectedData = [...this.selectedData, ...event.detail.selectedRows];

        // Remove duplicates based on the 'id' attribute
        const uniqueData = [];
        const idSet = new Set();

        currentlySelectedData.forEach(item => {
            if (!idSet.has(item.id)) {
                uniqueData.push(item);
                idSet.add(item.id);
            }
        });

        this.selectedData = uniqueData;

        // Disparar evento custom para avisar al padre que se actualizaron los datos
        const recordUpdateEvent = new CustomEvent('recorddatachange', {
        //detail: { recordData: this.selectedData }
        detail: { recordData: this.selectedData.map(item => ({ ...item })) }
        });
        this.dispatchEvent(recordUpdateEvent);
    }

    showError(message) {
        const event = new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error',
            mode: 'sticky'
        });
        this.dispatchEvent(event);
    }
}