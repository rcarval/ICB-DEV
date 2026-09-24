import { LightningElement, track } from 'lwc';
import { loadScript }    from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS          from '@salesforce/resourceUrl/chartJs';
import getSurveyData     from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';
import createExcelFile   from '@salesforce/apex/seidor_FileExportService.createExcelFile';

// Colores para respuestas CSAT reconocidas
const CSAT_COLORS = {
    'muy buena': '#27ae60', 'buena': '#82cc5a',
    'regular':   '#f39c12', 'mala':  '#e67e22', 'muy mala': '#e74c3c',
    '5': '#27ae60', '4': '#82cc5a', '3': '#f39c12', '2': '#e67e22', '1': '#e74c3c'
};
const FALLBACK_COLORS = ['#3498db', '#9b59b6', '#1abc9c', '#e74c3c', '#f39c12', '#34495e'];


export default class SurveyPivotReport extends LightningElement {

    static PAGE_SIZE = 25;

    @track dateFrom         = this._defaultDateFrom();
    @track dateTo           = this._defaultDateTo();
    @track selectedAgent    = '';
    @track currentPage      = 1;
    @track isLoading        = false;

    // Datos fuente
    @track rawRows          = [];
    @track agentOptionsList = [];

    // Pivot
    @track pivotData        = [];
    @track pivotColumns     = [];

    // Chart.js state
    _chartLibLoaded   = false;
    _csatChart        = null;
    _sinoChart        = null;
    _csatDataHash     = null;
    _sinoDataHash     = null;
    _agentCsatChart   = null;
    _agentCsatHash    = null;

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasData()       { return this.pivotData && this.pivotData.length > 0; }
    get totalSessions() { return (this.rawRows || []).length; }
    get totalResponded(){ return (this.rawRows || []).filter(r => r.csatScore != null).length; }

    // Paginación
    get paginatedPivotData() {
        const start = (this.currentPage - 1) * SurveyPivotReport.PAGE_SIZE;
        return (this.pivotData || []).slice(start, start + SurveyPivotReport.PAGE_SIZE);
    }
    get totalPages()   { return Math.max(1, Math.ceil((this.pivotData || []).length / SurveyPivotReport.PAGE_SIZE)); }
    get pageInfo()     { return `Página ${this.currentPage} de ${this.totalPages}`; }
    get prevDisabled() { return this.currentPage <= 1; }
    get nextDisabled() { return this.currentPage >= this.totalPages; }

    // Opciones de filtro — 100% dinámicas, sin preguntas hardcodeadas
    get agentOptions() {
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        (this.agentOptionsList || []).forEach(o => opts.push(o));
        return opts;
    }

    // Resumen CSAT
    get csatSummary() {
        if (!this.rawRows || !this.rawRows.length) return null;

        let filtered = this.rawRows.filter(r => r.csatScore != null);
        if (this.selectedAgent) filtered = filtered.filter(r => r.agentId === this.selectedAgent);
        if (!filtered.length) return null;

        const LABEL = { 5: 'Muy buena', 4: 'Buena', 3: 'Regular', 2: 'Mala', 1: 'Muy mala' };
        const ORDER = ['Muy buena', 'Buena', 'Regular', 'Mala', 'Muy mala'];

        const counts = {};
        filtered.forEach(r => {
            const label = LABEL[r.csatScore] || String(r.csatScore);
            counts[label] = (counts[label] || 0) + 1;
        });

        const total   = filtered.length;
        const sat     = filtered.filter(r => r.csatScore >= 4).length;
        const csatPct = Math.round(sat / total * 100);
        let fi = 0;

        const segments = Object.entries(counts)
            .sort((a, b) => ORDER.indexOf(a[0]) - ORDER.indexOf(b[0]))
            .map(([label, count]) => {
                const color = CSAT_COLORS[label.toLowerCase()] || FALLBACK_COLORS[fi++ % FALLBACK_COLORS.length];
                return {
                    label, count, color,
                    pct:      Math.round(count / total * 100),
                    dotStyle: `background:${color};width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;`
                };
            });

        const sum = segments.reduce((acc, s) => acc + s.pct, 0);
        if (segments.length && sum !== 100) segments[0].pct += (100 - sum);

        return { total, segments, csatPct };
    }

    get hasCsatSummary() { return !!this.csatSummary; }

    get csatSatisfactionDisplay() {
        const s = this.csatSummary;
        if (!s || !s.total) return '—';
        return s.csatPct + '%';
    }

    get csatRespondedCount() {
        const s = this.csatSummary;
        if (!s) return 0;
        return s.total;
    }

    get hasCsatMetric() { return !!this.csatSummary; }

