import { LightningElement, track } from 'lwc';
import { loadScript }              from 'lightning/platformResourceLoader';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { NavigationMixin }         from 'lightning/navigation';
import CHART_JS                    from '@salesforce/resourceUrl/chartJs';
import getSurveyData               from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';
import createExcelFile             from '@salesforce/apex/seidor_FileExportService.createExcelFile';

const CSAT_COLORS = {
    'muy buena': '#27ae60', 'buena': '#82cc5a',
    'regular':   '#f39c12', 'mala':  '#e67e22', 'muy mala': '#e74c3c'
};
const FALLBACK_COLORS = ['#3498db', '#9b59b6', '#1abc9c', '#e74c3c', '#f39c12', '#34495e'];


export default class EncuestaCreationDashboard extends NavigationMixin(LightningElement) {

    @track dateFrom        = this._defaultDateFrom();
    @track dateTo          = this._defaultDateTo();
    @track selectedAgent   = '';
    @track isLoading       = false;
    @track _allPreviewRows = [];
    @track lastResult      = null;

    // Chart.js state
    _chartLibLoaded = false;
    _csatChart      = null;  _csatHash      = null;
    _fcrChart       = null;  _fcrHash       = null;
    _estadoChart    = null;  _estadoHash    = null;
    _agentChart     = null;  _agentHash     = null;

    // ── Computed — datos ──────────────────────────────────────────────────────

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

    get hasPreview()       { return this.previewRows.length > 0; }
    get completadasCount() { return this.previewRows.filter(r => r.status === 'Completada').length; }
    get incompletasCount() { return this.previewRows.filter(r => r.status === 'Incompleta').length; }

    get csatSatisfactionDisplay() {
        return this.csatChartData ? this.csatChartData.csatPct + '%' : '—';
    }
    get csatRespondedCount() {
        return this.csatChartData ? this.csatChartData.total : 0;
    }
    get hasCsatMetric() {
        return !!this.csatChartData;
    }

    get fcrSatisfactionDisplay() {
        return this.fcrChartData ? this.fcrChartData.siPct + '%' : '—';
    }
    get fcrRespondedCount() {
        return this.fcrChartData ? this.fcrChartData.total : 0;
    }
    get hasFcrMetric() {
        return !!this.fcrChartData;
    }

    // ── Computed — gráficos ───────────────────────────────────────────────────

    get csatChartData() {
        const rows = this.previewRows.filter(r => r.csatScore != null);
        if (!rows.length) return null;
        const counts = {};
        rows.forEach(r => {
            const k = (r.csatAnswer || '').toLowerCase();
            counts[k] = (counts[k] || 0) + 1;
        });
        const total   = rows.length;
        const sat     = rows.filter(r => r.csatScore >= 4).length;
        const csatPct = Math.round(sat / total * 100);
        let fi = 0;
        const segments = Object.entries(counts)
            .sort((a, b) => b[1] - a[1])
            .map(([ans, count]) => {
                const color = CSAT_COLORS[ans] || FALLBACK_COLORS[fi++ % FALLBACK_COLORS.length];
                return {
                    label: ans.charAt(0).toUpperCase() + ans.slice(1),
                    count, color,
                    pct: Math.round(count / total * 100),
                    dotStyle: `background:${color};width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;`
                };
            });
        const sum = segments.reduce((a, s) => a + s.pct, 0);
        if (segments.length && sum !== 100) segments[0].pct += (100 - sum);
        return { total, segments, csatPct };
    }
    get hasCsatChartData() { return !!this.csatChartData; }

    get fcrChartData() {
        const rows = this.previewRows.filter(r => r.fcrAnswer);
        if (!rows.length) return null;
        let si = 0, no = 0;
        rows.forEach(r => {
            const a = (r.fcrAnswer || '').toLowerCase();
            if (a === 'si') si++;
            else if (a === 'no') no++;
        });
        const total = si + no;
        if (!total) return null;
        const siPct = Math.round(si / total * 100);
        const segments = [
            { label: 'Sí', count: si, pct: siPct,       color: '#27ae60',
              dotStyle: 'background:#27ae60;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' },
            { label: 'No', count: no, pct: 100 - siPct, color: '#e74c3c',
              dotStyle: 'background:#e74c3c;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' }
        ].filter(s => s.count > 0);
        return { total, siPct, segments };
    }
    get hasFcrChartData() { return !!this.fcrChartData; }

