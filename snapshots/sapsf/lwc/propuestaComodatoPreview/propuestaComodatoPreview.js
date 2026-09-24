import { LightningElement, api, track } from 'lwc';
import getPreviewHtml from '@salesforce/apex/ComodatoPropuestaController.getPreviewHtml';
import getMultiMachinePreviewHtml from '@salesforce/apex/ComodatoPropuestaMultiController.getMultiMachinePreviewHtml';
import getMultiMachinePreviewHtmlConAjustes from '@salesforce/apex/ComodatoPropuestaMultiController.getMultiMachinePreviewHtmlConAjustes';
import getPreviewHtmlConAjustes from '@salesforce/apex/ComodatoPropuestaController.getPreviewHtmlConAjustes';

export default class PropuestaComodatoPreview extends LightningElement {
    @api machineId;
    @api aportesMarca;
    @api machineSelectionsJson;
    // Ajustes excepcionales capturados en el paso anterior y todavia no guardados.
    // Sin esto la cotizacion mostraria los valores estandar y no lo que el usuario ajusto.
    @api ajustesJson;

    @track previewHtml;
    @track error;
    @track isLoading = false;

    _isRendered = false;
    _lastMachineId;
    _lastAportes;
    _lastSelectionsJson;

    connectedCallback() {
        this.loadPreview();
    }

    renderedCallback() {
        if (!this._isRendered) {
            this._isRendered = true;
            this.renderHtml();
        }

        if (this._lastMachineId !== this.machineId ||
            this._lastAportes !== this.aportesMarca ||
            this._lastSelectionsJson !== this.machineSelectionsJson ||
            this._lastAjustesJson !== this.ajustesJson) {
            this._lastMachineId = this.machineId;
            this._lastAportes = this.aportesMarca;
            this._lastSelectionsJson = this.machineSelectionsJson;
            this._lastAjustesJson = this.ajustesJson;
            this.loadPreview();
        }
    }

    get isMultiMode() {
        if (!this.machineSelectionsJson) return false;
        try {
            const selections = JSON.parse(this.machineSelectionsJson);
            return Array.isArray(selections) && selections.length > 0;
        } catch (e) {
            return false;
        }
    }

    loadPreview() {
        if (this.isMultiMode) {
            this.loadMultiPreview();
        } else if (this.machineId) {
            this.loadSinglePreview();
        }
    }

    /** Hay ajustes pendientes si el JSON trae al menos un elemento. */
    get tieneAjustes() {
        if (!this.ajustesJson) return false;
        try {
            const a = JSON.parse(this.ajustesJson);
            return Array.isArray(a) && a.length > 0;
        } catch (e) {
            return false;
        }
    }

    loadSinglePreview() {
        this.isLoading = true;
        const promesa = this.tieneAjustes
            ? getPreviewHtmlConAjustes({ machineId: this.machineId, ajustesJson: this.ajustesJson })
            : getPreviewHtml({ machineId: this.machineId });
        promesa
            .then(result => {
                this.previewHtml = result;
                this.error = undefined;
                this.renderHtml();
            })
            .catch(error => {
                console.error('Error loading preview:', error);
                this.error = error;
                this.previewHtml = undefined;
            })
            .finally(() => { this.isLoading = false; });
    }

    loadMultiPreview() {
        this.isLoading = true;
        const promesa = this.tieneAjustes
            ? getMultiMachinePreviewHtmlConAjustes({
                  machineSelectionsJson: this.machineSelectionsJson,
                  ajustesJson: this.ajustesJson
              })
            : getMultiMachinePreviewHtml({ machineSelectionsJson: this.machineSelectionsJson });
        promesa
            .then(result => {
                this.previewHtml = result;
                this.error = undefined;
                this.renderHtml();
            })
            .catch(error => {
                console.error('Error loading multi preview:', error);
                this.error = error;
                this.previewHtml = undefined;
            })
            .finally(() => { this.isLoading = false; });
    }

    renderHtml() {
        const container = this.template.querySelector('.html-container');
        if (container && this.previewHtml) {
            container.innerHTML = this.previewHtml;
        }
    }
}