import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import LAVAZZA_ICON from '@salesforce/resourceUrl/Logo_Lavazza_Icono';

const VALUE_CAFE = 'Máquina Café';
const VALUE_DISPENSADOR = 'Dispensador';

export default class TipoEquipoSelector extends LightningElement {
    @api value = '';

    lavazzaIconUrl = LAVAZZA_ICON;

    get isCafe() {
        return this.value === VALUE_CAFE;
    }

    get isDispensador() {
        return this.value === VALUE_DISPENSADOR;
    }

    get cafeClass() {
        return this.isCafe ? 'tipo-card selected' : 'tipo-card';
    }

    get dispensadorClass() {
        return this.isDispensador ? 'tipo-card selected' : 'tipo-card';
    }

    handleSelect(event) {
        this.value = event.currentTarget.dataset.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('value', this.value));
    }

    @api
    validate() {
        if (!this.value) {
            return {
                isValid: false,
                errorMessage: 'Selecciona un tipo de equipo antes de continuar.'
            };
        }
        return { isValid: true };
    }
}