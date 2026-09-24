import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import searchContactsByAccount from '@salesforce/apex/ICBFS_FlowLookupContactoCuentaController.searchContactsByAccount';

export default class IcbfsFlowLookupContactoCuenta extends LightningElement {
    _accountId;
    @api label = 'Seleccionar contacto';
    @api placeholder = 'Busca por nombre del contacto';
    @api maxResults = 50;

    @api selectedRecordId;
    @api selectedRecordName;

    @track results = [];
    @track loading = false;
    @track noResults = false;

    columns = [
        { label: 'Nombre', fieldName: 'name' },
        { label: 'Cargo', fieldName: 'role' },
        { label: 'Email', fieldName: 'email' },
        { label: 'MobilePhone', fieldName: 'mobilePhone' }
    ];

    @api
    get accountId() {
        return this._accountId;
    }

    set accountId(value) {
        this._accountId = value;
        if (value) {
            this.loadContacts();
        } else {
            this.results = [];
            this.noResults = true;
            this.clearSelection(false);
        }
    }

    connectedCallback() {
        if (this.accountId) {
            this.loadContacts();
        }
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get selectedRows() {
        return this.selectedRecordId ? [this.selectedRecordId] : [];
    }

    async loadContacts() {
        await this.doSearch('');
    }

    async doSearch(searchText) {
        if (!this.accountId) {
            this.results = [];
            this.noResults = true;
            return;
        }

        try {
            this.loading = true;
            const data = await searchContactsByAccount({
                accountId: this.accountId,
                searchText,
                maxResults: this.maxResults
            });

            this.results = data || [];
            this.noResults = this.results.length === 0;
        } catch (error) {
            this.results = [];
            this.noResults = true;
        } finally {
            this.loading = false;
        }
    }

    handlePick(event) {
        const selectedRows = event.detail.selectedRows || [];
        if (!selectedRows.length) {
            this.clearSelection();
            return;
        }

        const [selectedRow] = selectedRows;
        this.selectedRecordId = selectedRow.id;
        this.selectedRecordName = selectedRow.name;
        this.dispatchFlowChange('selectedRecordId', this.selectedRecordId);
        this.dispatchFlowChange('selectedRecordName', this.selectedRecordName);
    }

    clearSelection(shouldNotify = true) {
        this.selectedRecordId = null;
        this.selectedRecordName = null;
        if (shouldNotify) {
            this.dispatchFlowChange('selectedRecordId', null);
            this.dispatchFlowChange('selectedRecordName', null);
        }
    }

    dispatchFlowChange(attributeName, value) {
        this.dispatchEvent(new FlowAttributeChangeEvent(attributeName, value));
    }
}