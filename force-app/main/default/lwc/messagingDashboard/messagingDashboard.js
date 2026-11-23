import { LightningElement, track } from 'lwc';
import { loadScript }   from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CHART_JS         from '@salesforce/resourceUrl/chartJs';
import getSessionsDashboard   from '@salesforce/apex/seidor_MessagingDashboardService.getSessionsDashboard';
import getAgentPresenceStatus from '@salesforce/apex/seidor_MessagingDashboardService.getAgentPresenceStatus';
import getBitacoraEntries     from '@salesforce/apex/seidor_MessagingDashboardService.getBitacoraEntries';
import getMessagesByUUID      from '@salesforce/apex/seidor_ConversationDataService.getMessagesByUUID';
import getPresenceHistory     from '@salesforce/apex/seidor_MessagingDashboardService.getPresenceHistory';
import createExcelFile        from '@salesforce/apex/seidor_FileExportService.createExcelFile';
import getSurveyData          from '@salesforce/apex/seidor_EncuestaQueryService.getSurveyData';
import getHourlySessionCount  from '@salesforce/apex/seidor_MessagingDashboardService.getHourlySessionCount';
import getHourlyDateSessionCount from '@salesforce/apex/seidor_MessagingDashboardService.getHourlyDateSessionCount';

export default class MessagingDashboard extends LightningElement {

    // ── Filtros globales ──────────────────────────────────────────────────────
    @track dateFrom      = this._defaultDateFrom();
    @track dateTo        = this._defaultDateTo();
    @track selectedAgent = '';
    @track statusFilter  = '';

    // ── Estado de carga ───────────────────────────────────────────────────────
    @track isLoading         = false;
    @track isSurveyLoading   = false;
    @track isPresenceLoading = false;
    @track isBitacoraLoading = false;

    // ── Datos ─────────────────────────────────────────────────────────────────
    @track dashboardData = {
        sessions: [], agentOptions: [],
        totalSessions: 0,
        activeSessions: 0, endedSessions: 0, newSessions: 0,
        outOfHoursSessions: 0
    };
    @track presenceData  = [];
    @track bitacoraData  = [];
    @track surveyMetrics = null;

    // ── Expansión de filas inline ─────────────────────────────────────────────
    @track expandedSessions = {};   // sessionId → true/false
    @track sessionMessages  = {};   // sessionId → MessageWrapper[]
    @track loadingSessionId = null;
    @track expandedAgents   = {};   // agentKey  → true (expandido); ausente = colapsado por defecto
    @track currentPage      = 1;

    static PAGE_SIZE = 25;

    // ── Comparativo por ejecutivo ─────────────────────────────────────────────
    @track comparisonSortedBy        = 'total';
    @track comparisonSortedDirection = 'desc';

    // ── Historial de presencia ────────────────────────────────────────────────
    @track presenceHistoryData          = [];
    @track presenceHistoryDateFrom      = this._defaultDateFrom();
    @track presenceHistoryDateTo        = this._defaultDateTo();
    @track presenceHistoryAgent         = '';
    @track isPresenceHistoryLoading     = false;
    @track presenceHistoryPage          = 1;

    static PH_PAGE_SIZE = 20;

    // ── Flags de carga lazy ───────────────────────────────────────────────────
    @track surveyLoaded   = false;
    @track bitacoraLoaded = false;
    @track surveyRows     = [];

    // ── Datos de sesiones por hora ────────────────────────────────────────────
    @track hourlyData = [];
    @track hourlyDateData = [];
    @track hourlyFilterDate = this._defaultDateTo();
    @track comparePreviousDay = false;
    @track hourlyPreviousData = [];
    @track hourlyChartLoading = false;

    // ── Chart.js state ────────────────────────────────────────────────────────
    _chartLibLoaded      = false;
    _agentChart          = null;
    _agentHash           = null;
    _trendChart          = null;
    _trendHash           = null;
    _completenessChart   = null;
    _completenessHash    = null;
    _hourlyChart         = null;
    _hourlyHash          = null;
    _hourlyDateRendered  = false;

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasSessions() {
        return this.dashboardData.sessions && this.dashboardData.sessions.length > 0;
    }

    get agentLoadData() {
        const sessions = this.dashboardData.sessions || [];
        if (!sessions.length) return null;
        const sessionMap = {};
        sessions.forEach(s => {
            const key = s.agentName || 'Sin asignar';
            sessionMap[key] = (sessionMap[key] || 0) + 1;
        });
        const surveyMap = {};
        (this.surveyRows || []).forEach(r => {
            const key = r.agentName || 'Sin asignar';
            surveyMap[key] = (surveyMap[key] || 0) + 1;
        });
        const agents = Object.keys(sessionMap).sort((a, b) => sessionMap[b] - sessionMap[a]);
        return {
            labels:   agents,
            sessions: agents.map(a => sessionMap[a] || 0),
            surveys:  agents.map(a => surveyMap[a]  || 0)
        };
    }

    // Agrupa las sesiones (ya filtradas por fecha/agente/estado en el servidor)
    // por ejecutivo, contando cada status real.
    // "Otros estados" captura cualquier valor de Status distinto de
    // Ended/Active/New, para no perder datos si aparece un estado nuevo.
    _buildAgentComparisonRows() {
        const sessions = this.dashboardData.sessions || [];
        const map = {};

        sessions.forEach(s => {
            const key  = s.agentId || '__sin_asignar__';
            const name = s.agentName || 'Sin asignar';
            if (!map[key]) {
                map[key] = {
                    agentId: key, agentName: name,
                    total: 0, ended: 0, active: 0, nueva: 0, otros: 0
                };
            }
            const ag = map[key];
            ag.total++;
            if      (s.status === 'Ended')  ag.ended++;
            else if (s.status === 'Active') ag.active++;
            else if (s.status === 'New')    ag.nueva++;
            else                            ag.otros++;
        });

        return Object.values(map).map(ag => ({
            ...ag,
            endedPct: ag.total ? Math.round(ag.ended / ag.total * 100) : 0
        }));
    }

    get hasAgentComparison() {
        return this._buildAgentComparisonRows().length > 0;
    }

    // Al menos un ejecutivo tiene sesiones en un status distinto de
    // Ended/Active/New — solo entonces se muestra la columna "Otros estados"
    // para no ensuciar la tabla con una columna siempre en cero.
    get hasOtherStatuses() {
        return this._buildAgentComparisonRows().some(r => r.otros > 0);
    }

    get agentComparisonRows() {
        const rows  = this._buildAgentComparisonRows();
        const field = this.comparisonSortedBy;
        const dir   = this.comparisonSortedDirection === 'asc' ? 1 : -1;
        return [...rows].sort((a, b) => {
            const va = a[field];
            const vb = b[field];
            if (typeof va === 'string') return dir * va.localeCompare(vb, 'es');
            return dir * ((va ?? 0) - (vb ?? 0));
        });
    }

