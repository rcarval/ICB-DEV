import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import ESTADO_FIELD from '@salesforce/schema/Case.Estado_Nota_de_Credito__c';

export default class NotaCreditoWarning extends LightningElement {

    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [ESTADO_FIELD] })
    caseRecord;

    get showMessage() {
        const estado = this.caseRecord?.data?.fields?.Estado_Nota_de_Credito__c?.value;
        const archivoCargado = this.caseRecord?.data?.fields?.Archivo_cargado__c?.value;

        console.log('Estado Nota de Crédito:', estado);

        if (!estado) {
            return false;
        }

        return estado.trim() === 'No lista' || archivoCargado === true;
    }
}