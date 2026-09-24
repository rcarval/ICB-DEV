import { LightningElement, api, wire } from 'lwc';
import {
    getRecord,
    getFieldValue
} from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getFocusedTabInfo, refreshTab } from 'lightning/platformWorkspaceApi';

import getDependentPicklists from '@salesforce/apex/MessagingSessionTipificacionCtrl.getDependentPicklists';
import saveTipificacion      from '@salesforce/apex/MessagingSessionTipificacionCtrl.saveTipificacion';
import esFueraDeHorario      from '@salesforce/apex/MessagingSessionTipificacionCtrl.esFueraDeHorario';
import handleStatusEnded     from '@salesforce/apex/MessagingSessionTipificacionCtrl.handleStatusEnded';

import STATUS_FIELD        from '@salesforce/schema/MessagingSession.Status';
import TIP_FIELD           from '@salesforce/schema/MessagingSession.Tipificacion__c';
import SUBTIP_FIELD        from '@salesforce/schema/MessagingSession.Sub_tipificacion__c';
import COMENTARIO_FIELD    from '@salesforce/schema/MessagingSession.Comentario__c';
import FUERA_HORARIO_FIELD from '@salesforce/schema/MessagingSession.Fuera_de_horario__c';

const FIELDS = [STATUS_FIELD, TIP_FIELD, SUBTIP_FIELD, COMENTARIO_FIELD, FUERA_HORARIO_FIELD];
const STATUS_ENDED = 'Ended';
const VALOR_OTROS  = 'otros';

export default class MessagingSessionTipificacion extends LightningElement {
    @api recordId;

    showModal = false;
    saving = false;
    errorMessage;
    _saved = false;

    tipificacion;
    subTipificacion;
    comentario;
    mostrarComentario = false;

    tipificacionOptions = [];
    subTipificacionOptions = [];

    _dependentMap = {};

    // ─── Drag state ──────────────────────────────────────────────────────────────
    _dragging = false;
    _startX = 0;
    _startY = 0;
    _origLeft = 0;
    _origTop = 0;

    connectedCallback() {
        this._dragMoveHandler = this._handleDragMove.bind(this);
        this._dragEndHandler = this._handleDragEnd.bind(this);
    }

    // ---------- Estado UI ----------
    get subDisabled() {
        return !this.tipificacion || this.subTipificacionOptions.length === 0;
    }

    get subPlaceholder() {
        return this.tipificacion
            ? 'Selecciona una opción'
            : 'Selecciona primero una Tipificación';
    }

    esOtros(valor) {
        if (!valor) return false;
        return String(valor).trim().toLowerCase() === VALOR_OTROS;
    }

    // ---------- Cargar picklists con dependencia desde Apex ----------
    @wire(getDependentPicklists)
    wiredPicklists({ data, error }) {
        if (data) {
            this.tipificacionOptions = (data.controllerOptions || []).map(o => ({
                label: o.label,
                value: o.value
            }));
            this._dependentMap = data.dependentMap || {};
            this._recalcularSubOpciones();
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('[Tipificacion] Error cargando picklists:', error);
            this.errorMessage =
                error?.body?.message ||
                error?.message ||
                'No se pudieron cargar las opciones de tipificación.';
        }
    }

    _recalcularSubOpciones() {
        if (!this.tipificacion || !this._dependentMap) {
            this.subTipificacionOptions = [];
            return;
        }
        const lista = this._dependentMap[this.tipificacion] || [];
        this.subTipificacionOptions = lista.map(o => ({
            label: o.label,
            value: o.value
        }));
    }

    // ---------- Suscripción al registro ----------
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    async wiredSession({ data, error }) {
        if (error || !data) return;

        const status       = getFieldValue(data, STATUS_FIELD);
        const tip          = getFieldValue(data, TIP_FIELD);
        const sub          = getFieldValue(data, SUBTIP_FIELD);
        const sinTipificar = !tip || !sub;

        if (status === STATUS_ENDED && sinTipificar) {
            if (this._saved) return;
            try {
                const fueraDeHorario = await esFueraDeHorario({ sessionId: this.recordId });
                if (!fueraDeHorario) {
                    await handleStatusEnded({ sessionId: this.recordId });
                    this.showModal = true;
                }
            } catch (e) {
                console.error('[Tipificacion] Error verificando fuera de horario:', e);
                this.showModal = true;
            }
        } else if (status === STATUS_ENDED && !sinTipificar) {
            this.showModal = false;
        }
    }