    get agentComparisonColumns() {
        const cols = [
            { label: 'Ejecutivo',      fieldName: 'agentName', type: 'text',   sortable: true },
            { label: 'Total Sesiones', fieldName: 'total',     type: 'number', sortable: true, cellAttributes: { alignment: 'center' } },
            { label: 'Atendidas',      fieldName: 'ended',     type: 'number', sortable: true, cellAttributes: { alignment: 'center' } },
            { label: '% Atendidas',    fieldName: 'endedPct',  type: 'number', sortable: true, cellAttributes: { alignment: 'center' } },
            { label: 'Activas',        fieldName: 'active',    type: 'number', sortable: true, cellAttributes: { alignment: 'center' } },
            { label: 'En cola',        fieldName: 'nueva',     type: 'number', sortable: true, cellAttributes: { alignment: 'center' } }
        ];
        if (this.hasOtherStatuses) {
            cols.push({ label: 'Otros estados', fieldName: 'otros', type: 'number', sortable: true, cellAttributes: { alignment: 'center' } });
        }
        return cols;
    }

    handleComparisonSort(event) {
        this.comparisonSortedBy        = event.detail.fieldName;
        this.comparisonSortedDirection = event.detail.sortDirection;
    }

    get dailyTrendData() {
        const sessions = this.dashboardData.sessions || [];
        if (!sessions.length) return null;
        const dayMap = {};   // sesiones dentro de horario laboral
        const oohMap = {};   // sesiones fuera de horario laboral (SessionRow.isOutOfHours)
        const srvMap = {};
        sessions.forEach(s => {
            if (!s.startTime) return;
            const day = s.startTime.split('T')[0];
            if (s.isOutOfHours) {
                oohMap[day] = (oohMap[day] || 0) + 1;
            } else {
                dayMap[day] = (dayMap[day] || 0) + 1;
            }
        });
        (this.surveyRows || []).forEach(r => {
            if (!r.sessionEndTime) return;
            const day = r.sessionEndTime.split('T')[0];
            srvMap[day] = (srvMap[day] || 0) + 1;
        });
        // Unión de claves: un día puede tener solo sesiones fuera de horario
        const keys = [...new Set([...Object.keys(dayMap), ...Object.keys(oohMap)])].sort();
        return {
            labels:     keys.map(k => { const [,mm,dd] = k.split('-'); return `${dd}/${mm}`; }),
            inHours:    keys.map(k => dayMap[k] || 0),
            outOfHours: keys.map(k => oohMap[k] || 0),
            surveys:    keys.map(k => srvMap[k] || 0)
        };
    }
    get hasSessionCharts() { return !!(this.dashboardData.sessions && this.dashboardData.sessions.length > 0); }

    get hasHourlyData() {
        return this.hourlyData && this.hourlyData.length > 0 && this.hourlyData.some(h => h.count > 0);
    }

    get hourlyDayTotal() {
        if (!this.hourlyData || !this.hourlyData.length) return 0;
        return this.hourlyData.reduce((sum, h) => sum + (h.count || 0), 0);
    }

    get hourlyDayLabel() {
        if (!this.hourlyFilterDate) return '';
        const [, mm, dd] = this.hourlyFilterDate.split('-');
        return `${dd}/${mm}`;
    }

    get hourlyChartData() {
        if (!this.hourlyData || !this.hourlyData.length) return null;
        return {
            labels: this.hourlyData.map(h => {
                const hh = String(h.hour).padStart(2, '0');
                return `${hh}:00`;
            }),
            values: this.hourlyData.map(h => h.count)
        };
    }

    get topHoursSummary() {
        if (!this.hourlyData || !this.hourlyData.length) return [];
        return [...this.hourlyData]
            .filter(h => h.count > 0)
            .sort((a, b) => b.count - a.count)
            .slice(0, 5)
            .map(h => ({
                hour: String(h.hour).padStart(2, '0') + ':00',
                count: h.count
            }));
    }

    get hasTopHours() {
        return this.topHoursSummary.length > 0;
    }

    // Sesiones fuera de horario del día seleccionado, con la MISMA lógica que
    // el gráfico "Volumen Diario de Sesiones" (dailyTrendData): agrega en
    // cliente las sesiones con isOutOfHours=true cuyo día de startTime coincide
    // con hourlyFilterDate. Al ser un getter sobre estado @track, se actualiza
    // automáticamente al cambiar de día sin callout adicional.
    get outOfHoursDayCount() {
        const day = this.hourlyFilterDate;
        if (!day) return 0;
        return (this.dashboardData.sessions || []).filter(s =>
            s.isOutOfHours && s.startTime && s.startTime.split('T')[0] === day
        ).length;
    }

    // Porcentaje de sesiones del día que ingresaron fuera de horario
    // (outOfHoursDayCount / total de sesiones del día), acotado a 100% máximo.
    get outOfHoursDayRate() {
        const total = this.hourlyDayTotal || 0;
        const ooh   = this.outOfHoursDayCount || 0;
        if (!total) return '—';
        return Math.min(100, Math.round(ooh / total * 100)) + '%';
    }

    get hourlyPreviousDayTotal() {
        if (!this.hourlyPreviousData || !this.hourlyPreviousData.length) return 0;
        return this.hourlyPreviousData.reduce((sum, h) => sum + (h.count || 0), 0);
    }

    get hourlyPreviousDayLabel() {
        if (!this.hourlyFilterDate) return '';
        const prev = new Date(this.hourlyFilterDate);
        prev.setDate(prev.getDate() - 1);
        const mm = String(prev.getMonth() + 1).padStart(2, '0');
        const dd = String(prev.getDate()).padStart(2, '0');
        return `${dd}/${mm}`;
    }

    get hasDailyHourlyData() {
        return this.hourlyDateData && this.hourlyDateData.length > 0;
    }

    get dailyHourlyBreakdown() {
        if (!this.hourlyDateData || !this.hourlyDateData.length) return [];
        const grouped = {};
        this.hourlyDateData.forEach(item => {
            if (!grouped[item.dateStr]) grouped[item.dateStr] = [];
            grouped[item.dateStr].push({
                hour: String(item.hour).padStart(2, '0') + ':00',
                count: item.count
            });
        });
        return Object.entries(grouped)
            .sort((a, b) => b[0].localeCompare(a[0]))
            .map(([dateStr, hours]) => ({
                dateStr,
                hours,
                total: hours.reduce((sum, h) => sum + h.count, 0)
            }));
    }

    get agentOptions() {
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        (this.dashboardData.agentOptions || []).forEach(o => opts.push(o));
        return opts;
    }

