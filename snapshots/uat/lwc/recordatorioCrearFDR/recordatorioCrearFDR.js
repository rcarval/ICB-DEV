import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/Case.Status';

export default class RecordatorioCrearFDR extends LightningElement {

    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS_FIELD] })
    caseRecord;

    get showMessage() {
        const status = this.caseRecord?.data?.fields?.Status?.value;

        if (!status) {
            return false;
        }

        return status === 'En retiro';
    }
}