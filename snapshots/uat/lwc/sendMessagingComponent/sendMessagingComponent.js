import { LightningElement, api, track } from 'lwc';
import { sendMessagingComponent } from 'lightning/conversationToolkitApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SendMessagingComponent extends LightningElement {

    @api recordId;
    @api componentDeveloperName = 'encuestaPreguntaV1';
    @api buttonLabel = 'Enviar Encuesta';

    @track isLoading = false;

    get isDisabled() {
        return !this.recordId || this.isLoading;
    }

    handleSend() {
        if (this.isLoading) return;

        if (!this.componentDeveloperName) {
            this._showToast(
                'Configuración incompleta',
                'No se ha definido el componente de mensajería.',
                'error'
            );
            return;
        }

        this.isLoading = true;

        sendMessagingComponent(this.recordId, {
            messageType: 'Text',
            nameOrId: this.componentDeveloperName
        })
        .then(() => {
            this._showToast('Éxito', 'Componente enviado correctamente.', 'success');
        })
        .catch(error => {
            console.error('[sendMessagingComponent] error completo:', JSON.stringify(error));
            const message =
                error?.body?.message ||
                error?.message ||
                'Error desconocido.';
            this._showToast('Error al enviar', message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}