    get statusOptions() {
        return [
            { label: 'Todos los estados', value: '' },
            { label: 'Finalizadas',        value: 'Ended' },
            { label: 'Activas',            value: 'Active' },
            { label: 'En cola',            value: 'New' }
        ];
    }

    get paginatedSessions() {
        const all   = this.dashboardData.sessions || [];
        const start = (this.currentPage - 1) * MessagingDashboard.PAGE_SIZE;
        return all.slice(start, start + MessagingDashboard.PAGE_SIZE);
    }

    get totalPages() {
        return Math.max(1, Math.ceil((this.dashboardData.sessions || []).length / MessagingDashboard.PAGE_SIZE));
    }

    get pageInfo()     { return `Página ${this.currentPage} de ${this.totalPages}`; }
    get hasPrevPage()  { return this.currentPage > 1; }
    get hasNextPage()  { return this.currentPage < this.totalPages; }
    get prevDisabled() { return !this.hasPrevPage; }
    get nextDisabled() { return !this.hasNextPage; }

    get completionRate() {
        const ended = this.dashboardData.endedSessions || 0;
        if (!ended || !this.surveyRows) return '—';
        return Math.round(this.surveyRows.length / ended * 100) + '%';
    }
    get completionRateDetail() {
        return `${(this.surveyRows || []).length} / ${this.dashboardData.endedSessions || 0}`;
    }

    get outOfHoursRate() {
        const total = this.dashboardData.totalSessions || 0;
        const ooh   = this.dashboardData.outOfHoursSessions || 0;
        if (!total) return '—';
        return Math.round(ooh / total * 100) + '%';
    }

    get presenceKpis() {
        const data = this.presenceData || [];
        return {
            available: data.filter(r =>  r.isOnline && (r.activeSessions || 0) <= 5).length,
            busy:      data.filter(r =>  r.isOnline && (r.activeSessions || 0) >  5).length,
            offline:   data.filter(r => !r.isOnline).length
        };
    }

    // Opciones de agente para el filtro del historial (derivadas del data cargado)
    get presenceHistoryAgentOptions() {
        const map = {};
        (this.presenceHistoryData || []).forEach(r => {
            if (r.userId && !map[r.userId]) map[r.userId] = r.userName;
        });
        const opts = [{ label: 'Todos los ejecutivos', value: '' }];
        Object.entries(map)
            .sort((a, b) => (a[1] || '').localeCompare(b[1] || '', 'es'))
            .forEach(([v, l]) => opts.push({ label: l, value: v }));
        return opts;
    }

    // Filtrado por agente + orden de más reciente a más antiguo
    get filteredPresenceHistory() {
        let data = this.presenceHistoryAgent
            ? (this.presenceHistoryData || []).filter(r => r.userId === this.presenceHistoryAgent)
            : (this.presenceHistoryData || []);
        return [...data].sort((a, b) => {
            const ta = a.desde ? new Date(a.desde).getTime() : 0;
            const tb = b.desde ? new Date(b.desde).getTime() : 0;
            return tb - ta;
        });
    }

    // Paginación del historial (20 filas por página)
    get paginatedPresenceHistory() {
        const start = (this.presenceHistoryPage - 1) * MessagingDashboard.PH_PAGE_SIZE;
        return this.filteredPresenceHistory.slice(start, start + MessagingDashboard.PH_PAGE_SIZE);
    }
    get phTotalPages()   { return Math.max(1, Math.ceil(this.filteredPresenceHistory.length / MessagingDashboard.PH_PAGE_SIZE)); }
    get phPageInfo()     { return `Página ${this.presenceHistoryPage} de ${this.phTotalPages}`; }
    get phPrevDisabled() { return this.presenceHistoryPage <= 1; }
    get phNextDisabled() { return this.presenceHistoryPage >= this.phTotalPages; }

