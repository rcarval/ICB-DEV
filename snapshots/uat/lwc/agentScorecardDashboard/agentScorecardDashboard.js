import { LightningElement, track } from 'lwc';
import { loadScript }    from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS          from '@salesforce/resourceUrl/chartJs';
import getAgentSessions  from '@salesforce/apex/seidor_ResponseTimeService.getAgentSessions';
import getSurveyData     from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';
import createExcelFile   from '@salesforce/apex/seidor_FileExportService.createExcelFile';

export default class AgentScorecardDashboard extends LightningElement {

    @track dateFrom      = this._defaultDateFrom();
    @track dateTo        = this._defaultDateTo();
    @track isLoading     = false;
    @track scorecardRows = [];
    @track sortField     = 'totalSessions';
    @track sortAsc       = false;

    // ── Chart.js state ────────────────────────────────────────────────────────
    _chartLibLoaded = false;
    _csatBarChart   = null;
    _csatBarHash    = null;
    _fcrBarChart    = null;
    _fcrBarHash     = null;

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasData() { return this.scorecardRows && this.scorecardRows.length > 0; }

    get sortedRows() {
        return [...(this.scorecardRows || [])].sort((a, b) => {
            const va = a[this.sortField] ?? -1;
            const vb = b[this.sortField] ?? -1;
            if (typeof va === 'string') {
                return this.sortAsc ? va.localeCompare(vb, 'es') : vb.localeCompare(va, 'es');
            }
            return this.sortAsc ? va - vb : vb - va;
        });
    }

    get totalAgents()   { return this.scorecardRows.length; }
    get totalSessions() { return this.scorecardRows.reduce((acc, r) => acc + (r.totalSessions || 0), 0); }

    get overallCsat() {
        const rows = this.scorecardRows.filter(r => r.csatCount > 0);
        if (!rows.length) return '—';
        const sat   = rows.reduce((acc, r) => acc + r.csatPct / 100 * r.csatCount, 0);
        const total = rows.reduce((acc, r) => acc + r.csatCount, 0);
        return total > 0 ? Math.round(sat / total * 100) + '%' : '—';
    }

    get overallFcr() {
        const si    = this.scorecardRows.reduce((acc, r) => acc + (r.fcrSi    || 0), 0);
        const total = this.scorecardRows.reduce((acc, r) => acc + (r.fcrTotal || 0), 0);
        return total > 0 ? Math.round(si / total * 100) + '%' : '—';
    }

    get csatBarChartData() {
        const rows = (this.scorecardRows || []).filter(r => r.csatPct != null);
        if (!rows.length) return null;
        const sorted = [...rows].sort((a, b) => (b.csatPct || 0) - (a.csatPct || 0));
        return {
            labels: sorted.map(r => r.agentName),
            values: sorted.map(r => r.csatPct),
            colors: sorted.map(r => (r.csatPct >= 70 ? '#27ae60' : r.csatPct >= 50 ? '#f39c12' : '#e74c3c'))
        };
    }
    get hasCsatBarChart() { return !!this.csatBarChartData; }

