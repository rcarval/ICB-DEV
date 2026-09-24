import { LightningElement, track } from 'lwc';
import getReport from '@salesforce/apex/seidor_CaseMonthlyReportController.getReport';
import getCaseDetail from '@salesforce/apex/seidor_CaseMonthlyReportController.getCaseDetail';
import searchUsers from '@salesforce/apex/seidor_CaseMonthlyReportController.searchUsers';
import sendCaseReportEmail from '@salesforce/apex/seidor_CaseMonthlyReportController.sendCaseReportEmail';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import CHART_JS from '@salesforce/resourceUrl/chartJs';

const PAGE_SIZE = 20;
const CHART_MAX_SLICES = 10;
const CHART_PALETTE = [
    '#F62110', '#B0180B', '#1565c0', '#27ae60', '#9b59b6',
    '#f39c12', '#16a085', '#d35400', '#2980b9', '#8e44ad', '#7f8c8d'
];
const STATUS_LABEL_MAP = { Closed: 'Cerrado' };
const CASE_STATUS_OPTIONS = ['Análisis', 'En retiro', 'En devolución', 'Escalamiento', 'Closed'];
const ADVANCED_FIELDS = [
    { api: 'tipoNotaCredito', label: 'Tipo de Nota de Crédito' },
    { api: 'estadoNotaCredito', label: 'Estado de Nota de Crédito' },
    { api: 'estadoProducto', label: 'Estado de Producto' },
    { api: 'horarioRetiro', label: 'Horario de Retiro' },
    { api: 'fechaRetiro', label: 'Fecha de Retiro', type: 'date' }
];
const ADVANCED_FIELDS_BY_API = Object.fromEntries(ADVANCED_FIELDS.map(f => [f.api, f]));

export default class SeidorCaseReport extends NavigationMixin(LightningElement) {
    _resizeInitialized = false;
    _chartLibLoaded = false;
    _chartNeedsRender = false;
    _chart = null;
    @track chartDimension = 'tipoRequerimiento';
    @track chartLegend = [];
    @track isLoading = false;
    @track totalRecords = 0;
    @track accountFilter = '';
    @track accountSearchTerm = '';
    @track clienteDespachoFilter = '';
    @track clienteDespachoSearchTerm = '';
    @track propietarioFilter = '';
    @track propietarioSearchTerm = '';
    @track asesorFilter = '';
    @track asesorSearchTerm = '';
    @track tipoRequerimientoFilter = '';
    @track tipoRequerimientoSearchTerm = '';
    @track statusFilter = '';
    @track createdDateStartFilter = '';
    @track createdDateStartTerm = '';
    @track createdDateEndFilter = '';
    @track createdDateEndTerm = '';
    @track showAccountDropdown = false;
    @track showClienteDespachoDropdown = false;
    @track showPropietarioDropdown = false;
    @track showAsesorDropdown = false;
    @track showTipoRequerimientoDropdown = false;
    @track currentPage = 1;
    @track allRecords = [];
    @track collapsedGroups = {};
    @track pageGroups = [];
    @track filteredTotal = 0;
    @track totalPagesNum = 1;
    @track showExportMenu = false;
    @track showEmailModal = false;
    @track emailToList = [];
    @track emailCcList = [];
    @track emailToInput = '';
    @track emailCcInput = '';
    @track emailSubject = '';
    @track emailMessage = '';
    @track isSendingEmail = false;
    @track emailToSearchTerm = '';
    @track emailCcSearchTerm = '';
    @track showEmailToDropdown = false;
    @track showEmailCcDropdown = false;
    @track emailToUsers = [];
    @track emailCcUsers = [];
    @track sortField = '';
    @track sortDirection = 'asc';
    @track advancedFilters = [];
    @track advancedFieldSelected = '';
    @track advancedNewTerm = '';
    @track advancedNewShowDropdown = false;
    @track showCaseModal = false;
    @track isCaseLoading = false;
    @track selectedCase = {};

    get hasSelectedCase() {
        return this.selectedCase && this.selectedCase.id;
    }

    get hasNoSelectedCase() {
        return !(this.selectedCase && this.selectedCase.id);
    }

    get fechaRetiroDetail() {
        return this.selectedCase.fechaRetiro || '';
    }

    get fechaRecepcionDetail() {
        return this.selectedCase.fechaRecepcion || '';
    }

    get createdDateDetail() {
        return this.fmtDateTimeDetail(this.selectedCase.createdDate);
    }

    get closedDateDetail() {
        if (!this.selectedCase.closedDate) return '—';
        return this.fmtDateOnly(this.selectedCase.closedDate);
    }

    get valorNetoDetail() {
        return this.fmtMoney(this.selectedCase.valorNeto);
    }

    get hasResults() {
        return this.allRecords.length > 0;
    }

    get chartLabel() {
        const labels = {
            tipoRequerimiento: 'Tipo de Requerimiento',
            status: 'Estado del Caso',
            motivo: 'Motivo',
            causa: 'Causa'
        };
        return labels[this.chartDimension] || 'Tipo de Requerimiento';
    }

    get chartTotal() {
        return this.getFilteredRecords().length;
    }

    get hasChartData() {
        return this.getFilteredRecords().length > 0;
    }

    get accountOptions() {
        const term = this.accountSearchTerm.toLowerCase();
        const names = new Set();
        for (const r of this.allRecords) {
            if (r.accountName && (!term || r.accountName.toLowerCase().includes(term))) {
                names.add(r.accountName);
            }
        }
        return Array.from(names).sort().slice(0, 50);
    }

    get hasAccountOptions() {
        return this.accountOptions.length > 0;
    }

    get clienteDespachoOptions() {
        const term = this.clienteDespachoSearchTerm.toLowerCase();
        const vals = new Set();
        for (const r of this.allRecords) {
            if (r.clienteDespacho && (!term || r.clienteDespacho.toLowerCase().includes(term))) {
                vals.add(r.clienteDespacho);
            }
        }
        return Array.from(vals).sort().slice(0, 50);
    }

    get hasClienteDespachoOptions() {
        return this.clienteDespachoOptions.length > 0;
    }

    get propietarioOptions() {
        const term = this.propietarioSearchTerm.toLowerCase();
        const vals = new Set();
        for (const r of this.allRecords) {
            if (r.creadoPor && (!term || r.creadoPor.toLowerCase().includes(term))) {
                vals.add(r.creadoPor);
            }
        }
        return Array.from(vals).sort().slice(0, 50);
    }

