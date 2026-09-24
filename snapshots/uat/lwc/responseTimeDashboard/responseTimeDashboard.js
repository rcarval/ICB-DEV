import { LightningElement, track } from 'lwc';
import { loadScript }        from 'lightning/platformResourceLoader';
import { ShowToastEvent }    from 'lightning/platformShowToastEvent';
import CHART_JS              from '@salesforce/resourceUrl/chartJs';
import getAgentSessions      from '@salesforce/apex/seidor_ResponseTimeService.getAgentSessions';
import getMessagesByUUID     from '@salesforce/apex/seidor_ConversationDataService.getMessagesByUUID';
import createExcelFile       from '@salesforce/apex/seidor_FileExportService.createExcelFile';

const BUCKETS = [
    { label: '< 1 min',     maxSecs: 60,       color: '#27ae60' },
    { label: '1 – 5 min',   maxSecs: 300,      color: '#82cc5a' },
    { label: '5 – 30 min',  maxSecs: 1800,     color: '#f39c12' },
    { label: '30 – 60 min', maxSecs: 3600,     color: '#e67e22' },
    { label: '> 60 min',    maxSecs: Infinity,  color: '#e74c3c' }
];

export default class ResponseTimeDashboard extends LightningElement {

    // ── Filtros ───────────────────────────────────────────────────────────────
    @track dateFrom      = this._defaultDateFrom();
    @track dateTo        = this._defaultDateTo();
    @track selectedAgent = '';

    // ── Estado de carga ───────────────────────────────────────────────────────
    @track isLoading        = false;

    // ── Datos ─────────────────────────────────────────────────────────────────
    @track agentGroups   = [];
    @track agentOptions  = [];

    // ── Expansión acordeón ────────────────────────────────────────────────────
    @track expandedAgents   = {};   // agentKey → bool; ausente = colapsado
    @track expandedSessions = {};   // sessionId → bool
    @track sessionMessages  = {};   // sessionId → processed message array
    @track loadingSessionId = null;

    // ── Chart.js state ────────────────────────────────────────────────────────
    _chartLibLoaded   = false;
    _rtPieChart       = null;
    _rtPieDataHash    = null;
    _agentBarChart    = null;
    _agentBarHash     = null;

    // ── Computed ──────────────────────────────────────────────────────────────

    get agentFilterOptions() {
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        (this.agentOptions || []).forEach(o => opts.push(o));
        return opts;
    }

    get hasData() {
        return this.agentGroups && this.agentGroups.length > 0;
    }

    get hasNoData() {
        return !this.hasData;
    }

    // Lista plana de todas las sesiones de todos los agentes, newest first
    get allSessions() {
        const sessions = [];
        for (const group of (this.agentGroups || [])) {
            for (const s of (group.sessions || [])) {
                sessions.push({ ...s, agentId: group.agentId, agentName: group.agentName });
            }
        }
        return sessions.sort((a, b) => {
            const ta = a.startTime ? new Date(a.startTime).getTime() : 0;
            const tb = b.startTime ? new Date(b.startTime).getTime() : 0;
            return tb - ta;
        });
    }