    // FCR
    get siNoSummary() {
        if (!this.rawRows || !this.rawRows.length) return null;

        let filtered = this.rawRows.filter(r => r.fcrAnswer != null);
        if (this.selectedAgent) filtered = filtered.filter(r => r.agentId === this.selectedAgent);
        if (!filtered.length) return null;

        const siCount = filtered.filter(r => r.fcrAnswer === 'Si').length;
        const noCount = filtered.filter(r => r.fcrAnswer === 'No').length;
        const total   = siCount + noCount;
        if (total === 0) return null;

        const siPct = Math.round(siCount / total * 100);
        const noPct = 100 - siPct;

        const segments = [
            { label: 'Sí',  count: siCount, pct: siPct, color: '#27ae60',
              dotStyle: 'background:#27ae60;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' },
            { label: 'No',  count: noCount, pct: noPct, color: '#e74c3c',
              dotStyle: 'background:#e74c3c;width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;' }
        ].filter(s => s.count > 0);

        return { total, segments };
    }

    get hasSiNoSummary() { return !!this.siNoSummary; }

    get agentCsatData() {
        if (!this.rawRows || !this.rawRows.length) return null;
        let rows = this.rawRows.filter(r => r.csatScore != null);
        if (this.selectedAgent) rows = rows.filter(r => r.agentId === this.selectedAgent);
        if (!rows.length) return null;
        const agentMap = {};
        rows.forEach(r => {
            const key = r.agentId || '__sin_asignar__';
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
    get hasAgentCsatData() { return !!this.agentCsatData; }

    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._maybeRenderCsat();
                this._maybeRenderSiNo();
                this._maybeRenderAgentCsat();
            })
            .catch(err => console.error('Chart.js load error', err));
        this._loadData();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderCsat();
        this._maybeRenderSiNo();
        this._maybeRenderAgentCsat();
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDateFromChange(e)  { this.dateFrom        = e.detail.value; }
    handleDateToChange(e)    { this.dateTo           = e.detail.value; }
    handleAgentChange(e)     { this.selectedAgent    = e.detail.value; this._buildPivot(); }

    handleLoad()             { this._loadData(); }
    handlePrevPage()         { if (!this.prevDisabled) this.currentPage--; }
    handleNextPage()         { if (!this.nextDisabled) this.currentPage++; }

    @track activeChartTab  = 'csat';
    get tabCsatActive()    { return this.activeChartTab === 'csat'; }
    get tabSiNoActive()    { return this.activeChartTab === 'sino'; }
    get tabAgentActive()   { return this.activeChartTab === 'agent'; }
    get tabBtnCsat()       { return 'chart-tab-btn' + (this.activeChartTab === 'csat'  ? ' chart-tab-btn-active' : ''); }
    get tabBtnSiNo()       { return 'chart-tab-btn' + (this.activeChartTab === 'sino'  ? ' chart-tab-btn-active' : ''); }
    get tabBtnAgent()      { return 'chart-tab-btn' + (this.activeChartTab === 'agent' ? ' chart-tab-btn-active' : ''); }
    handleChartTabClick(e) {
        const tab = e.currentTarget.dataset.tab;
        if (this.activeChartTab === tab) return;
        this.activeChartTab = tab;
        this._csatDataHash = this._sinoDataHash = this._agentCsatHash = null;
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading    = true;
        this.rawRows      = [];
        this.pivotData    = [];
        this.pivotColumns = [];
        this.currentPage  = 1;

        getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  null,
            csatOnly: false
        })
        .then(rows => {
            this.rawRows = rows || [];

            const agentMap = {};
            this.rawRows.forEach(r => {
                if (r.agentId && !agentMap[r.agentId]) {
                    agentMap[r.agentId] = { value: r.agentId, label: r.agentName };
                }
            });
            this.agentOptionsList = Object.values(agentMap)
                .sort((a, b) => (a.label || '').localeCompare(b.label));

            this._buildPivot();
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos de encuestas', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _buildPivot() {
        this.currentPage = 1;
        let rows = [...this.rawRows];

        if (this.selectedAgent) rows = rows.filter(r => r.agentId === this.selectedAgent);

        if (!rows.length) {
            this.pivotData    = [];
            this.pivotColumns = [];
            return;
        }

        const CSAT_LABEL = { 5: 'Muy buena', 4: 'Buena', 3: 'Regular', 2: 'Mala', 1: 'Muy mala' };

        this.pivotColumns = [
            { label: 'Ejecutivo',       fieldName: 'agentName',    type: 'text' },
            { label: 'Cliente',         fieldName: 'accountName',  type: 'text' },
            { label: 'Cuenta',          fieldName: 'accountName',  type: 'text' },
            { label: 'Contacto',        fieldName: 'clientName',   type: 'text' },
            { label: 'Teléfono',        fieldName: 'phone',        type: 'text' },
            { label: 'Fecha Encuesta',  fieldName: 'sessionEndFmt',type: 'text' },
            { label: '¿Resuelta?',      fieldName: 'fcrAnswer',    type: 'text' },
            { label: 'Calificación',    fieldName: 'csatLabel',    type: 'text' },
            { label: 'Puntaje CSAT',    fieldName: 'csatScore',    type: 'number' },
            { label: '¿Qué mejoramos?', fieldName: 'mejorAnswer',  type: 'text' },
            { label: 'Estado',          fieldName: 'status',       type: 'text' }
        ];

        rows.sort((a, b) => {
            const ta = a.sessionEndTime ? new Date(a.sessionEndTime).getTime() : 0;
            const tb = b.sessionEndTime ? new Date(b.sessionEndTime).getTime() : 0;
            return tb - ta;
        });

        this.pivotData = rows.map(r => ({
            _rowKey:      r.sessionId || r.sessionName,
            agentName:    r.agentName    || 'Sin asignar',
            accountName:  r.accountName  || '—',
            clientName:   r.clientName   || '—',
            phone:        r.phone        || '—',
            sessionEndFmt: r.sessionEndTime ? new Date(r.sessionEndTime).toLocaleString('es-CL') : '—',
            fcrAnswer:    r.fcrAnswer    || '—',
            csatLabel:    r.csatScore != null ? (CSAT_LABEL[r.csatScore] || String(r.csatScore)) : '—',
            csatScore:    r.csatScore    ?? null,
            mejorAnswer:  r.mejorAnswer  || '—',
            status:       r.status       || '—'
        }));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    handleExportPivot(event) {
        const choice = event.detail.value;
        const rows = choice === 'visible' ? this.paginatedPivotData : (this.pivotData || []);
        this._exportToExcel(rows, this.pivotColumns, 'reporte_encuestas');
    }

    _exportToExcel(rows, columns, filename) {
        const esc = v => String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        const fmt = val => {
            if (val == null || val === '') return '';
            if (typeof val === 'boolean') return val ? 'Sí' : 'No';
            if (typeof val === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(val)) {
                try { return new Date(val).toLocaleString('es-CL'); } catch { /* fall through */ }
            }
            return esc(String(val));
        };

        let html = '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>'
            + 'table{border-collapse:collapse;font-family:Arial,sans-serif;font-size:11pt;}'
            + 'th{background:#2b6cb0;color:#fff;padding:6px 10px;border:1px solid #1a4a7a;font-weight:bold;}'
            + 'td{padding:4px 8px;border:1px solid #ccc;}'
            + 'tr:nth-child(even) td{background:#f0f4ff;}'
            + '</style></head><body><table><thead><tr>';
        html += columns.map(c => `<th>${esc(c.label)}</th>`).join('');
        html += '</tr></thead><tbody>';
        rows.forEach(row => {
            html += '<tr>' + columns.map(c => `<td>${fmt(row[c.fieldName])}</td>`).join('') + '</tr>';
        });
        html += '</tbody></table></body></html>';

        createExcelFile({ htmlContent: html, filename })
            .then(versionId => {
                window.open('/sfc/servlet.shepherd/version/download/' + versionId, '_blank');
            })
            .catch(err => this._toast('Error', err.body?.message || 'Error generando Excel', 'error'));
    }

    _maybeRenderAgentCsat() {
        const canvas = this.template.querySelector('canvas.agent-csat-bar-chart');
        if (!canvas) { if (this._agentCsatChart) { this._agentCsatChart.destroy(); this._agentCsatChart = null; } return; }
        const data = this.agentCsatData;
        if (!data) return;
        const hash = data.map(d => `${d.name}:${d.pct}`).join('|');
        if (this._agentCsatHash === hash && this._agentCsatChart) return;
        this._agentCsatHash = hash;
        if (this._agentCsatChart) { this._agentCsatChart.destroy(); this._agentCsatChart = null; }
        this._agentCsatChart = new window.Chart(canvas, {
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
                    tooltip: { callbacks: { label: ctx => ` ${ctx.parsed.x}% (${data[ctx.dataIndex].count} resp.)` } }
                },
                scales: {
                    x: { min: 0, max: 100, ticks: { callback: v => v + '%' }, grid: { color: 'rgba(0,0,0,0.05)' } }
                }
            }
        });
    }

    _maybeRenderCsat() {
        const canvas = this.template.querySelector('canvas.csat-pie-chart');
        if (!canvas) { if (this._csatChart) { this._csatChart.destroy(); this._csatChart = null; } return; }
        const summary = this.csatSummary;
        if (!summary) return;
        const hash = summary.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._csatDataHash === hash && this._csatChart) return;
        this._csatDataHash = hash;
        if (this._csatChart) { this._csatChart.destroy(); this._csatChart = null; }
        this._csatChart = this._buildDoughnut(canvas, summary.segments);
    }

    _maybeRenderSiNo() {
        const canvas = this.template.querySelector('canvas.sino-pie-chart');
        if (!canvas) { if (this._sinoChart) { this._sinoChart.destroy(); this._sinoChart = null; } return; }
        const summary = this.siNoSummary;
        if (!summary) return;
        const hash = summary.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._sinoDataHash === hash && this._sinoChart) return;
        this._sinoDataHash = hash;
        if (this._sinoChart) { this._sinoChart.destroy(); this._sinoChart = null; }
        this._sinoChart = this._buildDoughnut(canvas, summary.segments);
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
                responsive:   false,
                cutout:       '52%',
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