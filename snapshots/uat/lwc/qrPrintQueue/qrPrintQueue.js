import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUnprintedScans from '@salesforce/apex/QRPrintController.getUnprintedScans';
import markAsPrinted from '@salesforce/apex/QRPrintController.markAsPrinted';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { label: 'Miembro', fieldName: 'memberName', type: 'text' },
    { label: 'Token', fieldName: 'token', type: 'text' },
    { label: 'Fecha Escaneo', fieldName: 'scanDate', type: 'date' },
    { label: 'Usuario Escaneo', fieldName: 'scanUserName', type: 'text' },
    {
        label: 'Acción',
        type: 'button',
        typeAttributes: {
            label: 'Imprimir',
            name: 'print',
            title: 'Imprimir',
            variant: 'brand'
        }
    }
];

export default class QrPrintQueue extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    scans;

    get errorMessage() {
        return (
            this.scans?.error?.body?.message ||
            this.scans?.error?.message ||
            'Error desconocido'
        );
    }

    get noScans() {
        return !this.scans?.data && !this.scans?.error;
    }

    @wire(getUnprintedScans, { campaignId: '$recordId' })
    wiredScans(result) {
        this.scans = result;
    }

    refreshScans() {
        refreshApex(this.scans);
    }

    async handlePrint(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'print') {
            try {
                await markAsPrinted({ scanId: row.scanId });
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Impreso',
                        message: 'Escaneo marcado como impreso.',
                        variant: 'success'
                    })
                );
                refreshApex(this.scans);
            } catch (error) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'Error desconocido',
                        variant: 'error'
                    })
                );
            }
        }
    }
}