    get estadoChartData() {
        const rows = this.previewRows;
        if (!rows.length) return null;
        let completada = 0, incompleta = 0;
        rows.forEach(r => { if (r.status === 'Completada') completada++; else incompleta++; });
        const total = completada + incompleta;
        const cPct  = Math.round(completada / total * 100);
        const segments = [
            { label: 'Completada', count: completada, pct: cPct,       color: '#27ae60',
              dotStyle: 'background:#27ae60;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' },
            { label: 'Incompleta', count: incompleta, pct: 100 - cPct, color: '#f39c12',
              dotStyle: 'background:#f39c12;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' }
        ].filter(s => s.count > 0);
        return { total, segments };
    }
    get hasEstadoChartData() { return !!this.estadoChartData; }

    get agentCsatChartData() {
        const rows = this.previewRows.filter(r => r.csatScore != null && r.agentUserId);
        if (!rows.length) return null;
        const agentMap = {};
        rows.forEach(r => {
            const key = r.agentUserId;
            if (!agentMap[key]) agentMap[key] = { name: r.agentName || 'Sin asignar', scores: [] };
            agentMap[key].scores.push(r.csatScore);
        });
        const results = Object.values(agentMap)
            .filter(ag => ag.scores.length > 0)
            .map(ag => ({
                name:  ag.name,
                pct:   Math.round(ag.scores.filter(s => s >= 4).length / ag.scores.length * 100),
                count: ag.scores.length
            }))
            .sort((a, b) => b.pct - a.pct);
        return results.length ? results : null;
    }
    get hasAgentCsatChartData() { return !!this.agentCsatChartData; }

    @track currentPage = 1;
    static PAGE_SIZE = 7;

