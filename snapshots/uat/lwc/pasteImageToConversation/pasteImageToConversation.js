import { LightningElement, api, track } from 'lwc';
import uploadImage from '@salesforce/apex/seidor_WhatsAppCloudService.uploadImage';
import { sendTextMessage } from 'lightning/conversationToolkitApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const ALLOWED_TYPES = ['image/png', 'image/jpeg'];
const MAX_SIZE_BYTES = 5 * 1024 * 1024;

export default class PasteImageToConversation extends LightningElement {

    @api recordId;

    @track isLoading = false;

    connectedCallback() {
        this._pasteHandler = this.handlePaste.bind(this);
        document.addEventListener('paste', this._pasteHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('paste', this._pasteHandler);
    }

    handlePaste(event) {
        const items = (event.clipboardData || window.clipboardData)?.items;
        if (!items) return;

        const imageItem = Array.from(items).find((item) => item.type && item.type.startsWith('image/'));
        if (!imageItem) return;

        event.preventDefault();

        const file = imageItem.getAsFile();
        if (!file) return;

        if (!ALLOWED_TYPES.includes(file.type)) {
            this._toast('Formato no soportado', `Tipo de archivo ${file.type} no permitido.`, 'error');
            return;
        }
        if (file.size > MAX_SIZE_BYTES) {
            this._toast('Imagen muy grande', `Máximo ${MAX_SIZE_BYTES / 1024 / 1024} MB.`, 'error');
            return;
        }

        this._uploadAndSend(file);
    }

    _uploadAndSend(file) {
        this.isLoading = true;

        const reader = new FileReader();
        reader.onload = () => {
            const base64Data = reader.result.split(',')[1];
            const fileName = `whatsapp-${Date.now()}.${file.type === 'image/png' ? 'png' : 'jpg'}`;

            uploadImage({
                messagingSessionId: this.recordId,
                base64Data,
                fileName,
                mimeType: file.type
            })
                .then((result) => {
                    if (!result.success) {
                        throw new Error(result.error);
                    }
                    return sendTextMessage(this.recordId, {
                        text: '📎 Imagen adjunta (enlace privado): ' + result.publicUrl
                    });
                })
                .then(() => {
                    this._toast('Éxito', 'URL de imagen enviada por WhatsApp.', 'success');
                })
                .catch((error) => {
                    const message = error?.body?.message || error?.message || 'Error desconocido.';
                    this._toast('Error al enviar imagen', message, 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        };
        reader.onerror = () => {
            this.isLoading = false;
            this._toast('Error', 'No se pudo leer la imagen.', 'error');
        };
        reader.readAsDataURL(file);
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}