    /**
     * Genera el array plano de filas para la tabla acordeón.
     * Tipos de fila: isAgent, isSession, isMessage, isLoading.
     */
    get tableRows() {
        const rows = [];

        const sortedGroups = [...(this.agentGroups || [])].sort((a, b) =>
            (a.agentName || '').localeCompare(b.agentName || '', 'es')
        );

        for (const group of sortedGroups) {
            const agentKey  = group.agentId || '__sin_asignar__';
            const isExpanded = !!this.expandedAgents[agentKey];

            // ── Fila cabecera agente ──────────────────────────────────────────
            rows.push({
                _key:          'header_' + agentKey,
                isAgent:       true,
                isSession:     false,
                isMessage:     false,
                isLoading:     false,
                agentKey,
                agentName:     group.agentName || 'Sin asignar',
                totalSessions: (group.sessions || []).length,
                avgResponse:   this._calcAgentAvg(group.sessions || []),
                isExpanded,
                icon:          isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass:      'agent-group-header'
            });

            if (!isExpanded) continue;

            // Sesiones del agente ordenadas: más reciente primero
            const sorted = [...(group.sessions || [])].sort((a, b) => {
                const ta = a.startTime ? new Date(a.startTime).getTime() : 0;
                const tb = b.startTime ? new Date(b.startTime).getTime() : 0;
                return tb - ta;
            });

            for (const s of sorted) {
                const sessExpanded = !!this.expandedSessions[s.sessionId];
                const msgs         = this.sessionMessages[s.sessionId] || [];
                const avgSecs      = this._avgSeconds(msgs.filter(m => m.responseTimeSecs != null).map(m => m.responseTimeSecs));

                // ── Fila sesión ───────────────────────────────────────────────
                rows.push({
                    _key:             s.sessionId,
                    isAgent:          false,
                    isSession:        true,
                    isMessage:        false,
                    isLoading:        false,
                    sessionId:        s.sessionId,
                    conversationUUID: s.conversationUUID || '',
                    conversationId:   s.conversationId   || '',
                    endUserPhone:     s.endUserPhone || '',
                    endUserName:      s.endUserName  || '',
                    accountName:      s.accountName  || '',
                    startTime:        s.startTime ? new Date(s.startTime).toLocaleString('es-CL') : '—',
                    endTime:          s.endTime   ? new Date(s.endTime).toLocaleString('es-CL')   : '—',
                    duration:         s.durationMinutes != null ? this._formatMins(s.durationMinutes) : '—',
                    avgResponse:      avgSecs != null ? this._formatSecs(avgSecs) : '—',
                    isExpanded:       sessExpanded,
                    icon:             sessExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    rowClass:         'session-row'
                });

                if (!sessExpanded) continue;

                // ── Fila de carga ─────────────────────────────────────────────
                if (this.loadingSessionId === s.sessionId) {
                    rows.push({
                        _key:      s.sessionId + '_loading',
                        isAgent:   false,
                        isSession: false,
                        isMessage: false,
                        isLoading: true,
                        rowClass:  ''
                    });
                    continue;
                }

                // ── Filas de mensaje ──────────────────────────────────────────
                for (const msg of msgs) {
                    const roleCss = this._roleCss(msg.senderRole);
                    rows.push({
                        _key:         s.sessionId + '_msg_' + msg.messageId,
                        isAgent:      false,
                        isSession:    false,
                        isMessage:    true,
                        isLoading:    false,
                        senderRole:   msg.senderRole,
                        senderLabel:  this._roleLabel(msg.senderRole),
                        messageText:  (msg.messageText || '').length > 80
                                          ? msg.messageText.substring(0, 80) + '…'
                                          : (msg.messageText || ''),
                        timestamp:    msg.messageTimestamp
                                          ? new Date(msg.messageTimestamp).toLocaleString('es-CL')
                                          : '—',
                        responseTime: msg.responseFormatted || null,
                        hasResponse:  msg.responseTimeSecs != null,
                        rowClass:     'message-row ' + roleCss
                    });
                }
            }
        }

        return rows;
    }

    /**
     * Datos del gráfico de torta agregando todos los responseTimeSecs
     * de todas las sesiones cargadas en sessionMessages.
     */
    get pieData() {
        // Recolectar todos los tiempos de respuesta cargados
        const allSecs = [];
        for (const msgs of Object.values(this.sessionMessages)) {
            for (const m of (msgs || [])) {
                if (m.responseTimeSecs != null) allSecs.push(m.responseTimeSecs);
            }
        }
        if (!allSecs.length) return null;

        const total = allSecs.length;

        // Contar por bucket
        const counts = BUCKETS.map(() => 0);
        for (const secs of allSecs) {
            for (let i = 0; i < BUCKETS.length; i++) {
                if (secs < BUCKETS[i].maxSecs) {
                    counts[i]++;
                    break;
                }
            }
        }

        const segments = BUCKETS.map((b, i) => ({
            label:    b.label,
            count:    counts[i],
            pct:      Math.round(counts[i] / total * 100),
            color:    b.color,
            dotStyle: `background:${b.color};width:12px;height:12px;border-radius:50%;display:inline-block;flex-shrink:0;`
        })).filter(s => s.count > 0);

        // Ajuste para que los porcentajes sumen exactamente 100
        const sum = segments.reduce((acc, s) => acc + s.pct, 0);
        if (segments.length && sum !== 100) segments[0].pct += (100 - sum);

        return { total, segments };
    }

