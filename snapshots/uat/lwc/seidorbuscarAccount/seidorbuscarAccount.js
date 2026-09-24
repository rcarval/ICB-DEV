/**
 * ICB Food Service
 * Desarrollado por : Sebadev97
 * Fecha            : 2026-07-01
 * Descripción      : LWC de búsqueda de cliente para WhatsApp (Flow Screen / Record Page).
 *
 * Comportamiento:
 *  - Input libre: RUT, código de cliente alfanumérico (ej: FS21312) o nombre de cuenta.
 *  - Búsqueda imperative (no @wire) disparada por botón "Buscar Cliente" o tecla Enter.
 *  - Tabla con 3 columnas: Nombre Cuenta, RUT, Código Cliente.
 *  - Selección de fila única: expone outputs al Flow vía FlowAttributeChangeEvent.
 *  - Soporta validate() nativo del Flow cuando required = true.
 *
 * Outputs al Flow:
 *  selectedAccountId   → Id del Account seleccionado
 *  selectedAccountName → Name del Account seleccionado
 *  selectedRut         → RUT__c del Account seleccionado
 *  selectedCodigo      → C_digo_de_cliente__c del Account seleccionado
 */
import { LightningElement, api, track } from 'lwc';
import { FlowAttributeChangeEvent }      from 'lightning/flowSupport';
import searchCliente from '@salesforce/apex/seidor_getClienteWhatsApp.searchCliente';

// Mínimo de caracteres requeridos para disparar búsqueda
const MIN_CHARS   = 3;
const LIMIT_COUNT = 50; // Debe coincidir con MAX_RESULTS en Apex

/** Columnas para lightning-datatable */
const COLUMNS = [
    {
        label     : 'Nombre Cliente',
        fieldName : 'Name',
        type      : 'text',
        wrapText  : false,
        cellAttributes: { class: 'slds-truncate' }
    },
    {
        label     : 'RUT',
        fieldName : 'RUT__c',
        type      : 'text',
        wrapText  : false,
        initialWidth: 140
    },
    {
        label     : 'Código Cliente',
        // Nota: C_digo_de_cliente__c es el API name de "Código de cliente" (ó → _)
        fieldName : 'C_digo_de_cliente__c',
        type      : 'text',
        wrapText  : false,
        initialWidth: 160
    }
];

export default class SeidorBuscarCliente extends LightningElement {

    // ── @api: configuración desde Flow o Experience Cloud ─────────────────────
    /** Muestra error si el usuario intenta avanzar sin seleccionar un cliente */
    @api required = false;

    // ── @api: outputs hacia el Flow ───────────────────────────────────────────
    @api selectedAccountId   = null;
    @api selectedAccountName = null;
    @api selectedRut         = null;
    @api selectedCodigo      = null;

    // ── Estado interno ────────────────────────────────────────────────────────
    @track searchTerm          = '';
    @track results             = [];
    @track isLoading           = false;
    @track errorMessage        = '';
    @track lastSearchTerm      = '';
    @track showNoResults       = false;
    @track selectedRowIds      = [];
    @track showValidationError = false;
    @track validationErrorMsg  = '';

    columns = COLUMNS;

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasResults() {
        return this.results.length > 0;
    }

    get isSearchDisabled() {
        return this.isLoading || (this.searchTerm || '').trim().length < MIN_CHARS;
    }

    get showResultLimit() {
        return this.results.length === LIMIT_COUNT;
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleInputChange(event) {
        this.searchTerm          = event.target.value;
        this.showValidationError = false;

        // Limpiar resultados anteriores si el input se vacía
        if (!(this.searchTerm || '').trim()) {
            this._resetResults();
        }
    }

    handleKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this._triggerSearch();
        }
    }

    handleSearch() {
        this._triggerSearch();
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;

        if (!selectedRows || selectedRows.length === 0) {
            this._clearSelection();
            return;
        }

        const row = selectedRows[0];

        this.selectedAccountId   = row.Id;
        this.selectedAccountName = row.Name;
        this.selectedRut         = row.RUT__c         || null;
        this.selectedCodigo      = row.C_digo_de_cliente__c || null;
        this.selectedRowIds      = [row.Id];
        this.showValidationError = false;

        // Notifica al Flow de todos los outputs
        this._notifyFlow('selectedAccountId',   this.selectedAccountId);
        this._notifyFlow('selectedAccountName', this.selectedAccountName);
        this._notifyFlow('selectedRut',         this.selectedRut);
        this._notifyFlow('selectedCodigo',      this.selectedCodigo);
    }

    // ── Validación nativa del Flow ────────────────────────────────────────────

    @api
    validate() {
        if (this.required && !this.selectedAccountId) {
            const msg = 'Debes buscar y seleccionar un cliente antes de continuar.';
            this.showValidationError = true;
            this.validationErrorMsg  = msg;
            return { isValid: false, errorMessage: msg };
        }
        this.showValidationError = false;
        return { isValid: true };
    }

    // ── Búsqueda imperativa ───────────────────────────────────────────────────

    async _triggerSearch() {
        const term = (this.searchTerm || '').trim();

        if (term.length < MIN_CHARS) {
            this.errorMessage = `Ingresa al menos ${MIN_CHARS} caracteres para buscar.`;
            return;
        }

        this.isLoading      = true;
        this.errorMessage   = '';
        this.showNoResults  = false;
        this.results        = [];
        this.lastSearchTerm = term;
        this._clearSelection();

        try {
            const data    = await searchCliente({ searchTerm: term });
            this.results  = data || [];

            if (this.results.length === 0) {
                this.showNoResults = true;
            }
        } catch (error) {
            // AuraHandledException devuelve el mensaje en error.body.message
            this.errorMessage = (error && error.body && error.body.message)
                ? error.body.message
                : 'Error inesperado al buscar clientes. Intenta nuevamente.';

            console.error('[seidorBuscarCliente] Error en búsqueda:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Helpers internos ──────────────────────────────────────────────────────

    _resetResults() {
        this.results       = [];
        this.showNoResults = false;
        this.errorMessage  = '';
        this._clearSelection();
    }

    _clearSelection() {
        this.selectedRowIds      = [];
        this.selectedAccountId   = null;
        this.selectedAccountName = null;
        this.selectedRut         = null;
        this.selectedCodigo      = null;
        this._notifyFlow('selectedAccountId',   null);
        this._notifyFlow('selectedAccountName', null);
        this._notifyFlow('selectedRut',         null);
        this._notifyFlow('selectedCodigo',      null);
    }

    _notifyFlow(attrName, value) {
        try {
            this.dispatchEvent(new FlowAttributeChangeEvent(attrName, value));
        } catch (e) {
            // FlowAttributeChangeEvent lanza error fuera de contexto de Flow (ej: Record Page).
            // Es seguro ignorarlo: el componente funciona igual, solo no hay output al flow.
        }
    }
}