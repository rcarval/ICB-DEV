import { LightningElement, track } from 'lwc';
import { loadScript }   from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS          from '@salesforce/resourceUrl/chartJs';
import getSurveyData     from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';


export default class CsatTrendDashboard extends LightningElement {

    @track dateFrom  = this._defaultDateFrom();
    @track dateTo    = this._defaultDateTo();
    @track isLoading = false;
    @track rawRows   = [];

    _chartLibLoaded  = false;
    _chartNeedsRender = false;
    _chart           = null;
    _chartConfig     = null;

    // ── ──────────────────────────────────────────────────────────────

    get hasData() { return this.rawRows && this.rawRows.length > 0; }

    get overallCsat() {
        const scores = (this.rawRows || []).map(r => r.csatScore).filter(s => s != null);
        if (!scores.length) return '—';
        return (scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(1);
    }

    get overallFcr() {
        const fcrRows = (this.rawRows || []).filter(r => r.fcrAnswer != null);
        if (!fcrRows.length) return '—';
        const si = fcrRows.filter(r => r.fcrAnswer === 'Si').length;
        return Math.round(si / fcrRows.length * 100) + '%';
    }

    get overallCsatPct() {
        const scores = (this.rawRows || []).map(r => r.csatScore).filter(s => s != null);
        if (!scores.length) return '—';
        return Math.round(scores.filter(s => s >= 4).length / scores.length * 100) + '%';
    }

    get totalResponses() { return (this.rawRows || []).length; }

    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._loadChartLib();
        this._loadData();
    }

