import { LightningElement, track } from 'lwc';
import { loadScript }     from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS           from '@salesforce/resourceUrl/chartJs';
import getSurveyData      from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';
import createExcelFile    from '@salesforce/apex/seidor_FileExportService.createExcelFile';

const PAGE_SIZE = 25;

const ESTADO_OPTS = [
    { label: 'Todos los estados', value: ''              },
    { label: 'Completada',        value: 'Completada'    },
    { label: 'Incompleta',        value: 'Incompleta'    }
];

export default class EncuestasListDashboard extends LightningElement {

    @track dateFrom       = this._defaultDateFrom();
    @track dateTo         = this._defaultDateTo();
    @track selectedAgent  = '';
    @track selectedEstado = '';
    @track currentPage    = 1;
    @track isLoading      = false;

    @track _allRows = [];

    _chartLibLoaded = false;
    _estadoPieChart = null;
    _estadoPieHash  = null;

    // ── Computed ──────────────────────────────────────────────────────────────

    get _filteredRows() {
        let data = this._allRows;
        if (this.selectedAgent)  data = data.filter(r => r.agentId === this.selectedAgent);
        if (this.selectedEstado) data = data.filter(r => r.estado  === this.selectedEstado);
        return data;
    }

    get rows() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this._filteredRows.slice(start, start + PAGE_SIZE);
    }

    get totalRows()     { return this._filteredRows.length; }
    get hasData()       { return this._filteredRows.length > 0; }
    get totalPages()    { return Math.max(1, Math.ceil(this.totalRows / PAGE_SIZE)); }
    get pageInfo()      { return `Página ${this.currentPage} de ${this.totalPages} · ${this.totalRows} registros`; }
    get prevDisabled()  { return this.currentPage <= 1; }
    get nextDisabled()  { return this.currentPage >= this.totalPages; }
    get estadoOptions() { return ESTADO_OPTS; }

    get agentOptions() {
        const seen = new Set();
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        for (const r of this._allRows) {
            if (r.agentId && !seen.has(r.agentId)) {
                seen.add(r.agentId);
                opts.push({ label: r.agentName, value: r.agentId });
            }
        }
        return opts;
    }

    get estadoChartData() {
        if (!this._filteredRows.length) return null;
        const COLORS = { 'Completada': '#27ae60', 'Incompleta': '#f39c12' };
        const counts = {};
        this._filteredRows.forEach(r => {
            const k = r.estado || 'Sin estado';
            counts[k] = (counts[k] || 0) + 1;
        });
        const segs = Object.entries(counts).map(([label, count]) => ({
            label, count, color: COLORS[label] || '#95a5a6'
        }));
        return segs.length ? { total: this._filteredRows.length, segments: segs } : null;
    }
    get hasEstadoChartData() { return !!this.estadoChartData; }

    @track _showHelp = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => { this._chartLibLoaded = true; this._maybeRenderEstadoPie(); })
            .catch(err => console.error('Chart.js load error', err));
        this._loadData();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderEstadoPie();
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDateFromChange(e)  { this.dateFrom      = e.detail.value; }
    handleDateToChange(e)    { this.dateTo         = e.detail.value; }
    handleAgentChange(e)     { this.selectedAgent  = e.detail.value; this.currentPage = 1; }
    handleEstadoChange(e)    { this.selectedEstado = e.detail.value; this.currentPage = 1; }
    handleSearch()           { this.currentPage = 1; this._loadData(); }
    handlePrevPage()         { if (!this.prevDisabled) this.currentPage--; }
    handleNextPage()         { if (!this.nextDisabled) this.currentPage++; }

    handleExport(event) {
        const choice = event.detail.value;
        const rows   = choice === 'visible' ? this.rows : this._filteredRows;
        this._exportToExcel(rows, 'encuestas_lista');
    }

    // ── Data ──────────────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading = true;
        this._allRows  = [];

        getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  null,
            csatOnly: false
        })
        .then(surveyRows => {
            this._allRows = this._buildRows(surveyRows || []);
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _buildRows(surveyRows) {
        return [...surveyRows]
            .sort((a, b) => {
                const ta = a.sessionEndTime ? new Date(a.sessionEndTime).getTime() : 0;
                const tb = b.sessionEndTime ? new Date(b.sessionEndTime).getTime() : 0;
                return tb - ta;
            })
            .map(r => {
                const estado = r.status || (r.fcrAnswer && r.csatAnswer ? 'Completada' : 'Incompleta');
                return {
                    _key:           r.sessionId,
                    sessionId:      r.sessionId,
                    agentId:        r.agentId,
                    agentName:      r.agentName    || 'Sin asignar',
                    clientName:     r.clientName   || null,
                    endUserPhone:   r.phone         || null,
                    accountName:    r.accountName  || null,
                    sessionDateFmt: r.sessionEndTime
                        ? new Date(r.sessionEndTime).toLocaleString('es-CL', {
                            day: '2-digit', month: '2-digit', year: 'numeric',
                            hour: '2-digit', minute: '2-digit'
                          })
                        : '—',
                    fcrAnswer:   r.fcrAnswer  || null,
                    csatAnswer:  r.csatAnswer || null,
                    csatScore:   r.csatScore,
                    csatClass:   this._csatClass(r.csatScore),
                    fcrClass:    this._fcrClass(r.fcrAnswer),
                    estado,
                    estadoClass: this._estadoClass(estado)
                };
            });
    }

    // ── Chart render ──────────────────────────────────────────────────────────

    _maybeRenderEstadoPie() {
        const canvas = this.template.querySelector('canvas.estado-pie-chart');
        if (!canvas) return;
        const data = this.estadoChartData;
        if (!data) return;
        const hash = data.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._estadoPieHash === hash && this._estadoPieChart) return;
        this._estadoPieHash = hash;
        if (this._estadoPieChart) { this._estadoPieChart.destroy(); this._estadoPieChart = null; }
        const total = data.total;
        this._estadoPieChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: data.segments.map(s => s.label),
                datasets: [{
                    data:            data.segments.map(s => s.count),
                    backgroundColor: data.segments.map(s => s.color),
                    borderWidth: 2, borderColor: '#ffffff', hoverBorderWidth: 3
                }]
            },
            options: {
                responsive: false,
                cutout: '52%',
                plugins: {
                    legend: { position: 'bottom', labels: { font: { size: 11 }, padding: 8 } },
                    tooltip: {
                        callbacks: {
                            label(ctx) {
                                const count = ctx.parsed;
                                const pct = Math.round(count / total * 100);
                                return ` ${ctx.label}: ${count} (${pct}%)`;
                            }
                        }
                    }
                }
            }
        });
    }

    // ── Helpers de estilo ─────────────────────────────────────────────────────

    _csatClass(score) {
        if (score == null) return 'pill-neutral';
        if (score >= 5)    return 'pill-green';
        if (score >= 4)    return 'pill-lightgreen';
        if (score >= 3)    return 'pill-yellow';
        if (score >= 2)    return 'pill-orange';
        return 'pill-red';
    }

    _fcrClass(fcr) {
        if (!fcr) return 'pill-neutral';
        const norm = fcr.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
        return norm === 'si' ? 'pill-green' : 'pill-red';
    }

    _estadoClass(estado) {
        if (estado === 'Completada') return 'badge-completada';
        if (estado === 'Incompleta') return 'badge-incompleta';
        return 'badge-neutral';
    }

    _exportToExcel(rows, filename) {
        const cols = [
            { label: 'Fecha Sesión',      fieldName: 'sessionDateFmt' },
            { label: 'Ejecutivo',         fieldName: 'agentName'      },
            { label: 'Cliente',           fieldName: 'clientName'     },
            { label: 'Teléfono',          fieldName: 'endUserPhone'   },
            { label: 'Cuenta',            fieldName: 'accountName'    },
            { label: 'FCR',               fieldName: 'fcrAnswer'      },
            { label: 'CSAT',              fieldName: 'csatAnswer'     },
            { label: 'Estado',            fieldName: 'estado'         }
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

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _defaultDateFrom() {
        const d = new Date();
        d.setDate(d.getDate() - 30);
        return d.toISOString().split('T')[0];
    }
    _defaultDateTo() { return new Date().toISOString().split('T')[0]; }
}