    // ---------- Drag handlers ----------
    handleDragStart(event) {
        const panel = this.template.querySelector('.tipificacion-panel');
        if (!panel) return;

        const rect = panel.getBoundingClientRect();

        this._dragging = true;
        this._startX = event.clientX;
        this._startY = event.clientY;
        this._origLeft = rect.left;
        this._origTop = rect.top;

        panel.style.left = rect.left + 'px';
        panel.style.top = rect.top + 'px';
        panel.style.bottom = 'auto';
        panel.style.right = 'auto';
        panel.classList.add('tipificacion-panel--dragging');

        document.addEventListener('mousemove', this._dragMoveHandler);
        document.addEventListener('mouseup', this._dragEndHandler);

        event.preventDefault();
    }

    _handleDragMove(event) {
        if (!this._dragging) return;
        const panel = this.template.querySelector('.tipificacion-panel');
        if (!panel) return;
        const dx = event.clientX - this._startX;
        const dy = event.clientY - this._startY;
        panel.style.left = (this._origLeft + dx) + 'px';
        panel.style.top = (this._origTop + dy) + 'px';
    }

    _handleDragEnd() {
        this._dragging = false;
        document.removeEventListener('mousemove', this._dragMoveHandler);
        document.removeEventListener('mouseup', this._dragEndHandler);
        const panel = this.template.querySelector('.tipificacion-panel');
        if (panel) panel.classList.remove('tipificacion-panel--dragging');
    }

    // ---------- Handlers ----------
    handleTipChange(event) {
        this.tipificacion = event.detail.value;
        this.subTipificacion = null;
        this.comentario = null;
        this.mostrarComentario = false;
        this.errorMessage = null;
        this._recalcularSubOpciones();
    }

    handleSubTipChange(event) {
        this.subTipificacion = event.detail.value;
        this.mostrarComentario = this.esOtros(this.subTipificacion);
        if (!this.mostrarComentario) {
            this.comentario = null;
        }
        this.errorMessage = null;
    }

    handleComentarioChange(event) {
        this.comentario = event.detail.value;
        this.errorMessage = null;
    }

    handleKeyDown(event) {
        if (event.key === 'Escape' || event.keyCode === 27) {
            event.preventDefault();
            event.stopPropagation();
        }
    }

    // ---------- Validación ----------
    validar() {
        let valido = true;

        const combos = this.template.querySelectorAll('lightning-combobox');
        combos.forEach(c => {
            c.reportValidity();
            if (!c.checkValidity()) valido = false;
        });

        if (!this.tipificacion || !this.subTipificacion) {
            this.errorMessage = 'Debes completar Tipificación y Sub-tipificación.';
            valido = false;
        }

        if (this.mostrarComentario) {
            const textarea = this.template.querySelector('lightning-textarea');
            if (textarea) {
                textarea.reportValidity();
                if (!textarea.checkValidity()) valido = false;
            }
            if (!this.comentario || this.comentario.trim() === '') {
                this.errorMessage =
                    'Debes ingresar un comentario cuando seleccionas "Otros".';
                valido = false;
            }
        }

        return valido;
    }

    // ---------- Guardar y refrescar ----------
    async handleSave() {
        if (!this.validar()) return;

        this.saving = true;
        this.errorMessage = null;

        try {
            await saveTipificacion({
                sessionId: this.recordId,
                tipificacion: this.tipificacion,
                subTipificacion: this.subTipificacion,
                comentario: this.mostrarComentario ? this.comentario : null
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Tipificación guardada',
                message: 'La sesión fue tipificada correctamente.',
                variant: 'success'
            }));

            this._saved = true;
            this.showModal = false;

            try {
                const tabInfo = await getFocusedTabInfo();
                await refreshTab(tabInfo.tabId);
            } catch (_e) {
                // Not in a workspace console or API not available — fall back
                // eslint-disable-next-line no-console
                console.warn('[Tipificacion] refreshTab skipped:', _e);
            }

        } catch (err) {
            this.errorMessage =
                err?.body?.message || err?.message || 'Error desconocido.';
            // eslint-disable-next-line no-console
            console.error('[Tipificacion] Error en save:', this.errorMessage);
        } finally {
            this.saving = false;
        }
    }
}