    get fcrBarChartData() {
        const rows = (this.scorecardRows || []).filter(r => r.fcrPct != null);
        if (!rows.length) return null;
        const sorted = [...rows].sort((a, b) => (b.fcrPct || 0) - (a.fcrPct || 0));
        return {
            labels: sorted.map(r => r.agentName),
            values: sorted.map(r => r.fcrPct),
            colors: sorted.map(r => (r.fcrPct >= 80 ? '#27ae60' : r.fcrPct >= 60 ? '#f39c12' : '#e74c3c'))
        };
    }
    get hasFcrBarChart() { return !!this.fcrBarChartData; }

    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._maybeRenderCsatBar();
                this._maybeRenderFcrBar();
            })
            .catch(err => console.error('Chart.js load error', err));
        this._loadData();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderCsatBar();
        this._maybeRenderFcrBar();
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleDateFromChange(e) { this.dateFrom = e.detail.value; }
    handleDateToChange(e)   { this.dateTo   = e.detail.value; }
    handleLoad()            { this._loadData(); }

    handleExport(event) {
        const choice = event.detail.value;
        const rows   = choice === 'visible' ? this.sortedRows : this.scorecardRows;
        this._exportToExcel(rows, 'scorecard_ejecutivos');
    }

    handleSort(e) {
        const field = e.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortAsc = !this.sortAsc;
        } else {
            this.sortField = field;
            this.sortAsc   = false;
        }
    }

    // ── Data ──────────────────────────────────────────────────────────────────

    _loadData() {
        this.isLoading     = true;
        this.scorecardRows = [];

        Promise.all([
            getAgentSessions({
                dateFrom: this.dateFrom, dateTo: this.dateTo,
                agentId: null, limitSessions: 3000
            }),
            getSurveyData({
                dateFrom: this.dateFrom, dateTo: this.dateTo,
                agentId: null, csatOnly: false
            })
        ])
        .then(([sessResult, surveyRows]) => {
            this._buildScorecard(
                sessResult.agentGroups || [],
                surveyRows              || []
            );
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando datos', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _buildScorecard(agentGroups, surveyRows) {
        // ── Aggregate sessions per agent ───────────────────────────────────────
        const agentMap = {};

        for (const group of agentGroups) {
            const key = group.agentId || '__sin_asignar__';
            if (!agentMap[key]) {
                agentMap[key] = {
                    agentId:           group.agentId,
                    agentName:         group.agentName || 'Sin asignar',
                    totalSessions:     0,
                    totalDurationMins: 0
                };
            }
            const ag = agentMap[key];
            for (const s of (group.sessions || [])) {
                ag.totalSessions++;
                ag.totalDurationMins += s.durationMinutes || 0;
            }
        }

        // ── Aggregate survey per agent ─────────────────────────────────────────
        const surveyByAgent = {};

        for (const row of surveyRows) {
            const key = row.agentId || '__sin_asignar__';
            if (!surveyByAgent[key]) {
                surveyByAgent[key] = { csatScores: [], fcrSi: 0, fcrTotal: 0 };
            }
            const sa = surveyByAgent[key];

            if (row.csatScore != null) {
                sa.csatScores.push(row.csatScore);
            }
            if (row.fcrAnswer != null) {
                sa.fcrTotal++;
                if (row.fcrAnswer.trim().toLowerCase() === 'si') sa.fcrSi++;
            }
        }

        // ── Combine ────────────────────────────────────────────────────────────
        this.scorecardRows = Object.values(agentMap)
            .filter(ag => ag.agentId !== null)
            .map(ag => {
            const sv = surveyByAgent[ag.agentId || '__sin_asignar__']
                       || { csatScores: [], fcrSi: 0, fcrTotal: 0 };

            const csatPct = sv.csatScores.length
                ? Math.round(sv.csatScores.filter(s => s >= 4).length / sv.csatScores.length * 100)
                : null;

            const fcrPct = sv.fcrTotal > 0
                ? Math.round(sv.fcrSi / sv.fcrTotal * 100)
                : null;

            const avgDuration = ag.totalSessions > 0
                ? Math.round(ag.totalDurationMins / ag.totalSessions)
                : 0;

            return {
                agentId:        ag.agentId,
                agentName:      ag.agentName,
                totalSessions:  ag.totalSessions,
                avgDuration,
                avgDurationFmt: this._formatMins(avgDuration),
                csatPct,
                csatFmt:        csatPct != null ? csatPct + '%' : '—',
                csatCount:      sv.csatScores.length,
                csatClass:      'score-badge ' + this._csatClass(csatPct),
                fcrPct,
                fcrFmt:         fcrPct != null ? fcrPct + '%' : '—',
                fcrSi:          sv.fcrSi,
                fcrTotal:       sv.fcrTotal,
                fcrClass:       'score-badge ' + this._fcrClass(fcrPct)
            };
        });
    }

    // ── Chart render ──────────────────────────────────────────────────────────

    _maybeRenderCsatBar() {
        const canvas = this.template.querySelector('canvas.sc-csat-bar');
        if (!canvas) return;
        const data = this.csatBarChartData;
        if (!data) return;
        const hash = data.values.join(',');
        if (this._csatBarHash === hash && this._csatBarChart) return;
        this._csatBarHash = hash;
        if (this._csatBarChart) { this._csatBarChart.destroy(); this._csatBarChart = null; }
        this._csatBarChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: data.labels,
                datasets: [{ label: 'CSAT %', data: data.values, backgroundColor: data.colors, borderRadius: 4 }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: { callbacks: { label: ctx => ` ${ctx.parsed.x}%` } }
                },
                scales: {
                    x: { min: 0, max: 100, ticks: { callback: v => v + '%' }, grid: { color: 'rgba(0,0,0,0.05)' } }
                }
            }
        });
    }

    _maybeRenderFcrBar() {
        const canvas = this.template.querySelector('canvas.sc-fcr-bar');
        if (!canvas) return;
        const data = this.fcrBarChartData;
        if (!data) return;
        const hash = data.values.join(',');
        if (this._fcrBarHash === hash && this._fcrBarChart) return;
        this._fcrBarHash = hash;
        if (this._fcrBarChart) { this._fcrBarChart.destroy(); this._fcrBarChart = null; }
        this._fcrBarChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: data.labels,
                datasets: [{ label: 'FCR %', data: data.values, backgroundColor: data.colors, borderRadius: 4 }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: { callbacks: { label: ctx => ` ${ctx.parsed.x}%` } }
                },
                scales: {
                    x: { min: 0, max: 100, ticks: { callback: v => v + '%' }, grid: { color: 'rgba(0,0,0,0.05)' } }
                }
            }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _csatClass(pct) {
        if (pct == null) return 'score-neutral';
        if (pct >= 70)   return 'score-good';
        if (pct >= 50)   return 'score-warn';
        return 'score-bad';
    }

    _fcrClass(pct) {
        if (pct == null) return 'score-neutral';
        if (pct >= 80)   return 'score-good';
        if (pct >= 60)   return 'score-warn';
        return 'score-bad';
    }

    _formatMins(mins) {
        if (mins == null || mins < 0) return '—';
        const m  = Math.round(Number(mins));
        if (m < 60) return `${m}m`;
        const h  = Math.floor(m / 60);
        const rm = m % 60;
        return rm > 0 ? `${h}h ${rm}m` : `${h}h`;
    }

    _exportToExcel(rows, filename) {
        const cols = [
            { label: 'Ejecutivo',      fieldName: 'agentName'      },
            { label: 'Sesiones',       fieldName: 'totalSessions'  },
            { label: 'Duración Prom.', fieldName: 'avgDurationFmt' },
            { label: 'CSAT %',         fieldName: 'csatFmt'        },
            { label: 'Resp. CSAT',     fieldName: 'csatCount'      },
            { label: 'FCR %',          fieldName: 'fcrFmt'         },
            { label: 'FCR (Sí/Total)', fieldName: 'fcrDetail'      }
        ];
        const esc = v => String(v == null ? '' : v)
            .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        const data = rows.map(r => ({
            ...r,
            fcrDetail: `${r.fcrSi}/${r.fcrTotal}`
        }));
        let html = '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>'
            + 'table{border-collapse:collapse;font-family:Arial,sans-serif;font-size:11pt;}'
            + 'th{background:#2b6cb0;color:#fff;padding:6px 10px;border:1px solid #1a4a7a;font-weight:bold;}'
            + 'td{padding:4px 8px;border:1px solid #ccc;}'
            + 'tr:nth-child(even) td{background:#f0f4ff;}'
            + '</style></head><body><table><thead><tr>';
        html += cols.map(c => `<th>${esc(c.label)}</th>`).join('');
        html += '</tr></thead><tbody>';
        data.forEach(row => {
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

    _defaultDateTo() {
        return new Date().toISOString().split('T')[0];
    }
}