    get hasPieData() {
        return !!this.pieData;
    }

    get hasNoPieData() {
        return !this.hasPieData;
    }

    get agentBarData() {
        const results = [];
        for (const group of (this.agentGroups || [])) {
            const allSecs = [];
            for (const s of (group.sessions || [])) {
                const msgs = this.sessionMessages[s.sessionId] || [];
                for (const m of msgs) {
                    if (m.responseTimeSecs != null) allSecs.push(m.responseTimeSecs);
                }
            }
            if (!allSecs.length) continue;
            const avg = this._avgSeconds(allSecs);
            results.push({ name: group.agentName || 'Sin asignar', avgSecs: avg });
        }
        return results.sort((a, b) => a.avgSecs - b.avgSecs);
    }

    get hasAgentBarData() { return this.agentBarData.length > 0; }

    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._maybeRenderRtPie();
            })
            .catch(err => console.error('Chart.js load error', err));
        this._loadSessions();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderRtPie();
        this._maybeRenderAgentBar();
    }

    // ── Handlers — Filtros ────────────────────────────────────────────────────

    handleDateFromChange(e)  { this.dateFrom      = e.detail.value; }
    handleDateToChange(e)    { this.dateTo         = e.detail.value; }
    handleAgentChange(e)     { this.selectedAgent  = e.detail.value; }

    handleSearch() {
        this._loadSessions();
    }

    handleExportResponseTime() {
        const sessions = this.allSessions;

        const cols = [
            { label: 'Ejecutivo',          fieldName: 'agentName'   },
            { label: 'Nombre Cliente',     fieldName: 'endUserName' },
            { label: 'Cuenta',             fieldName: 'accountName' },
            { label: 'Teléfono',           fieldName: 'endUserPhone'},
            { label: 'Inicio',             fieldName: 'startTime'   },
            { label: 'Fin',                fieldName: 'endTime'     },
            { label: 'Duración',           fieldName: 'duration'    },
            { label: 'T. Prom. Respuesta', fieldName: 'avgResponse' }
        ];
        const rows = sessions.map(s => ({
            agentName:    s.agentName    || 'Sin asignar',
            endUserName:  s.endUserName  || '',
            accountName:  s.accountName  || '',
            endUserPhone: s.endUserPhone || '',
            startTime:    s.startTime ? new Date(s.startTime).toLocaleString('es-CL') : '',
            endTime:      s.endTime   ? new Date(s.endTime).toLocaleString('es-CL')   : '',
            duration:     s.durationMinutes != null ? this._formatMins(s.durationMinutes) : '—',
            avgResponse:  this._getSessionAvgResponse(s.sessionId)
        }));
        this._exportToExcel(rows, cols, 'tiempos_respuesta');
    }

    // ── Handlers — Acordeón agente ────────────────────────────────────────────

    handleToggleAgent(event) {
        const agentKey = event.currentTarget.dataset.agentKey;
        this.expandedAgents = {
            ...this.expandedAgents,
            [agentKey]: !this.expandedAgents[agentKey]
        };
    }

    // ── Handlers — Acordeón sesión ────────────────────────────────────────────

    handleToggleSession(event) {
        const sessionId       = event.currentTarget.dataset.sessionId;
        const conversationUUID = event.currentTarget.dataset.conversationUuid;
        const conversationId   = event.currentTarget.dataset.conversationId;
        const wasExpanded      = !!this.expandedSessions[sessionId];

        this.expandedSessions = {
            ...this.expandedSessions,
            [sessionId]: !wasExpanded
        };

        if (!wasExpanded && !this.sessionMessages[sessionId]) {
            this._loadMessages(sessionId, conversationUUID, conversationId);
        }
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    _loadSessions() {
        this.isLoading        = true;
        this.agentGroups      = [];
        this.agentOptions     = [];
        this.expandedAgents   = {};
        this.expandedSessions = {};
        this.sessionMessages  = {};
        this.loadingSessionId = null;

        getAgentSessions({
            dateFrom:      this.dateFrom,
            dateTo:        this.dateTo,
            agentId:       this.selectedAgent || null,
            limitSessions: 3000
        })
        .then(result => {
            this.agentGroups  = result.agentGroups  || [];
            this.agentOptions = result.agentOptions || [];
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando sesiones', 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    _loadMessages(sessionId, conversationUUID, conversationId) {
        if (!conversationUUID) {
            this._toast('Advertencia', 'Esta sesión no tiene UUID de conversación', 'warning');
            return;
        }

        this.loadingSessionId = sessionId;

        getMessagesByUUID({
            conversationUUID,
            conversationSfId: conversationId,
            sessionId
        })
        .then(entries => {
            this.sessionMessages = {
                ...this.sessionMessages,
                [sessionId]: this._processMessages(entries)
            };
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando mensajes', 'error');
            this.expandedSessions = { ...this.expandedSessions, [sessionId]: false };
        })
        .finally(() => { this.loadingSessionId = null; });
    }

    // ── Message Processing ────────────────────────────────────────────────────

    /**
     * Filtra, ordena y enriquece mensajes con delta de tiempo entre mensajes consecutivos.
     */
    _processMessages(entries) {
        const filtered = (entries || []).filter(e => e.messageText);

        filtered.sort((a, b) => {
            const ta = a.messageTimestamp ? new Date(a.messageTimestamp).getTime() : 0;
            const tb = b.messageTimestamp ? new Date(b.messageTimestamp).getTime() : 0;
            return ta - tb;
        });

        return filtered.map((e, idx) => {
            let responseTimeSecs  = null;
            let responseFormatted = null;

            if (idx > 0 && e.messageTimestamp && filtered[idx - 1].messageTimestamp) {
                const prev = new Date(filtered[idx - 1].messageTimestamp).getTime();
                const curr = new Date(e.messageTimestamp).getTime();
                responseTimeSecs  = Math.max(0, Math.round((curr - prev) / 1000));
                responseFormatted = this._formatSecs(responseTimeSecs);
            }

            return {
                ...e,
                responseTimeSecs,
                responseFormatted
            };
        });
    }

    // ── Helpers de cálculo ────────────────────────────────────────────────────

    /**
     * Calcula el promedio de responseTimeSecs de todas las sesiones cargadas
     * de este agente y devuelve una cadena formateada o '—'.
     */
    _calcAgentAvg(sessions) {
        const allSecs = [];
        for (const s of sessions) {
            const msgs = this.sessionMessages[s.sessionId] || [];
            for (const m of msgs) {
                if (m.responseTimeSecs != null) allSecs.push(m.responseTimeSecs);
            }
        }
        const avg = this._avgSeconds(allSecs);
        return avg != null ? this._formatSecs(avg) : '—';
    }

    /**
     * Calcula la media de un array de números. Devuelve null si el array está vacío.
     */
    _avgSeconds(arr) {
        if (!arr || !arr.length) return null;
        return Math.round(arr.reduce((a, b) => a + b, 0) / arr.length);
    }

    /**
     * Formatea segundos a cadena legible: "30s", "2m 15s", "1h 30m".
     */
    _formatSecs(secs) {
        if (secs == null || secs < 0) return '—';
        const s = Math.round(secs);
        if (s < 60)   return `${s}s`;
        const m = Math.floor(s / 60);
        const r = s % 60;
        if (m < 60)   return r > 0 ? `${m}m ${r}s` : `${m}m`;
        const h = Math.floor(m / 60);
        const rm = m % 60;
        return rm > 0 ? `${h}h ${rm}m` : `${h}h`;
    }

    /**
     * Formatea minutos a cadena legible (misma lógica que _formatSecs pero entrada en minutos).
     */
    _formatMins(mins) {
        if (mins == null || mins < 0) return '—';
        const m = Math.round(Number(mins));
        if (m < 60) return `${m}m`;
        const h  = Math.floor(m / 60);
        const rm = m % 60;
        return rm > 0 ? `${h}h ${rm}m` : `${h}h`;
    }

    /**
     * Etiqueta legible para el rol del remitente.
     */
    _roleLabel(role) {
        if (role === 'EndUser')  return 'Cliente';
        if (role === 'Agent')    return 'Ejecutivo';
        if (role === 'Chatbot')  return 'Bot';
        return 'Sistema';
    }

    /**
     * Clase CSS para el rol del remitente (aplicada a la fila de mensaje).
     */
    _roleCss(role) {
        if (role === 'EndUser')  return 'msg-user';
        if (role === 'Agent')    return 'msg-agent';
        if (role === 'Chatbot')  return 'msg-bot';
        return 'msg-system';
    }

    _getSessionAvgResponse(sessionId) {
        const msgs = this.sessionMessages[sessionId] || [];
        const secs = msgs.filter(m => m.responseTimeSecs != null).map(m => m.responseTimeSecs);
        const avg  = this._avgSeconds(secs);
        return avg != null ? this._formatSecs(avg) : '—';
    }

    _exportToExcel(rows, columns, filename) {
        const esc = v => String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        const fmt = val => {
            if (val == null || val === '') return '';
            if (typeof val === 'boolean') return val ? 'Sí' : 'No';
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

    _maybeRenderAgentBar() {
        const canvas = this.template.querySelector('canvas.agent-bar-chart');
        if (!canvas) return;
        const data = this.agentBarData;
        if (!data.length) return;
        const hash = data.map(d => `${d.name}:${d.avgSecs}`).join('|');
        if (this._agentBarHash === hash && this._agentBarChart) return;
        this._agentBarHash = hash;
        if (this._agentBarChart) { this._agentBarChart.destroy(); this._agentBarChart = null; }
        const self = this;
        this._agentBarChart = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: data.map(d => d.name),
                datasets: [{
                    label: 'T. Respuesta Prom.',
                    data:  data.map(d => d.avgSecs),
                    backgroundColor: data.map(d => {
                        if (d.avgSecs < 60)   return '#27ae60';
                        if (d.avgSecs < 300)  return '#82cc5a';
                        if (d.avgSecs < 1800) return '#f39c12';
                        if (d.avgSecs < 3600) return '#e67e22';
                        return '#e74c3c';
                    }),
                    borderRadius: 4
                }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: { callbacks: { label: ctx => ` ${self._formatSecs(ctx.parsed.x)}` } }
                },
                scales: {
                    x: { ticks: { callback: v => self._formatSecs(v) }, grid: { color: 'rgba(0,0,0,0.05)' } },
                    y: { ticks: { font: { size: 11 } } }
                }
            }
        });
    }

    _maybeRenderRtPie() {
        const canvas = this.template.querySelector('canvas.rt-pie-chart');
        if (!canvas) return;

        const pie = this.pieData;
        if (!pie) return;

        const hash = pie.segments.map(s => `${s.label}:${s.count}`).join('|');
        if (this._rtPieDataHash === hash && this._rtPieChart) return;
        this._rtPieDataHash = hash;

        if (this._rtPieChart) { this._rtPieChart.destroy(); this._rtPieChart = null; }

        this._rtPieChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: pie.segments.map(s => s.label),
                datasets: [{
                    data:             pie.segments.map(s => s.count),
                    backgroundColor:  pie.segments.map(s => s.color),
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
                                const seg = pie.segments[ctx.dataIndex];
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
        d.setDate(d.getDate() - 7);
        return d.toISOString().split('T')[0];
    }

    _defaultDateTo() {
        return new Date().toISOString().split('T')[0];
    }
}