import { LightningElement, api, track } from 'lwc';
import getPreviewHtml from '@salesforce/apex/ComodatoPropuestaController.getPreviewHtml';

export default class PropuestaComodatoPreview extends LightningElement {
    @api machineId;
    @api aportesMarca;

    @track previewHtml;
    @track error;
    @track isLoading = false;

    _isRendered = false;

    connectedCallback() {
        this.loadPreview();
    }

    renderedCallback() {
        if (!this._isRendered) {
            this._isRendered = true;
            this.renderHtml();
        }
        
        // Reactividad manual para cambios en las propiedades de entrada del flow
        if (this._lastMachineId !== this.machineId || this._lastAportes !== this.aportesMarca) {
            this._lastMachineId = this.machineId;
            this._lastAportes = this.aportesMarca;
            this.loadPreview();
        }
    }

    _lastMachineId;
    _lastAportes;

    loadPreview() {
        if (!this.machineId) return;
        
        this.isLoading = true;
        getPreviewHtml({ machineId: this.machineId })
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
            .finally(() => {
                this.isLoading = false;
            });
    }

    renderHtml() {
        const container = this.template.querySelector('.html-container');
        if (container && this.previewHtml) {
            // eslint-disable-next-line @lwc/lwc/no-inner-html
            container.innerHTML = this.previewHtml;
        }
    }
}