    get presenceHistoryColumns() {
        return [
            { label: 'Ejecutivo', fieldName: 'userName',           type: 'text' },
            { label: 'Desde',     fieldName: 'desde',               type: 'date',
              typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
            { label: 'Hasta',     fieldName: 'hasta',               type: 'date',
              typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
            { label: 'Duración',  fieldName: 'durationFormatted',   type: 'text' }
        ];
    }

    // Filas aplanadas: una fila de sesión + una fila expandida opcional por sesión.
    // Este patrón permite múltiples <tr> por iteración en la tabla custom.
    get sessionRows() {
        const rows = [];

        // Agrupa la página actual de sesiones por agente
        const agentMap = new Map();
        for (const s of this.paginatedSessions) {
            const key  = s.agentId || '__sin_asignar__';
            const name = s.agentName || 'Sin asignar';
            if (!agentMap.has(key)) agentMap.set(key, { agentName: name, sessions: [] });
            agentMap.get(key).sessions.push(s);
        }

        // Ordena grupos alfabéticamente por nombre de ejecutivo
        const sortedGroups = [...agentMap.entries()].sort((a, b) =>
            a[1].agentName.localeCompare(b[1].agentName, 'es')
        );

        for (const [agentKey, group] of sortedGroups) {

            // Fila cabecera acordeón — colapsada por defecto (expandedAgents ausente = colapsado)
            const isExpanded = !!this.expandedAgents[agentKey];
            rows.push({
                _key:            'header_' + agentKey,
                isGroupHeader:   true,
                isSession:       false,
                isExpandedRow:   false,
                agentName:       group.agentName,
                sessionCount:    group.sessions.length,
                agentKey:        agentKey,
                groupToggleIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                rowClass:        'agent-group-header'
            });

            if (!isExpanded) continue;

            // Sesiones del agente ordenadas cronológicamente (más reciente primero)
            const sorted = [...group.sessions].sort((a, b) => {
                const ta = a.startTime ? new Date(a.startTime).getTime() : 0;
                const tb = b.startTime ? new Date(b.startTime).getTime() : 0;
                return tb - ta;
            });

            for (const s of sorted) {
                const isExpanded = !!this.expandedSessions[s.sessionId];
                rows.push({
                    _key:             s.sessionId,
                    isGroupHeader:    false,
                    isSession:        true,
                    isExpandedRow:    false,
                    sessionId:        s.sessionId,
                    conversationId:   s.conversationId,
                    conversationUUID: s.conversationUUID,
                    startTime:        s.startTime ? new Date(s.startTime).toLocaleString('es-CL') : '—',
                    endTime:          s.endTime   ? new Date(s.endTime).toLocaleString('es-CL')   : '—',
                    status:           s.status,
                    agentName:        s.agentName,
                    endUserPhone:     s.endUserPhone || '—',
                    durationMinutes:  s.durationMinutes != null ? s.durationMinutes + ' min' : '—',
                    rowClass:         'slds-hint-parent',
                    toggleIcon:       isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    isExpanded
                });

                if (isExpanded) {
                    const msgs = this.sessionMessages[s.sessionId] || [];
                    rows.push({
                        _key:              s.sessionId + '_expanded',
                        isGroupHeader:     false,
                        isSession:         false,
                        isExpandedRow:     true,
                        parentSessionId:   s.sessionId,
                        messages:          msgs,
                        hasMessages:       msgs.length > 0,
                        isLoadingMessages: this.loadingSessionId === s.sessionId,
                        rowClass:          'expanded-messages-row'
                    });
                }
            }
        }

        return rows;
    }

    // ── Columnas de otras tabs ────────────────────────────────────────────────

    get surveyColumns() {
        return [
            { label: 'Ejecutivo',     fieldName: 'agentName',   type: 'text' },
            { label: 'Cliente',       fieldName: 'accountName', type: 'text' },
            { label: 'Cuenta',        fieldName: 'accountName', type: 'text' },
            { label: 'Contacto',      fieldName: 'clientName',  type: 'text' },
            { label: 'Teléfono',      fieldName: 'endUserPhone',type: 'text' },
            { label: 'FCR',           fieldName: 'fcrAnswer',   type: 'text' },
            { label: 'CSAT',         fieldName: 'csatAnswer',  type: 'text' },
            { label: 'Puntaje CSAT', fieldName: 'csatScore',   type: 'number' },
            { label: 'Inicio',       fieldName: 'startTime',   type: 'date',
              typeAttributes: { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' }}
        ];
    }

    get presenceColumns() {
        return [
            { label: 'Ejecutivo',        fieldName: 'userName',        type: 'text' },
            { label: 'Estado',           fieldName: 'presenceStatus',  type: 'text' },
            { label: 'Categoría',        fieldName: 'statusCategory',  type: 'text' },
            { label: 'Sesiones activas', fieldName: 'activeSessions',  type: 'number' },
            { label: 'Desde',            fieldName: 'lastStatusChange', type: 'date',
              typeAttributes: { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' }}
        ];
    }

    get bitacoraColumns() {
        return [
            { label: 'Ejecutivo',     fieldName: 'agentName',      type: 'text' },
            { label: 'Estado',        fieldName: 'workStatus',     type: 'text' },
            { label: 'Asignado',      fieldName: 'assignedTime',   type: 'date',
              typeAttributes: { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' }},
            { label: 'Cerrado',       fieldName: 'closedTime',     type: 'date',
              typeAttributes: { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' }},
            { label: 'Duración (min)', fieldName: 'handlingMinutes', type: 'number' },
            { label: 'Nombre Cliente', fieldName: 'endUserName',    type: 'text' },
            { label: 'Cuenta',         fieldName: 'accountName',    type: 'text' },
            { label: 'Teléfono',       fieldName: 'endUserPhone',   type: 'text' },
            { label: 'Estado sesión',  fieldName: 'sessionStatus',  type: 'text' }
        ];
    }

    @track _showHelp  = false;
    handleToggleHelp() { this._showHelp = !this._showHelp; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._maybeRenderAgentLoad();
                this._maybeRenderDailyTrend();
                this._maybeRenderCompleteness();
                this._maybeRenderHourlyChart();
            })
            .catch(err => console.error('Chart.js load error', err));
        this._loadDashboard();
    }

    renderedCallback() {
        if (!this._chartLibLoaded) return;
        this._maybeRenderAgentLoad();
        this._maybeRenderDailyTrend();
        this._maybeRenderCompleteness();
        this._maybeRenderHourlyChart();
    }

    // ── Handlers — Filtros ────────────────────────────────────────────────────

    handleDateFromChange(e)  { this.dateFrom      = e.detail.value; }
    handleDateToChange(e)    { this.dateTo        = e.detail.value; }
    handleAgentChange(e)     { this.selectedAgent = e.detail.value; }
    handleStatusChange(e)    { this.statusFilter  = e.detail.value; }

    handleHourlyFilterDateChange(e) {
        this.hourlyFilterDate = e.detail.value;
        this._loadHourlyChart();
    }

    handleComparePreviousDayChange(e) {
        const selected = e.detail.value;
        this.comparePreviousDay = selected && selected.includes('compare');
        this._loadHourlyChart();
    }

    get _comparePreviousDayOption() {
        return [{ label: 'Comparar con día anterior', value: 'compare' }];
    }

    get _comparePreviousDayValue() {
        return this.comparePreviousDay ? ['compare'] : [];
    }

    handleSearch() {
        this._loadDashboard();
        this.surveyLoaded     = false;
        this.bitacoraLoaded   = false;
        this.surveyMetrics    = null;
        this.bitacoraData     = [];
        this.expandedSessions = {};
        this.sessionMessages  = {};
        this.expandedAgents   = {};
        this.currentPage      = 1;
        this.comparePreviousDay = false;
        this.hourlyPreviousData = [];
        if (this._agentChart)       { this._agentChart.destroy();       this._agentChart = null; }
        this._agentHash        = null;
        if (this._completenessChart) { this._completenessChart.destroy(); this._completenessChart = null; }
        this._completenessHash = null;
        if (this._hourlyChart)       { this._hourlyChart.destroy();       this._hourlyChart = null; }
        this._hourlyHash        = null;
        this.hourlyDateData     = [];
        this.hourlyFilterDate   = this._defaultDateTo();
    }

    handleClearFilters() {
        this.dateFrom      = this._defaultDateFrom();
        this.dateTo        = this._defaultDateTo();
        this.selectedAgent = '';
        this.statusFilter  = '';
        this.hourlyFilterDate = this._defaultDateTo();
        this.comparePreviousDay = false;
        this.hourlyPreviousData = [];
        this.handleSearch();
    }

    handleTabSelect() {}

    // ── Handlers — Tab Atención (toggle inline) ───────────────────────────────

    handleToggleGroup(event) {
        const agentKey = event.currentTarget.dataset.agentKey;
        this.expandedAgents = { ...this.expandedAgents, [agentKey]: !this.expandedAgents[agentKey] };
    }

    handlePrevPage() { if (this.hasPrevPage) { this.currentPage--; this.expandedAgents = {}; } }
    handleNextPage() { if (this.hasNextPage) { this.currentPage++; this.expandedAgents = {}; } }

    handleToggleRow(event) {
        const sessionId   = event.currentTarget.dataset.sessionId;
        const wasExpanded = !!this.expandedSessions[sessionId];
        this.expandedSessions = { ...this.expandedSessions, [sessionId]: !wasExpanded };
        if (!wasExpanded && !this.sessionMessages[sessionId]) {
            this._loadSessionMessages(sessionId);
        }
    }

    // ── Handlers — Tab Encuestas ──────────────────────────────────────────────

    handleLoadSurveys() {
        // Reutiliza datos ya cargados por _loadDashboard si están disponibles
        if (this.surveyRows && this.surveyRows.length > 0) {
            this.surveyMetrics = this._buildSurveyMetrics(this.surveyRows);
            this.surveyLoaded  = true;
            return;
        }

        this.isSurveyLoading = true;
        this.surveyMetrics   = null;

        getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  this.selectedAgent || null,
            csatOnly: false
        })
        .then(rows => {
            this.surveyRows    = rows || [];
            this.surveyMetrics = this._buildSurveyMetrics(this.surveyRows);
            this.surveyLoaded  = true;
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando encuestas', 'error');
        })
        .finally(() => { this.isSurveyLoading = false; });
    }

    // ── Handlers — Tab Ejecutivos ─────────────────────────────────────────────

    handleRefreshPresence() {
        this._loadPresence();
    }

    // ── Handlers — Tab Bitácora ───────────────────────────────────────────────

    handleLoadBitacora() {
        this._loadBitacora();
    }

    // ── Handlers — Tab Ejecutivos (historial) ─────────────────────────────────

    handlePresenceHistoryDateFromChange(e) { this.presenceHistoryDateFrom = e.detail.value; }
    handlePresenceHistoryDateToChange(e)   { this.presenceHistoryDateTo   = e.detail.value; }
    handlePresenceHistoryAgentChange(e)    { this.presenceHistoryAgent = e.detail.value; this.presenceHistoryPage = 1; }
    handlePhPrev() { if (!this.phPrevDisabled) this.presenceHistoryPage--; }
    handlePhNext() { if (!this.phNextDisabled) this.presenceHistoryPage++; }

    handleLoadPresenceHistory() {
        this.isPresenceHistoryLoading = true;
        this.presenceHistoryAgent     = '';
        this.presenceHistoryPage      = 1;
        getPresenceHistory({
            dateFrom:     this.presenceHistoryDateFrom,
            dateTo:       this.presenceHistoryDateTo,
            limitEntries: 1000
        })
        .then(result => {
            this.presenceHistoryData = (result || []).map(r => ({
                ...r,
                durationFormatted: r.durationMinutes != null
                    ? this._formatDuration(r.durationMinutes)
                    : (r.hasta == null ? 'Activo' : '—')
            }));
        })
        .catch(err   => { this._toast('Error', err.body?.message || 'Error cargando historial de presencia', 'error'); })
        .finally(()  => { this.isPresenceHistoryLoading = false; });
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    _loadDashboard() {
        this.isLoading  = true;
        this.surveyRows = [];

        const sessionsP = getSessionsDashboard({
            dateFrom:      this.dateFrom,
            dateTo:        this.dateTo,
            agentId:       this.selectedAgent || null,
            statusFilter:  this.statusFilter  || null,
            limitSessions: null
        })
        .then(result => { this.dashboardData = result; })
        .catch(err   => { this._toast('Error', err.body?.message || 'Error cargando sesiones', 'error'); });

        const surveysP = getSurveyData({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  this.selectedAgent || null,
            csatOnly: false
        })
        .then(rows => { this.surveyRows = rows || []; })
        .catch(()  => { this.surveyRows = []; });

        const hourlyP = getHourlySessionCount({
            dateFrom: this.hourlyFilterDate,
            dateTo:   this.hourlyFilterDate,
            agentId:  this.selectedAgent || null,
        })
        .then(result => { this.hourlyData = result || []; })
        .catch(()  => { this.hourlyData = []; });

        const hourlyPrevP = this.comparePreviousDay
            ? this._fetchPreviousDayHourly()
            : Promise.resolve().then(() => { this.hourlyPreviousData = []; });

        const hourlyDateP = getHourlyDateSessionCount({
            dateFrom: this.dateFrom,
            dateTo:   this.dateTo,
            agentId:  this.selectedAgent || null
        })
        .then(result => { this.hourlyDateData = result || []; })
        .catch(()  => { this.hourlyDateData = []; });

        Promise.all([sessionsP, surveysP, hourlyP, hourlyPrevP, hourlyDateP])
            .finally(() => { this.isLoading = false; });
    }

    _loadHourlyChart() {
        this.hourlyChartLoading = true;

        const mainP = getHourlySessionCount({
            dateFrom: this.hourlyFilterDate,
            dateTo:   this.hourlyFilterDate,
            agentId:  this.selectedAgent || null,
        })
        .then(result => {
            this.hourlyData = result || [];
            this._hourlyHash = null;
            this._hourlyDateRendered = false;
        })
        .catch(() => { this.hourlyData = []; });

        const prevP = this.comparePreviousDay
            ? this._fetchPreviousDayHourly()
            : Promise.resolve().then(() => { this.hourlyPreviousData = []; });

        const minDelay = new Promise(resolve => setTimeout(resolve, 1000));

        Promise.all([mainP, prevP, minDelay])
            .finally(() => { this.hourlyChartLoading = false; });
    }

    _fetchPreviousDayHourly() {
        const prev = new Date(this.hourlyFilterDate);
        prev.setDate(prev.getDate() - 1);
        const prevStr = prev.toISOString().split('T')[0];
        return getHourlySessionCount({
            dateFrom: prevStr,
            dateTo:   prevStr,
            agentId:  this.selectedAgent || null,
        })
        .then(result => {
            this.hourlyPreviousData = result || [];
            this._hourlyHash = null;
        })
        .catch(() => { this.hourlyPreviousData = []; });
    }

    _loadSessionMessages(sessionId) {
        const session = (this.dashboardData.sessions || []).find(s => s.sessionId === sessionId);
        if (!session || !session.conversationUUID) return;

        this.loadingSessionId = sessionId;
        getMessagesByUUID({
            conversationUUID: session.conversationUUID,
            conversationSfId: session.conversationId,
            sessionId
        })
        .then(entries => {
            this.sessionMessages = {
                ...this.sessionMessages,
                [sessionId]: this._processEntries(entries)
            };
        })
        .catch(err => {
            this._toast('Error', err.body?.message || 'Error cargando mensajes', 'error');
            this.expandedSessions = { ...this.expandedSessions, [sessionId]: false };
        })
        .finally(() => { this.loadingSessionId = null; });
    }

    _loadPresence() {
        this.isPresenceLoading = true;
        getAgentPresenceStatus()
        .then(result => { this.presenceData = result; })
        .catch(err   => { this._toast('Advertencia', 'Error obteniendo presencia: ' + (err.body?.message || ''), 'warning'); })
        .finally(()  => { this.isPresenceLoading = false; });
    }

    _loadBitacora() {
        this.isBitacoraLoading = true;
        getBitacoraEntries({
            dateFrom:     this.dateFrom,
            dateTo:       this.dateTo,
            agentId:      this.selectedAgent || null,
            limitEntries: 500
        })
        .then(result => { this.bitacoraData = result; this.bitacoraLoaded = true; })
        .catch(err   => { this._toast('Error', err.body?.message || 'Error cargando bitácora', 'error'); })
        .finally(()  => { this.isBitacoraLoading = false; });
    }

    // ── Survey Processing ─────────────────────────────────────────────────────

    _buildSurveyMetrics(rows) {
        if (!rows.length) {
            return { totalSurveys: 0, completedCount: 0, incompleteCount: 0, completedPct: 0, incompletePct: 0,
                     fcrPercent: 0, csatPercent: 0, csatAvgScore: 0, fcrByAgent: [], csatByAgent: [], surveyDetail: [] };
        }

        const completedCount  = rows.filter(r => r.status === 'Completada').length;
        const incompleteCount = rows.filter(r => r.status === 'Incompleta').length;
        const completedPct    = Math.round(completedCount  / rows.length * 100);
        const incompletePct   = 100 - completedPct;

        const fcrRows    = rows.filter(r => r.fcrAnswer != null);
        const fcrSi      = fcrRows.filter(r => r.fcrAnswer === 'Si').length;
        const fcrPercent = fcrRows.length ? Math.round(fcrSi / fcrRows.length * 100) : 0;

        const csatRows     = rows.filter(r => r.csatScore != null);
        const csatPos      = csatRows.filter(r => r.csatScore >= 4).length;
        const csatPercent  = csatRows.length ? Math.round(csatPos / csatRows.length * 100) : 0;
        const csatSum      = csatRows.reduce((acc, r) => acc + r.csatScore, 0);
        const csatAvgScore = csatRows.length ? (csatSum / csatRows.length).toFixed(1) : 0;

        const agentMap = {};
        rows.forEach(r => {
            const key = r.agentId || '__sin_asignar__';
            if (!agentMap[key]) agentMap[key] = { agentName: r.agentName || 'Sin asignar', fcr: [], csat: [] };
            if (r.fcrAnswer  != null) agentMap[key].fcr.push(r.fcrAnswer);
            if (r.csatScore  != null) agentMap[key].csat.push(r.csatScore);
        });

        const fcrByAgent  = [];
        const csatByAgent = [];
        Object.values(agentMap).forEach(ag => {
            const fcrPos = ag.fcr.filter(a => a === 'Si').length;
            const fcrTot = ag.fcr.length;
            const fcrPct = fcrTot ? Math.round(fcrPos / fcrTot * 100) : 0;
            fcrByAgent.push({ agentName: ag.agentName, fcrPercent: fcrPct, fcrCount: fcrPos, totalCount: fcrTot, fcrBarStyle: `width:${fcrPct}%` });

            const csatTot = ag.csat.length;
            const csatSat = ag.csat.filter(s => s >= 4).length;
            const csatPct = csatTot ? Math.round(csatSat / csatTot * 100) : 0;
            const csatAvg = csatTot ? (ag.csat.reduce((a,b)=>a+b,0)/csatTot).toFixed(1) : 0;
            csatByAgent.push({ agentName: ag.agentName, csatPercent: csatPct, avgScore: csatAvg, csatBarStyle: `width:${csatPct}%` });
        });

        const surveyDetail = rows.map(r => ({
            agentName:    r.agentName   || 'Sin asignar',
            accountName:  r.accountName || '—',
            clientName:   r.clientName  || '—',
            endUserPhone: r.phone       || '—',
            fcrAnswer:    r.fcrAnswer   || '—',
            csatAnswer:   r.csatAnswer  || '—',
            csatScore:    r.csatScore   ?? null,
            startTime:    r.sessionEndTime
        }));

        return { totalSurveys: rows.length, completedCount, incompleteCount, completedPct, incompletePct,
                 fcrPercent, csatPercent, csatAvgScore, fcrByAgent, csatByAgent, surveyDetail };
    }

    // ── Chart render ──────────────────────────────────────────────────────────

    _maybeRenderAgentLoad() {
        const canvas = this.template.querySelector('canvas.agent-load-chart');
        if (!canvas) return;
        const data = this.agentLoadData;
        if (!data) return;
        const hash = [...data.sessions, ...data.surveys].join(',');
        if (this._agentHash === hash && this._agentChart && this._agentChart.canvas === canvas) return;
        this._agentHash = hash;
        if (this._agentChart) { this._agentChart.destroy(); this._agentChart = null; }

        const colors     = data.labels.map((_, i) => this._agentColor(i));
        const totalSess  = data.sessions.reduce((a, b) => a + b, 0);

        this._agentChart = new window.Chart(canvas, {
            type: 'pie',
            data: {
                labels: data.labels,
                datasets: [{
                    label:            'Sesiones totales',
                    data:             data.sessions,
                    backgroundColor:  colors,
                    borderColor:      '#ffffff',
                    borderWidth:      2,
                    hoverOffset:      14,
                    hoverBorderWidth: 3
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'nearest', intersect: true },
                plugins: {
                    legend: { display: false },
                    title:  { display: false },
                    tooltip: {
                        callbacks: {
                            label: (ctx) => {
                                const val     = ctx.parsed;
                                const pct     = totalSess ? Math.round(val / totalSess * 100) : 0;
                                const surveys = data.surveys[ctx.dataIndex] || 0;
                                return [` Sesiones: ${val} (${pct}%)`, ` Encuestas: ${surveys}`];
                            }
                        }
                    }
                }
            }
        });
    }

    // Paleta de colores estable por índice de ejecutivo (compartida entre el
    // canvas del pie chart y la lista/leyenda HTML para que coincidan).
    _agentColor(index) {
        const palette = [
            '#1565c0', '#9b59b6', '#27ae60', '#e67e22', '#e74c3c',
            '#16a085', '#f1c40f', '#8e44ad', '#2c3e50', '#d35400',
            '#2980b9', '#c0392b', '#7f8c8d', '#2ecc71', '#d68910'
        ];
        return palette[index % palette.length];
    }

    // Listado completo de ejecutivos que acompaña al pie chart de "Carga por
    // Ejecutivo" — asegura que todos los ejecutivos sean visibles aunque su
    // porción en el gráfico sea muy pequeña para leer el label.
    get agentLoadListData() {
        const data = this.agentLoadData;
        if (!data) return [];
        const total = data.sessions.reduce((a, b) => a + b, 0);
        return data.labels.map((label, i) => ({
            key:         label,
            index:       i,
            agentName:   label,
            sessions:    data.sessions[i],
            surveys:     data.surveys[i],
            pct:         total ? Math.round(data.sessions[i] / total * 100) : 0,
            colorStyle:  `background-color:${this._agentColor(i)}`
        }));
    }

    // ── Interactividad de la leyenda del pie chart ────────────────────────────

    handleAgentLegendEnter(event) {
        if (!this._agentChart) return;
        const index = Number(event.currentTarget.dataset.index);
        const el = [{ datasetIndex: 0, index }];
        this._agentChart.setActiveElements(el);
        this._agentChart.tooltip.setActiveElements(el, { x: 0, y: 0 });
        this._agentChart.update();
    }

    handleAgentLegendLeave() {
        if (!this._agentChart) return;
        this._agentChart.setActiveElements([]);
        this._agentChart.tooltip.setActiveElements([], { x: 0, y: 0 });
        this._agentChart.update();
    }

    handleAgentLegendClick(event) {
        if (!this._agentChart) return;
        const index = Number(event.currentTarget.dataset.index);
        this._agentChart.toggleDataVisibility(index);
        this._agentChart.update();
    }

    _maybeRenderHourlyChart() {
        const canvas = this.template.querySelector('canvas.hourly-sessions-chart');
        if (!canvas) return;
        const data = this.hourlyChartData;
        if (!data) return;

        const prevData = this.comparePreviousDay && this.hourlyPreviousData && this.hourlyPreviousData.length
            ? this.hourlyPreviousData.map(h => h.count)
            : null;

        const hash = data.values.join(',') + '|' + (prevData ? prevData.join(',') : '') + '|' + this.comparePreviousDay;
        if (this._hourlyHash === hash && this._hourlyChart && this._hourlyChart.canvas === canvas) return;
        this._hourlyHash = hash;
        if (this._hourlyChart) { this._hourlyChart.destroy(); this._hourlyChart = null; }

        const values = data.values;
        const maxVal = Math.max(...values, ...(prevData || [0]), 1);
        const total  = values.reduce((a, b) => a + b, 0);
        const nonZero = values.filter(v => v > 0);
        const avg = nonZero.length ? Math.round(total / nonZero.length * 10) / 10 : 0;

        // Colores: bars que superan el promedio se destacan
        const barColors = values.map(v =>
            v >= avg && v > 0 ? 'red' : 'rgba(255,0,0,0.30)'
        );
        const borderColors = values.map(v =>
            v >= avg && v > 0 ? 'darkred' : 'rgba(255,0,0,0.45)'
        );

        // Dataset del promedio (línea horizontal)
        const avgLine = values.map(() => avg);

        // Plugin inline: dibujar línea de promedio + etiqueta
        const avgLinePlugin = {
            id: 'avgLinePlugin',
            afterDraw(chart) {
                if (avg <= 0) return;
                const yScale = chart.scales.y;
                const xScale = chart.scales.x;
                const yPos   = yScale.getPixelForValue(avg);
                const ctx    = chart.ctx;

                // Línea punteada
                ctx.save();
                ctx.beginPath();
                ctx.setLineDash([6, 4]);
                ctx.strokeStyle = '#e67e22';
                ctx.lineWidth   = 1.5;
                ctx.moveTo(xScale.left, yPos);
                ctx.lineTo(xScale.right, yPos);
                ctx.stroke();

                // Etiqueta
                ctx.fillStyle    = '#e67e22';
                ctx.font         = 'bold 10px Arial';
                ctx.textAlign    = 'right';
                ctx.textBaseline = 'bottom';
                ctx.fillText(`Promedio: ${avg}`, xScale.right, yPos - 3);
                ctx.restore();
            }
        };

        // Build title text
        let titleText = `Sesiones por Hora (${this.hourlyDayLabel}) — Total: ${this.hourlyDayTotal}`;
        if (prevData) {
            const prevTotal = prevData.reduce((a, b) => a + b, 0);
            titleText += ` | Ayer (${this.hourlyPreviousDayLabel}): ${prevTotal}`;
        }

        // Build datasets array
        const datasets = [
            {
                label:                'Sesiones creadas',
                data:                 values,
                backgroundColor:      barColors,
                borderColor:          borderColors,
                borderWidth:          1,
                borderRadius:         3,
                hoverBackgroundColor: 'red',
                barPercentage:        0.85,
                categoryPercentage:   0.9,
                order:                3
            },
            {
                label:           'Promedio',
                data:            avgLine,
                type:            'line',
                borderColor:     '#e67e22',
                borderDash:      [6, 4],
                borderWidth:     1.5,
                pointRadius:     0,
                fill:            false,
                order:           1
            }
        ];

        // Add previous day comparison dataset
        if (prevData) {
            datasets.push({
                label:           `Día anterior (${this.hourlyPreviousDayLabel})`,
                data:            prevData,
                type:            'line',
                borderColor:     'rgba(26,115,232,0.8)',
                backgroundColor: 'rgba(26,115,232,0.08)',
                borderWidth:     2,
                pointRadius:     3,
                pointBackgroundColor: 'rgba(26,115,232,0.9)',
                fill:            true,
                tension:         0.3,
                order:           2
            });
        }

        this._hourlyChart = new window.Chart(canvas, {
            type: 'bar',
            plugins: [avgLinePlugin],
            data: {
                labels: data.labels,
                datasets: datasets
            },
            options: {
                responsive:          true,
                maintainAspectRatio: false,
                interaction:         { mode: 'index', intersect: false },
                plugins: {
                    legend: { display: false },
                    title:  {
                        display:  true,
                        text:     titleText,
                        font:     { size: 13, weight: '600' },
                        color:    'red',
                        padding:  { bottom: 10 }
                    },
                    tooltip: {
                        backgroundColor: 'rgba(0,0,0,0.85)',
                        titleFont:        { size: 12 },
                        bodyFont:         { size: 12 },
                        callbacks: {
                            label: (ctx) => {
                                if (ctx.datasetIndex === 1) return ` Promedio: ${avg}`;
                                if (ctx.datasetIndex === 2) return ` Ayer: ${ctx.parsed.y}`;
                                const val  = ctx.parsed.y;
                                const flag = val >= avg && val > 0 ? ' \u25B2 Flujo alto' : '';
                                return ` Hoy: ${val} sesión(es)${flag}`;
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        grid:    { display: false },
                        ticks:   { font: { size: 10 }, color: '#404040', maxRotation: 0, autoSkip: true, maxTicksLimit: 24 }
                    },
                    y: {
                        beginAtZero: true,
                        suggestedMax: maxVal + Math.ceil(maxVal * 0.15),
                        ticks:   { stepSize: 1, font: { size: 10 }, color: '#404040' },
                        grid:    { color: 'rgba(0,0,0,0.06)' }
                    }
                }
            }
        });
    }

    _maybeRenderDailyTrend() {
        const canvas = this.template.querySelector('canvas.daily-trend-chart');
        if (!canvas) return;
        const data = this.dailyTrendData;
        if (!data) return;
        const hash = [...data.inHours, ...data.outOfHours, ...data.surveys].join(',');
        if (this._trendHash === hash && this._trendChart && this._trendChart.canvas === canvas) return;
        this._trendHash = hash;
        if (this._trendChart) { this._trendChart.destroy(); this._trendChart = null; }
        this._trendChart = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels: data.labels,
                datasets: [
                    {
                        label:                'En horario',
                        data:                 data.inHours,
                        borderColor:          '#1565c0',
                        backgroundColor:      'rgba(21,101,192,0.08)',
                        fill:                 true,
                        tension:              0.35,
                        pointRadius:          4,
                        pointBackgroundColor: '#1565c0',
                        spanGaps:             true
                    },
                    {
                        label:                'Fuera de horario',
                        data:                 data.outOfHours,
                        borderColor:          '#c0392b',
                        backgroundColor:      'rgba(192,57,43,0.08)',
                        fill:                 true,
                        tension:              0.35,
                        pointRadius:          4,
                        pointBackgroundColor: '#c0392b',
                        borderDash:           [6, 3],
                        spanGaps:             true
                    },
                    {
                        label:                'Encuestas completadas',
                        data:                 data.surveys,
                        borderColor:          '#9b59b6',
                        backgroundColor:      'rgba(155,89,182,0.08)',
                        fill:                 true,
                        tension:              0.35,
                        pointRadius:          4,
                        pointBackgroundColor: '#9b59b6',
                        borderDash:           [4, 3],
                        spanGaps:             true
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { position: 'top', labels: { font: { size: 11 }, padding: 10 } },
                    title:  { display: true, text: 'Volumen Diario de Sesiones', font: { size: 12 } }
                },
                scales: {
                    y: { beginAtZero: true, ticks: { stepSize: 1 }, grid: { color: 'rgba(0,0,0,0.05)' } }
                }
            }
        });
    }

    _maybeRenderCompleteness() {
        if (!this.surveyLoaded || !this.surveyMetrics) return;
        const canvas = this.template.querySelector('canvas.completeness-chart');
        if (!canvas) return;
        const { completedCount, incompleteCount, completedPct, incompletePct } = this.surveyMetrics;
        const hash = `${completedCount},${incompleteCount}`;
        if (this._completenessHash === hash && this._completenessChart) return;
        this._completenessHash = hash;
        if (this._completenessChart) { this._completenessChart.destroy(); this._completenessChart = null; }
        this._completenessChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels: [
                    `Completadas (${completedPct}%)`,
                    `Incompletas (${incompletePct}%)`
                ],
                datasets: [{
                    data:            [completedCount, incompleteCount],
                    backgroundColor: ['#27ae60', '#e74c3c'],
                    borderColor:     '#ffffff',
                    borderWidth:     3,
                    hoverBorderWidth: 4
                }]
            },
            options: {
                responsive:   false,
                cutout:       '58%',
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels:   { font: { size: 12 }, padding: 14 }
                    },
                    tooltip: {
                        callbacks: {
                            label(ctx) {
                                return ` ${ctx.label}: ${ctx.parsed} encuestas`;
                            }
                        }
                    }
                }
            }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _processEntries(entries) {
        return (entries || [])
            .filter(e => e.messageText)
            .sort((a, b) => {
                const ta = a.messageTimestamp ? new Date(a.messageTimestamp).getTime() : 0;
                const tb = b.messageTimestamp ? new Date(b.messageTimestamp).getTime() : 0;
                return ta - tb; // cronológico: más antiguo primero
            })
            .map(e => ({
                ...e,
                bubbleClass:   this._bubbleClass(e.senderRole),
                formattedTime: e.messageTimestamp
                    ? new Date(e.messageTimestamp).toLocaleString('es-CL') : ''
            }));
    }

    _bubbleClass(role) {
        const base = 'msg-bubble';
        if (role === 'EndUser')  return base + ' bubble-user';
        if (role === 'Agent')    return base + ' bubble-agent';
        if (role === 'Chatbot')  return base + ' bubble-bot';
        return base + ' bubble-system';
    }

    // ── Export Excel ─────────────────────────────────────────────────────────

    handleExportSessions(event) {
        const choice = event.detail.value;
        const cols = [
            { label: 'Ejecutivo',      fieldName: 'agentName',      type: 'text' },
            { label: 'Nombre Cliente', fieldName: 'endUserName',     type: 'text' },
            { label: 'Cuenta',         fieldName: 'accountName',     type: 'text' },
            { label: 'Teléfono',       fieldName: 'endUserPhone',    type: 'text' },
            { label: 'Inicio Sesión',  fieldName: 'startTime',       type: 'date' },
            { label: 'Fin Sesión',     fieldName: 'endTime',         type: 'date' },
            { label: 'Estado',         fieldName: 'status',          type: 'text' },
            { label: 'Duración (min)', fieldName: 'durationMinutes', type: 'number' }
        ];
        const rows = choice === 'visible'
            ? this.paginatedSessions
            : (this.dashboardData.sessions || []);
        this._exportToExcel(rows, cols, 'sesiones_mensajeria');
    }

    handleExportAgentComparison() {
        const cols = [
            { label: 'Ejecutivo',       fieldName: 'agentName' },
            { label: 'Total Sesiones',  fieldName: 'total' },
            { label: 'Atendidas',       fieldName: 'ended' },
            { label: '% Atendidas',     fieldName: 'endedPct' },
            { label: 'Activas',         fieldName: 'active' },
            { label: 'En cola',         fieldName: 'nueva' },
            { label: 'Otros estados',   fieldName: 'otros' }
        ];
        this._exportToExcel(this.agentComparisonRows, cols, 'comparativo_ejecutivos');
    }

    handleExportSurveys(event) {
        const choice = event.detail.value;
        const all = this.surveyMetrics?.surveyDetail || [];
        this._exportToExcel(all, this.surveyColumns, 'encuestas');
    }

    handleExportPresence(event) {
        this._exportToExcel(this.presenceData || [], this.presenceColumns, 'presencia_ejecutivos');
    }

    handleExportPresenceHistory(event) {
        const choice = event.detail.value;
        const rows = choice === 'visible'
            ? this.paginatedPresenceHistory
            : this.filteredPresenceHistory;
        this._exportToExcel(rows, this.presenceHistoryColumns, 'historial_conectividad');
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

    _formatDuration(minutes) {
        const mins = Math.round(Number(minutes));
        const h = Math.floor(mins / 60);
        const m = mins % 60;
        if (h === 0) return `${m}m`;
        if (m === 0) return `${h}h`;
        return `${h}h ${m}m`;
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