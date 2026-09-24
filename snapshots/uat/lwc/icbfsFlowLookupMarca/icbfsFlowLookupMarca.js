/**
ICB Food Service
Desarrollado por: José Illanes
Fecha: 2026-02-12
Descripción: Lookup custom para Flow (móvil-friendly). Busca Marca__c por Name.
*/
import { LightningElement, api, track } from 'lwc';
import searchMarcas from '@salesforce/apex/ICBFS_FlowLookupController.searchMarcas';

export default class IcbfsFlowLookupMarca extends LightningElement {
    @api label = 'Marca';
    @api placeholder = 'Escribe al menos 2 letras…';
    @api maxResults = 10;

    // Salidas para Flow
    @api selectedRecordId;
    @api selectedRecordName;

    @track searchText = '';
    @track results = [];
    @track loading = false;
    @track showList = false;
    @track noResults = false;

    _debounce;

    handleFocus() {
        if (this.results?.length) this.showList = true;
    }

    handleChange(event) {
        this.searchText = event.target.value;
        this.selectedRecordId = null;
        this.selectedRecordName = null;

        const q = (this.searchText || '').trim();
        this.noResults = false;

        window.clearTimeout(this._debounce);
        if (q.length < 2) {
            this.results = [];
            this.showList = false;
            return;
        }

        this._debounce = window.setTimeout(() => this.doSearch(q), 250);
    }

    async doSearch(q) {
        try {
            this.loading = true;
            this.showList = true;

            const data = await searchMarcas({ searchText: q, maxResults: this.maxResults });
            this.results = data || [];
            this.noResults = (this.results.length === 0);
        } catch (e) {
            this.results = [];
            this.noResults = true;
        } finally {
            this.loading = false;
        }
    }

    handlePick(event) {
        const id = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;

        this.selectedRecordId = id;
        this.selectedRecordName = label;

        this.showList = false;
        this.results = [];
        this.searchText = label;

        // Notifica al Flow que cambió la salida
        this.dispatchEvent(new CustomEvent('valuechange'));
    }

    clearSelection() {
        this.selectedRecordId = null;
        this.selectedRecordName = null;
        this.searchText = '';
        this.results = [];
        this.showList = false;
        this.noResults = false;
        this.dispatchEvent(new CustomEvent('valuechange'));
    }
}