    renderedCallback() {
        if (!this._chartLibLoaded || !this._chartNeedsRender) return;
        this._renderChart();
        this._chartNeedsRender = false;
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDateFromChange(e) { this.dateFrom = e.detail.value; }
    handleDateToChange(e)   { this.dateTo   = e.detail.value; }
    handleLoad()            { this._loadData(); }

    // ── Chart library ─────────────────────────────────────────────────────────

    _loadChartLib() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                if (this._chartNeedsRender && this._chartConfig) {
                    this._renderChart();
                    this._chartNeedsRender = false;
                }
            })
            .catch(err => console.error('Chart.js load error', err));
    }

    // ── Data ──────────────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading = true;
        this.rawRows   = [];
        if (this._chart) { this._chart.destroy(); this._chart = null; }

        getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  null,
            csatOnly: false
        })
        .then(rows => {
            this.rawRows = rows || [];
            this._buildChartConfig();
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _buildChartConfig() {
        // Group rows by ISO week (key = Monday date string for lexicographic sort)
        const weekMap = {};

        for (const row of (this.rawRows || [])) {
            const wk = this._weekKey(row.sessionEndTime);
            if (!wk) continue;
            if (!weekMap[wk]) {
                weekMap[wk] = {
                    label:      this._weekLabel(row.sessionEndTime),
                    csatScores: [],
                    fcrSi:      0,
                    fcrTotal:   0,
                    sessionIds: new Set()
                };
            }
            const w = weekMap[wk];

            if (row.csatScore != null) w.csatScores.push(row.csatScore);
            if (row.fcrAnswer != null) {
                w.fcrTotal++;
                if (row.fcrAnswer === 'Si') w.fcrSi++;
            }
            if (row.sessionId) w.sessionIds.add(row.sessionId);
        }

        const keys    = Object.keys(weekMap).sort();
        const labels  = keys.map(k => weekMap[k].label);
        const csatAvg = keys.map(k => {
            const sc = weekMap[k].csatScores;
            return sc.length
                ? parseFloat((sc.reduce((a, b) => a + b, 0) / sc.length).toFixed(2))
                : null;
        });
        const fcrPct = keys.map(k => {
            const w = weekMap[k];
            return w.fcrTotal > 0 ? Math.round(w.fcrSi / w.fcrTotal * 100) : null;
        });
        const volume = keys.map(k => weekMap[k].sessionIds.size);

        this._chartConfig = {
            type: 'line',
            data: {
                labels,
                datasets: [
                    {
                        label:              'CSAT Promedio',
                        data:               csatAvg,
                        borderColor:        '#1565c0',
                        backgroundColor:    'rgba(21,101,192,0.08)',
                        fill:               true,
                        tension:            0.35,
                        pointBackgroundColor: '#1565c0',
                        pointRadius:        5,
                        yAxisID:            'yLeft',
                        spanGaps:           true,
                        order:              0
                    },
                    {
                        label:              'FCR %',
                        data:               fcrPct,
                        borderColor:        '#27ae60',
                        backgroundColor:    'rgba(39,174,96,0)',
                        fill:               false,
                        tension:            0.35,
                        pointBackgroundColor: '#27ae60',
                        pointRadius:        5,
                        yAxisID:            'yRight',
                        spanGaps:           true,
                        order:              1
                    },
                    {
                        label:           'Sesiones',
                        type:            'bar',
                        data:            volume,
                        backgroundColor: 'rgba(155,89,182,0.35)',
                        borderColor:     '#9b59b6',
                        borderWidth:     1,
                        borderRadius:    3,
                        yAxisID:         'yVolume',
                        order:           2
                    }
                ]
            },
            options: {
                responsive:          true,
                maintainAspectRatio: false,
                interaction:         { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 12 }, padding: 16 } },
                    tooltip: {
                        callbacks: {
                            label(ctx) {
                                if (ctx.datasetIndex === 2) return ` Sesiones: ${ctx.parsed.y}`;
                                return ctx.datasetIndex === 0
                                    ? ` CSAT: ${ctx.parsed.y} / 5`
                                    : ` FCR: ${ctx.parsed.y}%`;
                            }
                        }
                    }
                },
                scales: {
                    yLeft: {
                        type:     'linear',
                        position: 'left',
                        min:      0,
                        max:      5,
                        title:    { display: true, text: 'CSAT (1–5)', font: { size: 11 } },
                        ticks:    { stepSize: 1 },
                        grid:     { color: 'rgba(0,0,0,0.05)' }
                    },
                    yRight: {
                        type:     'linear',
                        position: 'right',
                        min:      0,
                        max:      100,
                        title:    { display: true, text: 'FCR (%)', font: { size: 11 } },
                        ticks:    { callback: v => v + '%' },
                        grid:     { drawOnChartArea: false }
                    },
                    yVolume: {
                        type:     'linear',
                        position: 'right',
                        display:  false,
                        min:      0,
                        grid:     { drawOnChartArea: false }
                    }
                }
            }
        };

        if (this._chartLibLoaded) {
            this._renderChart();
        } else {
            this._chartNeedsRender = true;
        }
    }

    _renderChart() {
        const canvas = this.template.querySelector('canvas.trend-chart');
        if (!canvas) {
            this._chartNeedsRender = true;
            return;
        }
        if (this._chart) { this._chart.destroy(); this._chart = null; }
        // eslint-disable-next-line no-undef
        this._chart = new window.Chart(canvas, this._chartConfig);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _weekKey(dateStr) {
        if (!dateStr) return null;
        const d = new Date(dateStr);
        if (isNaN(d.getTime())) return null;
        const day  = d.getDay();
        const monday = new Date(d);
        monday.setDate(d.getDate() - day + (day === 0 ? -6 : 1));
        return monday.toISOString().split('T')[0]; // lexicographically sortable
    }

    _weekLabel(dateStr) {
        const key = this._weekKey(dateStr);
        if (!key) return '';
        const [, mm, dd] = key.split('-');
        return `${dd}/${mm}`;
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _defaultDateFrom() {
        const d = new Date();
        d.setDate(d.getDate() - 90);
        return d.toISOString().split('T')[0];
    }
    _defaultDateTo() { return new Date().toISOString().split('T')[0]; }
}