    get hasPropietarioOptions() {
        return this.propietarioOptions.length > 0;
    }

    get asesorOptions() {
        const term = this.asesorSearchTerm.toLowerCase();
        const vals = new Set();
        for (const r of this.allRecords) {
            if (r.asesor && (!term || r.asesor.toLowerCase().includes(term))) {
                vals.add(r.asesor);
            }
        }
        return Array.from(vals).sort().slice(0, 50);
    }

    get hasAsesorOptions() {
        return this.asesorOptions.length > 0;
    }

    get tipoRequerimientoOptions() {
        const term = this.tipoRequerimientoSearchTerm.toLowerCase();
        const vals = new Set();
        for (const r of this.allRecords) {
            if (r.tipoRequerimiento && (!term || r.tipoRequerimiento.toLowerCase().includes(term))) {
                vals.add(r.tipoRequerimiento);
            }
        }
        return Array.from(vals).sort().slice(0, 50);
    }

    get hasTipoRequerimientoOptions() {
        return this.tipoRequerimientoOptions.length > 0;
    }

    get availableAdvancedFields() {
        return ADVANCED_FIELDS.filter(f => !this.advancedFilters.some(af => af.key === f.api));
    }

    get hasAvailableAdvancedFields() {
        return this.availableAdvancedFields.length > 0;
    }

    get advancedFieldValues() {
        const fieldCfg = ADVANCED_FIELDS_BY_API[this.advancedFieldSelected];
        if (!fieldCfg) return [];
        const term = this.advancedNewTerm.toLowerCase();
        const vals = new Set();
        for (const r of this.allRecords) {
            const v = r[fieldCfg.api];
            if (v && (!term || v.toLowerCase().includes(term))) {
                vals.add(v);
            }
        }
        return Array.from(vals).sort().slice(0, 50);
    }

    get hasAdvancedFieldValues() {
        return this.advancedFieldValues.length > 0;
    }

    get selectedAdvancedFieldIsDate() {
        const cfg = ADVANCED_FIELDS_BY_API[this.advancedFieldSelected];
        return !!(cfg && cfg.type === 'date');
    }

    get statusOptions() {
        const options = [{
            value: '',
            label: 'Todos',
            isSelected: !this.statusFilter
        }];
        return options.concat(CASE_STATUS_OPTIONS.map(v => ({
            value: v,
            label: STATUS_LABEL_MAP[v] || v,
            isSelected: v === this.statusFilter
        })));
    }

    get emailToOptions() {
        const term = this.emailToSearchTerm.toLowerCase();
        if (!term) return this.emailToUsers;
        return this.emailToUsers.filter(u =>
            (u.name || '').toLowerCase().includes(term) ||
            (u.email || '').toLowerCase().includes(term)
        );
    }

    get hasEmailToOptions() {
        return this.emailToOptions.length > 0;
    }

    get emailToPlaceholder() {
        return this.emailToList.length ? '' : 'Buscar usuario o escribir correo...';
    }

    get emailCcPlaceholder() {
        return this.emailCcList.length ? '' : 'Buscar usuario o escribir correo...';
    }

    get emailCcOptions() {
        const term = this.emailCcSearchTerm.toLowerCase();
        if (!term) return this.emailCcUsers;
        return this.emailCcUsers.filter(u =>
            (u.name || '').toLowerCase().includes(term) ||
            (u.email || '').toLowerCase().includes(term)
        );
    }

    get hasEmailCcOptions() {
        return this.emailCcOptions.length > 0;
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPagesNum;
    }

    get pageNumbers() {
        const pages = [];
        const total = this.totalPagesNum;
        const current = this.currentPage;
        let start = Math.max(1, current - 2);
        let end = Math.min(total, start + 4);
        start = Math.max(1, end - 4);
        for (let i = start; i <= end; i++) {
            pages.push({
                num: i,
                className: i === current ? 'page-btn page-btn-active' : 'page-btn'
            });
        }
        return pages;
    }

    connectedCallback() {
        this.loadData();
        this._loadChartLib();
        this._handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('mousedown', this._handleClickOutside);
    }

    disconnectedCallback() {
        document.removeEventListener('mousedown', this._handleClickOutside);
        if (this._chart) { this._chart.destroy(); this._chart = null; }
    }

    renderedCallback() {
        this._tryRenderChart();
        if (this._resizeInitialized) return;
        const handles = this.template.querySelectorAll('.resize-handle');
        if (!handles.length) return;
        this._resizeInitialized = true;
        handles.forEach(handle => {
            handle.addEventListener('mousedown', (e) => {
                e.preventDefault();
                const th = handle.parentElement;
                const table = th.closest('table');
                const startX = e.pageX;
                const startWidth = th.offsetWidth;
                handle.classList.add('resizing');
                table.classList.add('table-resizing');

                const onMove = (moveEvent) => {
                    const newWidth = Math.max(50, startWidth + (moveEvent.pageX - startX));
                    th.style.width = newWidth + 'px';
                    th.style.minWidth = newWidth + 'px';
                };
                const onUp = () => {
                    handle.classList.remove('resizing');
                    table.classList.remove('table-resizing');
                    document.removeEventListener('mousemove', onMove);
                    document.removeEventListener('mouseup', onUp);
                };
                document.addEventListener('mousemove', onMove);
                document.addEventListener('mouseup', onUp);
            });
        });
    }

    handleClickOutside(event) {
        const wrappers = this.template.querySelectorAll('.autocomplete-wrapper');
        let insideAny = false;
        wrappers.forEach(w => { if (w.contains(event.target)) insideAny = true; });
        if (!insideAny) {
            this.showAccountDropdown = false;
            this.showClienteDespachoDropdown = false;
            this.showPropietarioDropdown = false;
            this.showAsesorDropdown = false;
            this.showTipoRequerimientoDropdown = false;
            this.showEmailToDropdown = false;
            this.showEmailCcDropdown = false;
        }
    }

