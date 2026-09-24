import { LightningElement, api } from 'lwc';
import generarPdf from '@salesforce/apex/ICB_PdfRecoveryMemoryController.generarPdf';

// Downloads the PDF from Flow memory, regenerating it only for download when needed.
export default class FlowPdfRecoveryDownload extends LightningElement {
    // Kept only for compatibility with obsolete Flow versions; never used.
    @api contentVersionId = '';
    @api pdfBase64 = '';
    @api pdfFileName = '';
    @api opportunityId = '';

    isLoading = false;
    downloadError = '';

    get hasDownloadablePdf() {
        return Boolean(this.pdfBase64 || this.opportunityId);
    }

    get isDownloadUnavailable() {
        return !this.hasDownloadablePdf || this.isLoading;
    }

    get helpText() {
        if (this.pdfBase64) {
            return 'El PDF está disponible para descarga y no se guardó en Archivos.';
        }
        if (this.opportunityId) {
            return 'Al descargar, el PDF se regenerará sin guardarlo en Archivos.';
        }
        return 'No hay información suficiente para regenerar el PDF.';
    }

    async handleDownload() {
        if (!this.hasDownloadablePdf || this.isLoading) {
            return;
        }

        this.isLoading = true;
        this.downloadError = '';
        try {
            let base64 = this.pdfBase64;
            let fileName = this.pdfFileName;
            if (!base64) {
                const regenerated = await generarPdf({ opportunityId: this.opportunityId });
                base64 = regenerated?.pdfBase64;
                fileName = regenerated?.pdfFileName;
            }
            if (!base64) {
                throw new Error('El PDF regenerado está vacío.');
            }
            this.download(base64, fileName);
        } catch (error) {
            this.downloadError = error?.body?.message || error?.message || 'No se pudo descargar el PDF.';
        } finally {
            this.isLoading = false;
        }
    }

    download(pdfBase64, pdfFileName) {
        const base64 = pdfBase64.includes(',') ? pdfBase64.split(',').pop() : pdfBase64;
        const binary = window.atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) {
            bytes[index] = binary.charCodeAt(index);
        }

        const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
        const link = document.createElement('a');
        link.href = url;
        link.download = pdfFileName || 'Contrato_Comodato.pdf';
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);
    }
}