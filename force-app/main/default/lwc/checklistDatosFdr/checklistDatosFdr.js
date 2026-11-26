import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import evaluate from '@salesforce/apex/ChecklistDatosFdrController.evaluate';

const FLOW_API_NAME = 'Caso_Ingreso_de_Caso_mejorado';

export default class ChecklistDatosFdr extends NavigationMixin(LightningElement) {
    @api recordId;

    @track items = [];
    isComplete = false;
    canCreateCase = false;
    summaryMessage = '';
    isLoading = true;
    errorMessage;

    connectedCallback() {
        this.loadChecklist();
    }

    @api
    refresh() {
        return this.loadChecklist();
    }

    loadChecklist() {
        if (!this.recordId) {
            this.isLoading = false;
            this.errorMessage = 'No se recibió el Id de la cuenta.';
            return Promise.resolve();
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        return evaluate({ accountId: this.recordId })
            .then((result) => {
                this.items = (result.items || []).map((item) => ({
                    ...item,
                    iconName: item.ok ? 'utility:success' : 'utility:error',
                    iconVariant: item.ok ? 'success' : 'error',
                    statusLabel: item.ok ? 'OK' : 'Falta'
                }));
                this.isComplete = result.isComplete === true;
                this.canCreateCase = result.canCreateCase === true;
                this.summaryMessage = result.summaryMessage;
            })
            .catch((error) => {
                this.errorMessage =
                    error?.body?.message || error?.message || 'Error al evaluar el checklist.';
                this.items = [];
                this.isComplete = false;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get showCrearCaso() {
        return this.canCreateCase && this.isComplete && !this.isLoading && !this.errorMessage;
    }

    get showIncompleteBanner() {
        return !this.isLoading && !this.errorMessage && !this.isComplete;
    }

    get cardTitle() {
        return 'Checklist datos FDR';
    }

    handleRefresh() {
        this.loadChecklist();
    }

    handleCrearCaso() {
        if (!this.showCrearCaso) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No disponible',
                    message: this.summaryMessage || 'Completa el checklist antes de crear el caso.',
                    variant: 'warning'
                })
            );
            return;
        }
        const url =
            '/flow/' +
            FLOW_API_NAME +
            '?recordId=' +
            encodeURIComponent(this.recordId);
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url }
        });
    }
}