    computePageGroups() {
        const filtered = this.getFilteredRecords();
        this.filteredTotal = filtered.length;
        this.totalPagesNum = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
        if (this.currentPage > this.totalPagesNum) {
            this.currentPage = this.totalPagesNum;
        }
        const start = (this.currentPage - 1) * PAGE_SIZE;
        const paged = filtered.slice(start, start + PAGE_SIZE);

        const orderedKeys = [];
        const groupMap = {};
        for (const r of paged) {
            const key = r.yearMonth;
            if (!groupMap[key]) {
                orderedKeys.push(key);
                const isCollapsed = !!this.collapsedGroups[key];
                groupMap[key] = {
                    key: key,
                    monthLabel: r.monthLabel,
                    totalCases: 0,
                    collapsed: isCollapsed,
                    toggleIcon: isCollapsed ? '\u25B6' : '\u25BC',
                    records: []
                };
            }
            groupMap[key].records.push(r);
            groupMap[key].totalCases = groupMap[key].records.length;
        }
        this.pageGroups = orderedKeys.map(k => groupMap[k]);
    }

    getFilteredRecords() {
        const hasAccount = !!this.accountFilter;
        const hasCliente = !!this.clienteDespachoFilter;
        const hasPropietario = !!this.propietarioFilter;
        const hasAsesor = !!this.asesorFilter;
        const hasTipoRequerimiento = !!this.tipoRequerimientoFilter;
        const hasStatus = !!this.statusFilter;
        const hasCreatedDateStart = !!this.createdDateStartFilter;
        const hasCreatedDateEnd = !!this.createdDateEndFilter;
        let result;
        if (!hasAccount && !hasCliente && !hasPropietario && !hasAsesor && !hasTipoRequerimiento && !hasStatus && !hasCreatedDateStart && !hasCreatedDateEnd && this.advancedFilters.length === 0) {
            result = [...this.allRecords];
        } else {
            result = this.allRecords.filter(r => {
                if (hasAccount && !(r.accountName || '').toLowerCase().includes(this.accountFilter.toLowerCase())) return false;
                if (hasCliente && !(r.clienteDespacho || '').toLowerCase().includes(this.clienteDespachoFilter.toLowerCase())) return false;
                if (hasPropietario && !(r.creadoPor || '').toLowerCase().includes(this.propietarioFilter.toLowerCase())) return false;
                if (hasAsesor && !(r.asesor || '').toLowerCase().includes(this.asesorFilter.toLowerCase())) return false;
                if (hasTipoRequerimiento && !(r.tipoRequerimiento || '').toLowerCase().includes(this.tipoRequerimientoFilter.toLowerCase())) return false;
                if (hasStatus && r.status !== this.statusFilter) return false;
                if (r.createdDate) {
                    const recDate = r.createdDate.substring(0, 10);
                    if (hasCreatedDateStart && recDate < this.createdDateStartFilter) return false;
                    if (hasCreatedDateEnd && recDate > this.createdDateEndFilter) return false;
                }
                for (const af of this.advancedFilters) {
                    if (af.term) {
                        if (af.type === 'date') {
                            const v = this._toIsoDate(r[af.key]);
                            if (!v || v !== af.term) return false;
                        } else {
                            const v = r[af.key];
                            if (!v || !v.toLowerCase().includes(af.term.toLowerCase())) return false;
                        }
                    }
                }
                return true;
            });
        }
        if (this.sortField) {
            const dir = this.sortDirection === 'asc' ? 1 : -1;
            const field = this.sortField;
            const numericFields = ['cantidadReclamada', 'valorNeto'];
            const isNumeric = numericFields.includes(field);
            result.sort((a, b) => {
                let va = a[field];
                let vb = b[field];
                if (isNumeric) {
                    va = va != null ? Number(va) : 0;
                    vb = vb != null ? Number(vb) : 0;
                    return (va - vb) * dir;
                }
                va = (va || '').toString().toLowerCase();
                vb = (vb || '').toString().toLowerCase();
                return va < vb ? -dir : va > vb ? dir : 0;
            });
        }
        return result;
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
        this.currentPage = 1;
        this.computePageGroups();
    }

    _arrowFor(fieldName) {
        return this.sortField === fieldName ? (this.sortDirection === 'asc' ? '\u25B2' : '\u25BC') : '';
    }

    get sortArrowTipoRequerimiento() { return this._arrowFor('tipoRequerimiento'); }
    get sortArrowCaseNumber() { return this._arrowFor('caseNumber'); }
    get sortArrowCreatedDate() { return this._arrowFor('createdDate'); }
    get sortArrowClosedDate() { return this._arrowFor('closedDate'); }
    get sortArrowPeriodoAtencion() { return this._arrowFor('periodoAtencion'); }
    get sortArrowAccountName() { return this._arrowFor('accountName'); }
    get sortArrowClienteDespacho() { return this._arrowFor('clienteDespacho'); }
    get sortArrowNombreDireccion() { return this._arrowFor('nombreDireccion'); }
    get sortArrowComunaSucursal() { return this._arrowFor('comunaSucursal'); }
    get sortArrowRegionCliente() { return this._arrowFor('regionCliente'); }
    get sortArrowSku() { return this._arrowFor('sku'); }
    get sortArrowNombreProducto() { return this._arrowFor('nombreProducto'); }
    get sortArrowCantidadReclamada() { return this._arrowFor('cantidadReclamada'); }
    get sortArrowUm() { return this._arrowFor('um'); }
    get sortArrowTipoUMReclamo() { return this._arrowFor('tipoUMReclamo'); }
    get sortArrowValorNeto() { return this._arrowFor('valorNeto'); }
    get sortArrowMotivo() { return this._arrowFor('motivo'); }
    get sortArrowCausa() { return this._arrowFor('causa'); }
    get sortArrowCategoriaReclamo() { return this._arrowFor('categoriaReclamo'); }
    get sortArrowProcedeReclamo() { return this._arrowFor('procedeReclamo'); }
    get sortArrowMotivoNoProcede() { return this._arrowFor('motivoNoProcede'); }
    get sortArrowStatus() { return this._arrowFor('status'); }
    get sortArrowCreadoPor() { return this._arrowFor('creadoPor'); }
    get sortArrowAsesor() { return this._arrowFor('asesor'); }
    get sortArrowTipoNotaCredito() { return this._arrowFor('tipoNotaCredito'); }
    get sortArrowCumplePlazos() { return this._arrowFor('cumplePlazos'); }