    get paginatedRows() {
        const start = (this.currentPage - 1) * EncuestaCreationDashboard.PAGE_SIZE;
        return this.previewRows.slice(start, start + EncuestaCreationDashboard.PAGE_SIZE);
    }
    get totalPages()   { return Math.max(1, Math.ceil(this.previewRows.length / EncuestaCreationDashboard.PAGE_SIZE)); }
    get pageInfo()     { return `Página ${this.currentPage} de ${this.totalPages}`; }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }
    handlePrevPage()   { if (!this.prevDisabled) this.currentPage--; }
    handleNextPage()   { if (!this.nextDisabled) this.currentPage++; }

    @track _showHelp = false;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._maybeRenderAll();
            })
            .catch(err => console.error('Chart.js load error', err));
        this._loadData();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderAll();
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleToggleHelp()      { this._showHelp     = !this._showHelp; }
    handleDateFromChange(e) { this.dateFrom      = e.detail.value; }
    handleDateToChange(e)   { this.dateTo        = e.detail.value; }
    handleAgentChange(e)    { this.selectedAgent = e.detail.value; this.currentPage = 1; this._resetAllHashes(); }
    handleLoad()            { this._loadData(); }

    handleExport(event) {
        const choice = event.detail.value;
        const rows   = choice === 'visible' ? this.previewRows : this._allPreviewRows;
        this._exportToExcel(rows, 'encuestas_sesiones');
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

    @track activeChartTab   = 'fcr';
    get tabCsatActive()     { return this.activeChartTab === 'csat'; }
    get tabFcrActive()      { return this.activeChartTab === 'fcr'; }
    get tabEstadoActive()   { return this.activeChartTab === 'estado'; }
    get tabAgentActive()    { return this.activeChartTab === 'agent'; }
    get tabBtnCsat()        { return 'chart-tab-btn' + (this.activeChartTab === 'csat'   ? ' chart-tab-btn-active' : ''); }
    get tabBtnFcr()         { return 'chart-tab-btn' + (this.activeChartTab === 'fcr'    ? ' chart-tab-btn-active' : ''); }
    get tabBtnEstado()      { return 'chart-tab-btn' + (this.activeChartTab === 'estado' ? ' chart-tab-btn-active' : ''); }
    get tabBtnAgent()       { return 'chart-tab-btn' + (this.activeChartTab === 'agent'  ? ' chart-tab-btn-active' : ''); }
    handleChartTabClick(e) {
        const tab = e.currentTarget.dataset.tab;
        if (this.activeChartTab === tab) return;
        this.activeChartTab = tab;
        this._csatHash = this._fcrHash = this._estadoHash = this._agentHash = null;
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading       = true;
        this._allPreviewRows = [];
        this.selectedAgent   = '';
        this.currentPage     = 1;
        this.lastResult      = null;
        this.activeChartTab  = 'fcr';
        this._resetAllHashes();

        getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  null,
            csatOnly: false
        })
        .then(rows => {
            this._mapSurveyRows(rows || []);
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _mapSurveyRows(rows) {
        const mapped = rows.map(r => {
            const status = r.status || (r.fcrAnswer && r.csatAnswer ? 'Completada' : 'Incompleta');
            const end    = r.sessionEndTime;
            const mejorar = r.mejorAnswer || null;
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
                mejorAnswer:       mejorar,
                mejorTrunc:        mejorar ?? '—',
                status,
                statusClass: status === 'Completada' ? 'badge-completada' : 'badge-incompleta'
            };
        });
        mapped.sort((a, b) => {
            const ta = a.sessionEndTimeStr ? new Date(a.sessionEndTimeStr).getTime() : 0;
            const tb = b.sessionEndTimeStr ? new Date(b.sessionEndTimeStr).getTime() : 0;
            return tb - ta;
        });
        this._allPreviewRows = mapped.filter(r => r.fcrAnswer || r.csatAnswer);
    }

    // ── Chart renders ─────────────────────────────────────────────────────────

    _maybeRenderAll() {
        this._maybeRenderCsat();
        this._maybeRenderFcr();
        this._maybeRenderEstado();
        this._maybeRenderAgentCsat();
    }

    _resetAllHashes() {
        this._csatHash = this._fcrHash = this._estadoHash = this._agentHash = null;
    }

    _maybeRenderCsat() {
        const canvas = this.template.querySelector('canvas.enc-csat-pie');
        if (!canvas) { if (this._csatChart) { this._csatChart.destroy(); this._csatChart = null; } return; }
        const data = this.csatChartData;
        if (!data) return;
        const hash = data.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._csatHash === hash && this._csatChart) return;
        this._csatHash = hash;
        if (this._csatChart) { this._csatChart.destroy(); this._csatChart = null; }
        this._csatChart = this._buildDoughnut(canvas, data.segments);
    }

    _maybeRenderFcr() {
        const canvas = this.template.querySelector('canvas.enc-fcr-pie');
        if (!canvas) { if (this._fcrChart) { this._fcrChart.destroy(); this._fcrChart = null; } return; }
        const data = this.fcrChartData;
        if (!data) return;
        const hash = data.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._fcrHash === hash && this._fcrChart) return;
        this._fcrHash = hash;
        if (this._fcrChart) { this._fcrChart.destroy(); this._fcrChart = null; }
        this._fcrChart = this._buildDoughnut(canvas, data.segments);
    }

    _maybeRenderEstado() {
        const canvas = this.template.querySelector('canvas.enc-estado-pie');
        if (!canvas) { if (this._estadoChart) { this._estadoChart.destroy(); this._estadoChart = null; } return; }
        const data = this.estadoChartData;
        if (!data) return;
        const hash = data.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._estadoHash === hash && this._estadoChart) return;
        this._estadoHash = hash;
        if (this._estadoChart) { this._estadoChart.destroy(); this._estadoChart = null; }
        this._estadoChart = this._buildDoughnut(canvas, data.segments);
    }

    _maybeRenderAgentCsat() {
        const canvas = this.template.querySelector('canvas.enc-agent-csat-bar');
        if (!canvas) { if (this._agentChart) { this._agentChart.destroy(); this._agentChart = null; } return; }
        const data = this.agentCsatChartData;
        if (!data) return;
        const hash = data.map(d => `${d.name}:${d.pct}`).join('|');
        if (this._agentHash === hash && this._agentChart) return;
        this._agentHash = hash;
        if (this._agentChart) { this._agentChart.destroy(); this._agentChart = null; }
        this._agentChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: data.map(d => d.name),
                datasets: [{
                    label: 'CSAT %',
                    data:  data.map(d => d.pct),
                    backgroundColor: data.map(d => (d.pct >= 70 ? '#27ae60' : d.pct >= 50 ? '#f39c12' : '#e74c3c')),
                    borderRadius: 4
                }]
            },
            options: {
                indexAxis: 'y',
                responsive: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label: ctx => ` ${ctx.parsed.x}% (${data[ctx.dataIndex].count} resp.)`
                        }
                    }
                },
                scales: {
                    x: { min: 0, max: 100, ticks: { callback: v => v + '%' }, grid: { color: 'rgba(0,0,0,0.05)' } }
                }
            }
        });
    }

    _buildDoughnut(canvas, segments) {
        return new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: segments.map(s => s.label),
                datasets: [{
                    data:             segments.map(s => s.count),
                    backgroundColor:  segments.map(s => s.color),
                    borderWidth:      2,
                    borderColor:      '#ffffff',
                    hoverBorderWidth: 3
                }]
            },
            options: {
                responsive: false,
                cutout:     '52%',
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label(ctx) {
                                const seg = segments[ctx.dataIndex];
                                return ` ${ctx.label}: ${seg.count} (${seg.pct}%)`;
                            }
                        }
                    }
                }
            }
        });
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
            { label: 'Estado',            fieldName: 'status'        }
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