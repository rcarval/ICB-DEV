import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getUnprintedScans from '@salesforce/apex/QRPrintController.getUnprintedScans';
import getQRData from '@salesforce/apex/QRPrintController.getQRData';
import markAsPrinted from '@salesforce/apex/QRPrintController.markAsPrinted';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Miembro',
        fieldName: 'memberName',
        type: 'text',
        initialWidth: 320,
        cellAttributes: { class: 'wrapTextColumn' },
        typeAttributes: {
            tooltip: { fieldName: 'memberName' }
        }
    },
    {
        label: 'Tipo',
        fieldName: 'memberType',
        type: 'text',
        initialWidth: 120,
        cellAttributes: { class: 'wrapTextColumn' }
    },
    {
        label: 'Token Miembro',
        fieldName: 'memberToken',
        type: 'text',
        initialWidth: 280,
        cellAttributes: { class: 'wrapTextColumn' },
        typeAttributes: {
            tooltip: { fieldName: 'memberToken' }
        }
    },
    {
        label: 'Fecha Escaneo',
        fieldName: 'scanDate',
        type: 'date',
        initialWidth: 160
    },
    {
        label: 'Usuario Escaneo',
        fieldName: 'scanUserName',
        type: 'text',
        initialWidth: 160
    },
    {
        label: 'Imprimir',
        type: 'button',
        initialWidth: 130,
        typeAttributes: {
            label: 'Imprimir',
            name: 'printQR',
            title: 'Imprimir',
            variant: 'brand'
        }
    },
    {
        label: 'Estado',
        type: 'button',
        initialWidth: 160,
        typeAttributes: {
            label: 'Marcar impreso',
            name: 'markPrinted',
            title: 'Marcar como impreso',
            variant: 'neutral'
        }
    }
];

export default class QrPrintQueueAction extends LightningElement {
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

        if (!row?.scanId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'No se encontro el escaneo para esta accion.',
                    variant: 'error'
                })
            );
            return;
        }

        if (actionName === 'printQR') {
            await this.openQrInNewTab(row.scanId);
            return;
        }

        if (actionName === 'markPrinted') {
            await this.markScanAsPrinted(row.scanId);
        }
    }

    async openQrInNewTab(scanId) {
        let qrData;
        try {
            qrData = await getQRData({ scanId });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'No se pudo obtener el QR del miembro de campana.',
                    variant: 'error'
                })
            );
            return;
        }

        const encodedData = encodeURIComponent(qrData);
        const url = `https://api.qrserver.com/v1/create-qr-code/?size=200x200&margin=10&data=${encodedData}`;

        const win = window.open(url, '_blank');
        if (!win) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'El navegador bloqueo la ventana emergente.',
                    variant: 'error'
                })
            );
        }
    }

    async markScanAsPrinted(scanId) {
        try {
            await markAsPrinted({ scanId });
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
                    message: error?.body?.message || 'Error marcando como impreso',
                    variant: 'error'
                })
            );
        }
    }
}