    loadData() {
        this.isLoading = true;
        getReport()
            .then(result => {
                const groups = result.groups || [];
                const records = [];
                for (const g of groups) {
                    for (const r of (g.records || [])) {
                        records.push({
                            ...r,
                            formattedCreatedDate: this.fmtDate(r.createdDate),
                            formattedClosedDate: this.fmtDateOnly(r.closedDate),
                            formattedValorNeto: this.fmtMoney(r.valorNeto),
                            caseUrl: '/lightning/r/Case/' + r.id + '/view',
                            yearMonth: g.year + '-' + String(g.month).padStart(2, '0'),
                            monthLabel: g.monthLabel
                        });
                    }
                }
                this.allRecords = records;
                this.totalRecords = records.length;
                this.currentPage = 1;
                this.computePageGroups();
                this._requestChartRender();
            })
            .catch(error => {
                let msg = 'Error desconocido';
                if (error && error.body && error.body.message) {
                    msg = error.body.message;
                }
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: msg,
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleChartDimensionChange(event) {
        this.chartDimension = event.target.value;
        this._requestChartRender();
    }

    _loadChartLib() {
        loadScript(this, CHART_JS)
            .then(() => {
                this._chartLibLoaded = true;
                this._tryRenderChart();
            })
            .catch(err => console.error('Chart.js load error', err));
    }

    _tryRenderChart() {
        if (!this._chartLibLoaded || !this._chartNeedsRender) return;
        if (this._renderChart()) {
            this._chartNeedsRender = false;
        }
    }

    _requestChartRender() {
        this._chartNeedsRender = true;
    }

    _pieField() {
        if (this.chartDimension === 'status') return 'status';
        if (this.chartDimension === 'motivo') return 'categoria';
        if (this.chartDimension === 'causa') return 'causa';
        return 'tipoRequerimiento';
    }

    _renderChart() {
        return this._renderPieChart();
    }

    _renderPieChart() {
        if (!this.hasChartData) {
            this.chartLegend = [];
            if (this._chart) { this._chart.destroy(); this._chart = null; }
            return true;
        }
        const canvas = this.template.querySelector('canvas.case-report-chart');
        if (!canvas) {
            return false;
        }
        if (this._chart) { this._chart.destroy(); this._chart = null; }

        const field = this._pieField();
        const labels = [];
        const values = [];
        const colors = [];
        this._countByField(field, CHART_MAX_SLICES).forEach((e, i) => {
            labels.push(STATUS_LABEL_MAP[e.label] || e.label);
            values.push(e.value);
            colors.push(CHART_PALETTE[i % CHART_PALETTE.length]);
        });
        const totalCases = values.reduce((a, b) => a + b, 0);
        this.chartLegend = labels.map((label, i) => ({
            label,
            value: values[i],
            color: colors[i],
            style: 'background: ' + colors[i] + ';'
        }));

        // eslint-disable-next-line no-undef
        this._chart = new window.Chart(canvas, {
            type: 'pie',
            data: {
                labels: labels,
                datasets: [{
                    data: values,
                    backgroundColor: colors,
                    borderColor: '#ffffff',
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        callbacks: {
                            label: ctx => {
                                const pct = totalCases ? Math.round(ctx.parsed / totalCases * 100) : 0;
                                return ` ${ctx.label}: ${ctx.parsed} casos (${pct}%)`;
                            }
                        }
                    }
                }
            }
        });
        return true;
    }

    _countByField(field, max) {
        const records = this.getFilteredRecords();
        const counts = new Map();
        for (const r of records) {
            let v = r[field];
            if (v === null || v === undefined || String(v).trim() === '') v = 'Sin especificar';
            counts.set(String(v), (counts.get(String(v)) || 0) + 1);
        }
        const entries = Array.from(counts.entries())
            .map(([label, value]) => ({ label, value }))
            .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));
        const top = entries.slice(0, max);
        if (entries.length > max) {
            top.push({
                label: 'Otros',
                value: entries.slice(max).reduce((s, e) => s + e.value, 0)
            });
        }
        return top;
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        const updated = { ...this.collapsedGroups };
        updated[key] = !updated[key];
        this.collapsedGroups = updated;
        this.computePageGroups();
    }

    handleAccountInput(event) {
        this.accountSearchTerm = event.target.value;
        this.showAccountDropdown = true;
        this.accountFilter = this.accountSearchTerm;
        this.applyFilters();
    }

    handleAccountFocus() {
        this.showAccountDropdown = true;
    }

    handleAccountSelect(event) {
        this.accountSearchTerm = event.currentTarget.dataset.value;
        this.accountFilter = this.accountSearchTerm;
        this.showAccountDropdown = false;
        this.applyFilters();
    }

    handleClienteDespachoInput(event) {
        this.clienteDespachoSearchTerm = event.target.value;
        this.showClienteDespachoDropdown = true;
        this.clienteDespachoFilter = this.clienteDespachoSearchTerm;
        this.applyFilters();
    }

    handleClienteDespachoFocus() {
        this.showClienteDespachoDropdown = true;
    }

    handleClienteDespachoSelect(event) {
        this.clienteDespachoSearchTerm = event.currentTarget.dataset.value;
        this.clienteDespachoFilter = this.clienteDespachoSearchTerm;
        this.showClienteDespachoDropdown = false;
        this.applyFilters();
    }

    handlePropietarioInput(event) {
        this.propietarioSearchTerm = event.target.value;
        this.showPropietarioDropdown = true;
        this.propietarioFilter = this.propietarioSearchTerm;
        this.applyFilters();
    }

    handlePropietarioFocus() {
        this.showPropietarioDropdown = true;
    }

    handlePropietarioSelect(event) {
        this.propietarioSearchTerm = event.currentTarget.dataset.value;
        this.propietarioFilter = this.propietarioSearchTerm;
        this.showPropietarioDropdown = false;
        this.applyFilters();
    }

    handleAsesorInput(event) {
        this.asesorSearchTerm = event.target.value;
        this.showAsesorDropdown = true;
        this.asesorFilter = this.asesorSearchTerm;
        this.applyFilters();
    }

    handleAsesorFocus() {
        this.showAsesorDropdown = true;
    }

    handleAsesorSelect(event) {
        this.asesorSearchTerm = event.currentTarget.dataset.value;
        this.asesorFilter = this.asesorSearchTerm;
        this.showAsesorDropdown = false;
        this.applyFilters();
    }

    handleTipoRequerimientoInput(event) {
        this.tipoRequerimientoSearchTerm = event.target.value;
        this.showTipoRequerimientoDropdown = true;
        this.tipoRequerimientoFilter = this.tipoRequerimientoSearchTerm;
        this.applyFilters();
    }

    handleTipoRequerimientoFocus() {
        this.showTipoRequerimientoDropdown = true;
    }

    handleTipoRequerimientoSelect(event) {
        this.tipoRequerimientoSearchTerm = event.currentTarget.dataset.value;
        this.tipoRequerimientoFilter = this.tipoRequerimientoSearchTerm;
        this.showTipoRequerimientoDropdown = false;
        this.applyFilters();
    }

    handleStatusChange(event) {
        this.statusFilter = event.target.value;
        this.applyFilters();
    }

    handleCreatedDateStartInput(event) {
        this.createdDateStartTerm = event.target.value;
        this.createdDateStartFilter = this.createdDateStartTerm;
        this.applyFilters();
    }

    handleAdvancedFieldChange(event) {
        this.advancedFieldSelected = event.target.value;
        this.advancedNewTerm = '';
        this.advancedNewShowDropdown = false;
    }

    handleAdvancedTermInput(event) {
        this.advancedNewTerm = event.target.value;
        this.advancedNewShowDropdown = true;
    }

    handleAdvancedTermFocus() {
        this.advancedNewShowDropdown = true;
    }

    handleAdvancedTermSelect(event) {
        const value = event.currentTarget.dataset.value;
        if (this.advancedFieldSelected) {
            const cfg = ADVANCED_FIELDS_BY_API[this.advancedFieldSelected];
            this.advancedFilters = [...this.advancedFilters, { key: this.advancedFieldSelected, label: cfg ? cfg.label : this.advancedFieldSelected, term: value, termLabel: value, type: cfg ? cfg.type || 'text' : 'text' }];
        }
        this.advancedFieldSelected = '';
        this.advancedNewTerm = '';
        this.advancedNewShowDropdown = false;
        this.applyFilters();
    }

    handleAdvancedDateChange(event) {
        const value = event.target.value;
        if (this.advancedFieldSelected && value) {
            const cfg = ADVANCED_FIELDS_BY_API[this.advancedFieldSelected];
            const p = value.split('-');
            const display = p.length === 3 ? p[2] + '/' + p[1] + '/' + p[0] : value;
            this.advancedFilters = [...this.advancedFilters, { key: this.advancedFieldSelected, label: cfg ? cfg.label : this.advancedFieldSelected, term: value, termLabel: display, type: 'date' }];
        }
        this.advancedFieldSelected = '';
        this.advancedNewTerm = '';
        this.advancedNewShowDropdown = false;
        this.applyFilters();
    }

    handleAdvancedRowRemove(event) {
        const key = event.currentTarget.dataset.key;
        this.advancedFilters = this.advancedFilters.filter(af => af.key !== key);
        this.applyFilters();
    }


    applyFilters() {
        this.currentPage = 1;
        this.computePageGroups();
        this._requestChartRender();
    }

    handleSearch() {
        this.accountFilter = this.accountSearchTerm;
        this.clienteDespachoFilter = this.clienteDespachoSearchTerm;
        this.propietarioFilter = this.propietarioSearchTerm;
        this.asesorFilter = this.asesorSearchTerm;
        this.tipoRequerimientoFilter = this.tipoRequerimientoSearchTerm;
        this.createdDateStartFilter = this.createdDateStartTerm;
        this.createdDateEndFilter = this.createdDateEndTerm;
        this.applyFilters();
    }

    handleClearFilters() {
        this.accountSearchTerm = '';
        this.accountFilter = '';
        this.clienteDespachoSearchTerm = '';
        this.clienteDespachoFilter = '';
        this.propietarioSearchTerm = '';
        this.propietarioFilter = '';
        this.asesorSearchTerm = '';
        this.asesorFilter = '';
        this.tipoRequerimientoSearchTerm = '';
        this.tipoRequerimientoFilter = '';
        this.statusFilter = '';
        this.createdDateStartTerm = '';
        this.createdDateStartFilter = '';
        this.createdDateEndTerm = '';
        this.createdDateEndFilter = '';
        this.advancedFilters = [];
        this.advancedFieldSelected = '';
        this.advancedNewTerm = '';
        this.advancedNewShowDropdown = false;
        this.applyFilters();
    }

    handleFirstPage() {
        this.currentPage = 1;
        this.computePageGroups();
    }

    handlePrevPage() {
        if (!this.isFirstPage) {
            this.currentPage--;
            this.computePageGroups();
        }
    }

    handleNextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.computePageGroups();
        }
    }

    handleLastPage() {
        this.currentPage = this.totalPagesNum;
        this.computePageGroups();
    }

    handlePageClick(event) {
        this.currentPage = parseInt(event.currentTarget.dataset.page, 10);
        this.computePageGroups();
    }

    handleToggleExportMenu() {
        this.showExportMenu = !this.showExportMenu;
    }

    handleOpenCase(event) {
        const caseId = event.currentTarget.dataset.id;
        if (!caseId) return;
        this.showCaseModal = true;
        this.isCaseLoading = true;
        this.selectedCase = {};
        getCaseDetail({ caseId: caseId })
            .then(result => {
                this.selectedCase = result || {};
            })
            .catch(error => {
                this.showCaseModal = false;
                let msg = 'Error al cargar el detalle del caso';
                if (error && error.body && error.body.message) {
                    msg = error.body.message;
                }
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: msg,
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isCaseLoading = false;
            });
    }

    handleCloseCaseModal() {
        this.showCaseModal = false;
        this.selectedCase = {};
    }

    handleOpenInConsole() {
        if (!this.hasSelectedCase) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedCase.id,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    handleExportFiltered() {
        this.showExportMenu = false;
        this.exportToExcel(this.getFilteredRecords(), 'Reporte_Casos_Filtrado');
    }

    handleExportAll() {
        this.showExportMenu = false;
        this.exportToExcel(this.allRecords, 'Reporte_Casos_Completo');
    }

    handleOpenEmailModal() {
        this.emailSubject = 'Reporte de Casos - ' + new Date().toLocaleDateString('es-CL');
        this.emailMessage = '';
        this.emailToList = [];
        this.emailCcList = [];
        this.emailToInput = '';
        this.emailCcInput = '';
        this.emailToSearchTerm = '';
        this.emailCcSearchTerm = '';
        this.emailToUsers = [];
        this.emailCcUsers = [];
        this.showEmailToDropdown = false;
        this.showEmailCcDropdown = false;
        this.showEmailModal = true;
    }

    handleCloseEmailModal() {
        this.showEmailModal = false;
        this.showEmailToDropdown = false;
        this.showEmailCcDropdown = false;
    }

    handleEmailToInput(event) {
        this.emailToInput = event.target.value;
        this.emailToSearchTerm = event.target.value;
        this.showEmailToDropdown = true;
        searchUsers({ searchTerm: event.target.value || ' ' })
            .then(users => { this.emailToUsers = users || []; })
            .catch(() => { this.emailToUsers = []; });
    }

    handleEmailToFocus() {
        this.showEmailToDropdown = true;
        const term = this.emailToSearchTerm || ' ';
        searchUsers({ searchTerm: term })
            .then(users => { this.emailToUsers = users || []; })
            .catch(() => { this.emailToUsers = []; });
    }

    handleEmailToSelect(event) {
        const name = event.currentTarget.dataset.name;
        const email = event.currentTarget.dataset.email;
        this.addEmailChip('to', email, name);
        this.emailToInput = '';
        this.emailToSearchTerm = '';
        this.showEmailToDropdown = false;
    }

    handleEmailToKeyDown(event) {
        this.handleEmailKeyDown(event, 'to');
    }

    handleEmailCcKeyDown(event) {
        this.handleEmailKeyDown(event, 'cc');
    }

    handleEmailKeyDown(event, field) {
        if (event.key !== 'Enter' && event.key !== ',') {
            return;
        }
        event.preventDefault();
        const raw = field === 'to' ? this.emailToInput : this.emailCcInput;
        this.addEmailsFromText(field, raw);
        if (field === 'to') {
            this.emailToInput = '';
            this.emailToSearchTerm = '';
        } else {
            this.emailCcInput = '';
            this.emailCcSearchTerm = '';
        }
        this.showEmailToDropdown = false;
        this.showEmailCcDropdown = false;
    }

    addEmailsFromText(field, raw) {
        const parts = (raw || '').split(/[;,]+/).map(e => e.trim()).filter(e => e.length > 0);
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        const invalid = parts.filter(e => !emailRegex.test(e));
        if (invalid.length > 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: field === 'to' ? 'Correo inválido en Para' : 'Correo inválido en Copia',
                message: 'Formato incorrecto: ' + invalid.join(', '),
                variant: 'error'
            }));
            return;
        }
        parts.forEach(email => this.addEmailChip(field, email));
    }

    addEmailChip(field, email, name) {
        const list = field === 'to' ? [...this.emailToList] : [...this.emailCcList];
        if (!list.some(r => r.email === email)) {
            list.push({ email: email, name: name || null, label: name || email });
        }
        if (field === 'to') {
            this.emailToList = list;
        } else {
            this.emailCcList = list;
        }
    }

    removeEmailToRecipient(event) {
        event.stopPropagation();
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const list = [...this.emailToList];
        list.splice(idx, 1);
        this.emailToList = list;
    }

    removeEmailCcRecipient(event) {
        event.stopPropagation();
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const list = [...this.emailCcList];
        list.splice(idx, 1);
        this.emailCcList = list;
    }

    handleEmailCcInput(event) {
        this.emailCcInput = event.target.value;
        this.emailCcSearchTerm = event.target.value;
        this.showEmailCcDropdown = true;
        searchUsers({ searchTerm: event.target.value || ' ' })
            .then(users => { this.emailCcUsers = users || []; })
            .catch(() => { this.emailCcUsers = []; });
    }

    handleEmailCcFocus() {
        this.showEmailCcDropdown = true;
        const term = this.emailCcSearchTerm || ' ';
        searchUsers({ searchTerm: term })
            .then(users => { this.emailCcUsers = users || []; })
            .catch(() => { this.emailCcUsers = []; });
    }

    handleEmailCcSelect(event) {
        const name = event.currentTarget.dataset.name;
        const email = event.currentTarget.dataset.email;
        this.addEmailChip('cc', email, name);
        this.emailCcInput = '';
        this.emailCcSearchTerm = '';
        this.showEmailCcDropdown = false;
    }

    handleEmailSubjectInput(event) {
        this.emailSubject = event.target.value;
    }

    handleEmailMessageInput(event) {
        this.emailMessage = event.target.value;
    }

    handleSendEmail() {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

        const rawTo = this.emailToList.map(r => r.email).map(e => e.trim()).filter(e => e.length > 0);
        if (rawTo.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Debe ingresar al menos un correo en "Para".',
                variant: 'error'
            }));
            return;
        }
        const invalidTo = rawTo.filter(e => !emailRegex.test(e));
        if (invalidTo.length > 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Correo inválido en Para',
                message: 'Formato incorrecto: ' + invalidTo.join(', '),
                variant: 'error'
            }));
            return;
        }

        const rawCc = this.emailCcList.map(r => r.email).map(e => e.trim()).filter(e => e.length > 0);
        const invalidCc = rawCc.filter(e => !emailRegex.test(e));
        if (invalidCc.length > 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Correo inválido en Copia',
                message: 'Formato incorrecto: ' + invalidCc.join(', '),
                variant: 'error'
            }));
            return;
        }

        if (!this.emailSubject.trim()) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'El asunto es obligatorio.',
                variant: 'error'
            }));
            return;
        }

        const records = this.getFilteredRecords();
        if (records.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Aviso',
                message: 'No hay datos para enviar.',
                variant: 'warning'
            }));
            return;
        }

        const htmlBody = this.buildEmailBody(records, this.emailMessage);
        const attachmentName = 'Reporte_Casos_' + new Date().toISOString().slice(0, 10) + '.xls';
        const attachmentBase64 = this.buildExcelBase64(records);
        this.isSendingEmail = true;

        sendCaseReportEmail({
            toAddresses: rawTo,
            ccAddresses: rawCc,
            subject: this.emailSubject,
            htmlBody: htmlBody,
            attachmentName: attachmentName,
            attachmentBase64: attachmentBase64
        })
        .then(() => {
            const total = rawTo.length + rawCc.length;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Correo enviado',
                message: 'Reporte enviado a ' + total + ' destinatario(s).',
                variant: 'success'
            }));
            this.showEmailModal = false;
        })
        .catch(error => {
            let msg = 'Error al enviar el correo.';
            if (error && error.body && error.body.message) {
                msg = error.body.message;
            }
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: msg,
                variant: 'error'
            }));
        })
        .finally(() => {
            this.isSendingEmail = false;
        });
    }

    buildEmailBody(records, userMessage) {
        const headers = [
            'Mes', 'Tipo Req.', 'N Caso', 'F. Apertura', 'F. Cierre', 'Periodo',
            'Cuenta', 'Cliente Desp.', 'Nombre Direccion', 'Comuna', 'Region',
            'SKU', 'Producto', 'Cant.', 'UM', 'Tipo UM', 'Valor Neto',
            'Motivo', 'Causa', 'Categoria', 'Procede', 'Motivo No proc.',
            'Fecha Retiro', 'Fecha Recepción',
            'Estado', 'Creado por', 'Asesor', 'Cod. Asesor', 'Tipo NC', 'Cumple Plazos'
        ];

        const orderedKeys = [];
        const groupMap = {};
        for (const r of records) {
            const key = r.yearMonth;
            if (!groupMap[key]) {
                orderedKeys.push(key);
                groupMap[key] = { label: r.monthLabel, records: [] };
            }
            groupMap[key].records.push(r);
        }

        let body = '';
        body += '<div style="max-width:100%;background:#ffffff;border-radius:8px;overflow:hidden;border:1px solid #e5e5e5;font-family:Arial,Helvetica,sans-serif;">';

        body += '<div style="background:linear-gradient(135deg,#B0180B 0%,#F62110 100%);padding:16px 20px;">';
        body += '<h1 style="margin:0;font-size:18px;color:#ffffff;font-weight:700;">Reporte de Casos</h1>';
        body += '<p style="margin:4px 0 0;font-size:13px;color:rgba(255,255,255,0.85);">' + records.length + ' registros</p>';
        body += '</div>';

        if (userMessage && userMessage.trim()) {
            body += '<div style="padding:16px 20px;border-bottom:1px solid #e5e5e5;background:#fafaf9;">';
            body += '<p style="margin:0;font-size:14px;color:#181818;line-height:1.5;white-space:pre-wrap;">' + this.esc(userMessage) + '</p>';
            body += '</div>';
        }

        body += '<div style="padding:20px;border-bottom:1px solid #e5e5e5;background:#ffffff;text-align:center;">';
        body += '<p style="margin:0 0 12px;font-size:12px;color:#444746;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Acceso directo al panel</p>';
        body += '<p style="margin:0 0 14px;font-size:13px;color:#181818;line-height:1.5;">Para revisar el detalle completo, la trazabilidad y los tiempos de respuesta de cada caso, acceda directamente al panel oficial de reportes.</p>';
        body += '<a href="https://icbfs.lightning.force.com/lightning/n/Panel_de_Casos"';
        body += ' style="display:inline-block;background:linear-gradient(135deg,#B0180B 0%,#F62110 100%);color:#ffffff;padding:12px 32px;border-radius:6px;font-size:14px;font-weight:700;text-decoration:none;border:1px solid #B0180B;box-shadow:0 2px 6px rgba(176,24,11,0.35);">';
        body += '<span style="padding:0;">Ver Panel de Casos</span>';
        body += '</a>';
        body += '<p style="margin:12px 0 0;font-size:11px;color:#9b9a9a;">Enlace seguro al Panel de Casos en Salesforce</p>';
        body += '</div>';

        body += '<div style="overflow-x:auto;padding:0;">';
        body += '<table cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;font-size:12px;">';

        body += '<thead><tr style="background:#f3f2f2;border-bottom:2px solid #dddbda;">';
        for (const h of headers) {
            body += '<th style="padding:8px 10px;font-weight:700;font-size:11px;color:#444746;text-transform:uppercase;letter-spacing:0.3px;text-align:left;white-space:nowrap;border-bottom:1px solid #dddbda;">' + h + '</th>';
        }
        body += '</tr></thead><tbody>';

        for (const key of orderedKeys) {
            const g = groupMap[key];
            body += '<tr style="background:#D41C0E;">';
            body += '<td colspan="30" style="padding:8px 14px;color:#ffffff;font-weight:700;font-size:13px;">' + this.esc(g.label) + ' (' + g.records.length + ' registros)</td>';
            body += '</tr>';

            for (const r of g.records) {
                body += '<tr style="border-bottom:1px solid #f3f2f2;">';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(g.label) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.tipoRequerimiento) + '</td>';
                body += '<td style="padding:6px 10px;color:#F62110;font-weight:600;white-space:nowrap;"><a href="' + window.location.origin + r.caseUrl + '" style="color:#F62110;text-decoration:underline;">' + this.esc(r.caseNumber) + '</a></td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.formattedCreatedDate) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.formattedClosedDate) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.periodoAtencion) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.accountName) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.clienteDespacho) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.nombreDireccion) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.comunaSucursal) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.regionCliente) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.sku) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.nombreProducto) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;text-align:right;white-space:nowrap;">' + (r.cantidadReclamada != null ? r.cantidadReclamada : '') + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.um) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.tipoUMReclamo) + '</td>';
                body += '<td style="padding:6px 10px;color:#B0180B;font-weight:600;text-align:right;white-space:nowrap;">' + (r.valorNeto != null ? r.valorNeto : '') + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.motivo) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.causa) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.categoriaReclamo) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.procedeReclamo) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.motivoNoProcede) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.fechaRetiro) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.fechaRecepcion) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.status) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.creadoPor) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.asesor) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.codigoAsesor) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.tipoNotaCredito) + '</td>';
                body += '<td style="padding:6px 10px;color:#181818;white-space:nowrap;">' + this.esc(r.cumplePlazos) + '</td>';
                body += '</tr>';
            }
        }

        body += '</tbody></table></div>';

        body += '<div style="padding:12px 20px;border-top:1px solid #e5e5e5;background:#fafaf9;">';
        body += '<p style="margin:0;font-size:11px;color:#747474;">Generado desde el Panel de Reporte de Casos &mdash; ' + new Date().toLocaleDateString('es-CL') + ' ' + new Date().toLocaleTimeString('es-CL', {hour: '2-digit', minute: '2-digit'}) + '</p>';
        body += '</div>';

        body += '</div>';

        return body;
    }

    buildExcelBase64(records) {
        const groups = this.groupRecordsByMonth(records);

        const headers = [
            'Mes', 'Tipo Req.', 'N Caso', 'F. Apertura', 'F. Cierre', 'Periodo',
            'Cuenta', 'Cliente Desp.', 'Nombre Direccion', 'Comuna', 'Region',
            'SKU', 'Producto', 'Cant.', 'UM', 'Tipo UM', 'Valor Neto',
            'Motivo', 'Causa', 'Categoria', 'Procede', 'Motivo No proc.',
            'Fecha Retiro', 'Fecha Recepción',
            'Estado', 'Creado por', 'Asesor', 'Cod. Asesor', 'Tipo NC', 'Cumple Plazos'
        ];

        let html = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">';
        html += '<head><meta charset="UTF-8">';
        html += '<style>td,th{mso-number-format:"\\@";}th{background:#032d60;color:#fff;font-weight:bold;border:1px solid #999;padding:4px 8px;}.month-row{background:#F62110;color:#fff;font-weight:bold;font-size:14px;}.data-row td{border:1px solid #ccc;padding:3px 6px;}.money{text-align:right;mso-number-format:"\\$\\ #\\,\\#\\#0";}.number{text-align:right;mso-number-format:"\\#,\\#\\#0";}</style>';
        html += '</head><body><table border="1">';
        html += '<thead><tr>';
        for (const h of headers) {
            html += '<th>' + h + '</th>';
        }
        html += '</tr></thead><tbody>';

        for (const key of groups.orderedKeys) {
            const g = groups.groupMap[key];
            html += '<tr class="month-row"><td colspan="30">' + g.label + ' (' + g.records.length + ' registros)</td></tr>';
            for (const r of g.records) {
                html += '<tr class="data-row">';
                html += '<td>' + g.label + '</td>';
                html += '<td>' + this.esc(r.tipoRequerimiento) + '</td>';
                html += '<td>' + this.esc(r.caseNumber) + '</td>';
                html += '<td>' + this.esc(r.formattedCreatedDate) + '</td>';
                html += '<td>' + this.esc(r.formattedClosedDate) + '</td>';
                html += '<td>' + this.esc(r.periodoAtencion) + '</td>';
                html += '<td>' + this.esc(r.accountName) + '</td>';
                html += '<td>' + this.esc(r.clienteDespacho) + '</td>';
                html += '<td>' + this.esc(r.nombreDireccion) + '</td>';
                html += '<td>' + this.esc(r.comunaSucursal) + '</td>';
                html += '<td>' + this.esc(r.regionCliente) + '</td>';
                html += '<td>' + this.esc(r.sku) + '</td>';
                html += '<td>' + this.esc(r.nombreProducto) + '</td>';
                html += '<td class="number">' + (r.cantidadReclamada != null ? r.cantidadReclamada : '') + '</td>';
                html += '<td>' + this.esc(r.um) + '</td>';
                html += '<td>' + this.esc(r.tipoUMReclamo) + '</td>';
                html += '<td class="money">' + (r.valorNeto != null ? r.valorNeto : '') + '</td>';
                html += '<td>' + this.esc(r.motivo) + '</td>';
                html += '<td>' + this.esc(r.causa) + '</td>';
                html += '<td>' + this.esc(r.categoriaReclamo) + '</td>';
                html += '<td>' + this.esc(r.procedeReclamo) + '</td>';
                html += '<td>' + this.esc(r.motivoNoProcede) + '</td>';
                html += '<td>' + this.esc(r.fechaRetiro) + '</td>';
                html += '<td>' + this.esc(r.fechaRecepcion) + '</td>';
                html += '<td>' + this.esc(r.status) + '</td>';
                html += '<td>' + this.esc(r.creadoPor) + '</td>';
                html += '<td>' + this.esc(r.asesor) + '</td>';
                html += '<td>' + this.esc(r.codigoAsesor) + '</td>';
                html += '<td>' + this.esc(r.tipoNotaCredito) + '</td>';
                html += '<td>' + this.esc(r.cumplePlazos) + '</td>';
                html += '</tr>';
            }
        }

        html += '</tbody></table></body></html>';

        return btoa(unescape(encodeURIComponent(html)));
    }

    groupRecordsByMonth(records) {
        const orderedKeys = [];
        const groupMap = {};
        for (const r of records) {
            const key = r.yearMonth;
            if (!groupMap[key]) {
                orderedKeys.push(key);
                groupMap[key] = { label: r.monthLabel, records: [] };
            }
            groupMap[key].records.push(r);
        }
        return { orderedKeys, groupMap };
    }

    exportToExcel(records, filename) {
        if (!records || records.length === 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Aviso',
                message: 'No hay datos para exportar',
                variant: 'warning'
            }));
            return;
        }

        const base64 = this.buildExcelBase64(records);
        const dataUri = 'data:application/vnd.ms-excel;base64,' + base64;
        const link = document.createElement('a');
        link.href = dataUri;
        link.download = filename + '.xls';
        link.click();

        this.dispatchEvent(new ShowToastEvent({
            title: 'Exportado',
            message: records.length + ' registros exportados a Excel',
            variant: 'success'
        }));
    }

    esc(v) {
        if (v === null || v === undefined) return '';
        return String(v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    fmtDate(v) {
        if (!v) return '';
        const d = new Date(v);
        return String(d.getDate()).padStart(2, '0') + '/' +
               String(d.getMonth() + 1).padStart(2, '0') + '/' +
               d.getFullYear();
    }

    _toIsoDate(v) {
        if (!v) return null;
        const p = String(v).split('-');
        if (p.length === 3) return v;
        const m = String(v).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
        if (m) return m[3] + '-' + m[2].padStart(2, '0') + '-' + m[1].padStart(2, '0');
        return null;
    }

    fmtDateOnly(v) {
        if (!v) return '';
        const p = String(v).split('-');
        if (p.length === 3) return p[2] + '/' + p[1] + '/' + p[0];
        return this.fmtDate(v);
    }

    fmtMoney(v) {
        if (v === null || v === undefined) return '';
        return '$ ' + Number(v).toLocaleString('es-CL');
    }

    fmtDateTimeDetail(v) {
        if (!v) return '';
        const d = new Date(v);
        const dateStr = String(d.getDate()).padStart(2, '0') + '/' +
            String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear();
        const timeStr = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
        return dateStr + ' ' + timeStr;
    }
}