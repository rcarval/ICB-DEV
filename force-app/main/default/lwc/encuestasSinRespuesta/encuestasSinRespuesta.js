import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { NavigationMixin }         from 'lightning/navigation';
import getEmptySurveyData          from '@salesforce/apex/seidor_EncuestaQueryService.getEmptySurveyData';
import createExcelFile             from '@salesforce/apex/seidor_FileExportService.createExcelFile';

export default class EncuestasSinRespuesta extends NavigationMixin(LightningElement) {

    @track dateFrom        = this._defaultDateFrom();
    @track dateTo          = this._defaultDateTo();
    @track selectedAgent   = '';
    @track isLoading       = false;
    @track _allPreviewRows = [];

    // ── Computed — KPIs ───────────────────────────────────────────────────────

    get previewRows() {
        if (!this.selectedAgent) return this._allPreviewRows;
        return this._allPreviewRows.filter(r => r.agentUserId === this.selectedAgent);
    }

    get agentOptions() {
        const seen = new Set();
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        for (const r of this._allPreviewRows) {
            if (r.agentUserId && !seen.has(r.agentUserId)) {
                seen.add(r.agentUserId);
                opts.push({ label: r.agentName || r.agentUserId, value: r.agentUserId });
            }
        }
        return opts;
    }

    get hasPreview() { return this.previewRows.length > 0; }

    get totalCount()         { return this.previewRows.length; }
    get sinRespuestaCount()  { return this.previewRows.filter(r => r.categoria === 'sin_respuesta').length; }
    get sinRespuestaPct() {
        const t = this.totalCount;
        return t ? Math.round(this.sinRespuestaCount / t * 100) : 0;
    }

    get sinRespuestaDisplay() { return `${this.sinRespuestaCount} (${this.sinRespuestaPct}%)`; }

    // ── Tabla y paginación ────────────────────────────────────────────────────

    @track currentPage = 1;
    static PAGE_SIZE = 7;

    get paginatedRows() {
        const start = (this.currentPage - 1) * EncuestasSinRespuesta.PAGE_SIZE;
        return this.previewRows.slice(start, start + EncuestasSinRespuesta.PAGE_SIZE);
    }
    get totalPages()   { return Math.max(1, Math.ceil(this.previewRows.length / EncuestasSinRespuesta.PAGE_SIZE)); }
    get pageInfo()     { return `Página ${this.currentPage} de ${this.totalPages}`; }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }
    handlePrevPage()   { if (!this.prevDisabled) this.currentPage--; }
    handleNextPage()   { if (!this.nextDisabled) this.currentPage++; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadData();
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleDateFromChange(e) { this.dateFrom      = e.detail.value; }
    handleDateToChange(e)   { this.dateTo        = e.detail.value; }
    handleAgentChange(e)    { this.selectedAgent = e.detail.value; this.currentPage = 1; }
    handleLoad()            { this._loadData(); }

    handleExport(event) {
        const choice = event.detail.value;
        const rows   = choice === 'visible' ? this.previewRows : this._allPreviewRows;
        this._exportToExcel(rows, 'encuestas_sin_respuesta');
    }

    // Navega al registro de MessagingSession al hacer clic en la columna "Sesión"
    handleSessionClick(event) {
        event.preventDefault();
        const sessionId = event.currentTarget.dataset.id;
        if (!sessionId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:      sessionId,
                objectApiName: 'MessagingSession',
                actionName:    'view'
            }
        });
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading       = true;
        this._allPreviewRows = [];
        this.selectedAgent   = '';
        this.currentPage     = 1;

        getEmptySurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo
        })
        .then(rows => {
            this._mapRows(rows || []);
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _mapRows(rows) {
        const mapped = rows.map(r => {
            const sinRespuesta = r.categoria === 'sin_respuesta';
            const status = !r.fcrAnswer && !r.csatAnswer ? 'Sin respuesta'
                        : r.status || 'Incompleta';
            const end = r.sessionEndTime;
            return {
                _key:              r.sessionId || r.sessionName,
                sessionId:         r.sessionId,
                sessionName:       r.sessionName,
                agentUserId:       r.agentId,
                agentName:         r.agentName   || 'Sin asignar',
                accountName:       r.accountName || '—',
                clientName:        r.clientName  || '—',
                sessionEndFmt:     end ? new Date(end).toLocaleString('es-CL') : '—',
                sessionEndTimeStr: end || null,
                fcrAnswer:         r.fcrAnswer  || null,
                csatAnswer:        r.csatAnswer || null,
                csatScore:         r.csatScore  ?? null,
                mejorAnswer:       r.mejorAnswer || null,
                status,
                statusClass: sinRespuesta ? 'badge-sin-respuesta'
                            : status === 'Completada' ? 'badge-completada' : 'badge-incompleta',
                categoria:         r.categoria
            };
        });
        mapped.sort((a, b) => {
            const ta = a.sessionEndTimeStr ? new Date(a.sessionEndTimeStr).getTime() : 0;
            const tb = b.sessionEndTimeStr ? new Date(b.sessionEndTimeStr).getTime() : 0;
            return tb - ta;
        });
        this._allPreviewRows = mapped;
    }

    // ── Export ────────────────────────────────────────────────────────────────

    _exportToExcel(rows, filename) {
        const cols = [
            { label: 'Sesión',            fieldName: 'sessionName'   },
            { label: 'Ejecutivo',         fieldName: 'agentName'     },
            { label: 'Cuenta',            fieldName: 'accountName'   },
            { label: 'Contacto',          fieldName: 'clientName'    },
            { label: 'Fin Sesión',        fieldName: 'sessionEndFmt' },
            { label: '¿Resuelta? (FCR)',  fieldName: 'fcrAnswer'     },
            { label: 'Calificación CSAT', fieldName: 'csatAnswer'    },
            { label: '¿Qué mejorarías?',  fieldName: 'mejorAnswer'   },
            { label: 'Categoría',         fieldName: 'status'        }
        ];
        const esc = v => String(v == null ? '' : v)
            .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        let html = '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>'
            + 'table{border-collapse:collapse;font-family:Arial,sans-serif;font-size:11pt;}'
            + 'th{background:#2b6cb0;color:#fff;padding:6px 10px;border:1px solid #1a4a7a;font-weight:bold;}'
            + 'td{padding:4px 8px;border:1px solid #ccc;}'
            + 'tr:nth-child(even) td{background:#f0f4ff;}'
            + '</style></head><body><table><thead><tr>';
        html += cols.map(c => `<th>${esc(c.label)}</th>`).join('');
        html += '</tr></thead><tbody>';
        rows.forEach(row => {
            html += '<tr>' + cols.map(c => `<td>${esc(row[c.fieldName])}</td>`).join('') + '</tr>';
        });
        html += '</tbody></table></body></html>';
        createExcelFile({ htmlContent: html, filename })
            .then(versionId => {
                window.open('/sfc/servlet.shepherd/version/download/' + versionId, '_blank');
            })
            .catch(err => this._toast('Error', err.body?.message || 'Error generando Excel', 'error'));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _defaultDateFrom() {
        const d = new Date();
        d.setDate(d.getDate() - 30);
        return d.toISOString().split('T')[0];
    }

    _defaultDateTo() {
        return new Date().toISOString().split('T')[0];
    }
}