import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import TIPICADA_FIELD from '@salesforce/schema/MessagingSession.Tipificada__c';
import NO_ASOCIADO_FIELD from '@salesforce/schema/MessagingSession.No_asociado_a_cliente__c';

const FIELDS = [TIPICADA_FIELD, NO_ASOCIADO_FIELD];

export default class Icbfs_messagingTipicada extends LightningElement {

    @api recordId;

    @track isTipicada = false;
    @track isNoAsociado = false;

    _dismissed = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.isTipicada = getFieldValue(data, TIPICADA_FIELD) === true;
            this.isNoAsociado = getFieldValue(data, NO_ASOCIADO_FIELD) === true;
        } else if (error) {
            this.isTipicada = false;
            this.isNoAsociado = false;
        }
    }

    get showTipicada() {
        return this.isTipicada && !this._dismissed;
    }

    get showNoAsociado() {
        return this.isNoAsociado && !this._dismissed;
    }

    get hasAnyBanner() {
        return this.isTipicada || this.isNoAsociado;
    }
}