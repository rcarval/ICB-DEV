import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent, FlowNavigationFinishEvent } from 'lightning/flowSupport';

const ACCION_CONFIRMAR = 'CONFIRMAR';
const ACCION_VOLVER = 'VOLVER';
const MAX_LENGTH = 255;

export default class CancelarCasoScreen extends LightningElement {
    @api motivo = '';
    @api accion;

    maxLength = MAX_LENGTH;

    get caracteresRestantes() {
        return MAX_LENGTH - (this.motivo ? this.motivo.length : 0);
    }

    handleMotivoChange(event) {
        this.motivo = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('motivo', this.motivo));
    }

    handleVolver() {
        this.finalizar(ACCION_VOLVER);
    }

    handleConfirmar() {
        const textarea = this.template.querySelector('lightning-textarea');
        this.motivo = this.motivo ? this.motivo.trim() : '';
        if (!this.motivo) {
            textarea.value = '';
        }
        if (!textarea.reportValidity()) {
            return;
        }
        this.dispatchEvent(new FlowAttributeChangeEvent('motivo', this.motivo));
        this.finalizar(ACCION_CONFIRMAR);
    }

    finalizar(accion) {
        this.accion = accion;
        this.dispatchEvent(new FlowAttributeChangeEvent('accion', accion));
        this.dispatchEvent(new FlowNavigationFinishEvent());
    }

    @api
    validate() {
        if (this.accion === ACCION_CONFIRMAR && (!this.motivo || this.motivo.length > MAX_LENGTH)) {
            return { isValid: false, errorMessage: 'Debes indicar un motivo de cancelación de máximo 255 caracteres.' };
        }
        return { isValid: true };
    }
}