import { LightningElement, track } from 'lwc';
import { loadScript }    from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS           from '@salesforce/resourceUrl/chartJs';
import getSurveyQAData    from '@salesforce/apex/seidor_SurveyPivotService.getSurveyQAData';

const BAR_COLORS = [
    '#c0392b','#e74c3c','#e67e22','#f39c12','#27ae60',
    '#1abc9c','#2980b9','#8e44ad','#16a085','#d35400'
];

export default class SurveyInsightsDashboard extends LightningElement {

    @track dateFrom          = this._defaultDateFrom();
    @track dateTo            = this._defaultDateTo();
    @track isLoading         = false;
    @track rawRows           = [];
    @track uniqueQuestions   = [];
    @track selectedQuestion  = '';
    @track topN              = 10;

    _chartLibLoaded   = false;
    _chartNeedsRender = false;
    _chart            = null;
    _chartConfig      = null;
    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasData()       { return this.rawRows && this.rawRows.length > 0; }
    get hasQuestion()   { return !!this.selectedQuestion; }

    get questionOptions() {
        const opts = [{ label: '— Selecciona una pregunta —', value: '' }];
        (this.uniqueQuestions || []).forEach(q => opts.push({
            label: q.length > 80 ? q.substring(0, 80) + '…' : q,
            value: q
        }));
        return opts;
    }

    get filteredAnswerCount() {
        if (!this.selectedQuestion) return 0;
        return (this.rawRows || []).filter(r => r.questionText === this.selectedQuestion).length;
    }

    get uniqueAnswerCount() {
        if (!this.selectedQuestion) return 0;
        return new Set(
            (this.rawRows || [])
                .filter(r => r.questionText === this.selectedQuestion)
                .map(r => (r.answerText || '').trim().toLowerCase())
        ).size;
    }

    get topNOptions() {
        return [
            { label: 'Top 5',   value: 5  },
            { label: 'Top 10',  value: 10 },
            { label: 'Top 20',  value: 20 }
        ];
    }

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

    handleDateFromChange(e)     { this.dateFrom         = e.detail.value; }
    handleDateToChange(e)       { this.dateTo            = e.detail.value; }
    handleLoad()                { this._loadData(); }
    handleQuestionChange(e)     { this.selectedQuestion  = e.detail.value; this._buildChartConfig(); }
    handleTopNChange(e)         { this.topN              = parseInt(e.detail.value, 10); this._buildChartConfig(); }

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
        this.isLoading       = true;
        this.rawRows         = [];
        this.uniqueQuestions = [];
        if (this._chart) { this._chart.destroy(); this._chart = null; }

        getSurveyQAData({
            dateFrom:      this.dateFrom,
            dateTo:        this.dateTo,
            agentId:       null,
            questionText:  null,
            statusFilter:  'Ended',
            limitSessions: 500
        })
        .then(result => {
            this.rawRows         = result.rows           || [];
            this.uniqueQuestions = result.uniqueQuestions || [];
            // Auto-select first question if none selected
            if (!this.selectedQuestion && this.uniqueQuestions.length) {
                this.selectedQuestion = this.uniqueQuestions[0];
            }
            if (this.selectedQuestion) this._buildChartConfig();
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _buildChartConfig() {
        if (!this.selectedQuestion) return;

        const filtered = (this.rawRows || []).filter(r => r.questionText === this.selectedQuestion);

        // Count frequency per answer (normalized to lowercase)
        const counts = {};
        for (const row of filtered) {
            const key = (row.answerText || '').trim();
            if (key) counts[key] = (counts[key] || 0) + 1;
        }

        const sorted = Object.entries(counts)
            .sort((a, b) => b[1] - a[1])
            .slice(0, this.topN);

        const labels = sorted.map(([ans]) => ans.length > 50 ? ans.substring(0, 50) + '…' : ans);
        const data   = sorted.map(([, cnt]) => cnt);
        const bgs    = data.map((_, i) => BAR_COLORS[i % BAR_COLORS.length]);

        this._chartConfig = {
            type: 'bar',
            data: {
                labels,
                datasets: [{
                    label:           'Respuestas',
                    data,
                    backgroundColor: bgs,
                    borderRadius:    4,
                    borderSkipped:   false
                }]
            },
            options: {
                indexAxis:           'y',
                responsive:          true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label(ctx) { return ` ${ctx.parsed.x} respuesta${ctx.parsed.x !== 1 ? 's' : ''}`; }
                        }
                    }
                },
                scales: {
                    x: {
                        beginAtZero: true,
                        ticks:       { precision: 0, font: { size: 11 } },
                        grid:        { color: 'rgba(0,0,0,0.05)' }
                    },
                    y: {
                        ticks: { font: { size: 11 } }
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
        const canvas = this.template.querySelector('canvas.insights-chart');
        if (!canvas) {
            this._chartNeedsRender = true;
            return;
        }
        if (this._chart) { this._chart.destroy(); this._chart = null; }
        // eslint-disable-next-line no-undef
        this._chart = new window.Chart(canvas, this._chartConfig);
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
    _defaultDateTo() { return new Date().toISOString().split('T')[0]; }
}