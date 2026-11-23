import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/Case.Status';

export default class RetiroWarning extends LightningElement {

    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS_FIELD] })
    caseRecord;

    get showMessage() {
        const status = this.caseRecord?.data?.fields?.Status?.value;

        console.log('Estado del Caso:', status);

        if (!status) {
            return false;
        }

        return status === 'En retiro';
    }
}