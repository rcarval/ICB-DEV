import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { NavigationMixin }         from 'lightning/navigation';
import getCuentasPaginadas         from '@salesforce/apex/seidor_CuentasSinContactosService.getCuentasPaginadas';
import getTotales                  from '@salesforce/apex/seidor_CuentasSinContactosService.getTotales';
import exportarExcel               from '@salesforce/apex/seidor_CuentasSinContactosService.exportarExcel';
import prepararCorreoAsesor        from '@salesforce/apex/seidor_CuentasSinContactosService.prepararCorreoAsesor';
import enviarCorreoAsesor          from '@salesforce/apex/seidor_CuentasSinContactosService.enviarCorreoAsesor';

const PAGE_SIZE    = 200;
const DEBOUNCE_MS  = 400;
const MAX_CORREOS_CC = 10;
const REGEX_EMAIL  = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export default class CuentasSinContactos extends NavigationMixin(LightningElement) {

    @track isLoading   = false;
    @track loadingMore = false;
    @track exportando  = false;
    @track searchTerm  = '';
    @track _allRows    = [];
    @track totales     = { total: null, conRespaldo: null, sinRespaldo: null,
                           principales: null, topAsesores: [] };
    @track correo      = {
        abierto: false, preparando: false, enviando: false,
        de: '', nombreDe: '', para: '', asunto: '',
        cc: [], ccInput: ''
    };

    // Filas visibles del grupo del asesor en el modal (preview + envío)
    _filasCorreo = null;

    // Acordeón: inicia TODO COLAPSADO; solo se expanden los asesores marcados
    @track _expandidos = {};

    _nextAnchor = null;
    _debounceId = null;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._recargar();
    }

    disconnectedCallback() {
        clearTimeout(this._debounceId);
    }

    // ── Computed — agrupación por asesor (Owner de la cuenta principal) ───────

    // Cada grupo sintetiza el asesor de la primera fila que llega; dentro del
    // grupo, los bloques contiguos de una misma cuenta principal llevan su
    // propio rowspan. El servidor ordena por (OwnerId, ParentId, Id) para que
    // los bloques lleguen contiguos por página.
    _buildGroups(rows) {
        const buckets = new Map();

        for (const r of rows) {
            const key = r.parentOwnerId ?? r.parentOwnerName;
            let b = buckets.get(key);
            if (!b) {
                b = { key, rows: [] };
                buckets.set(key, b);
            }
            b.rows.push(r);
        }

        return [...buckets.values()];
    }

    get gruposPlanos() {
        const out = [];
        let grupoIdx = 0;
        for (const g of this._buildGroups(this._allRows)) {
            const grupoKey = String(g.key);
            const spanAsesor = g.rows.length;

            // Grupo colapsado (estado inicial): una sola fila resumen por asesor
            if (!this._expandidos[grupoKey]) {
                out.push({
                    key: 'colapso-' + grupoKey,
                    esFilaResumen: true,
                    grupoKey,
                    asesorNombre: g.rows[0].parentOwnerName || '—',
                    totalOcultas: spanAsesor
                });
                grupoIdx++;
                continue;
            }

            g.rows.forEach((r, idx) => {
                const anterior = idx > 0 ? g.rows[idx - 1] : null;
                const esPrimeraDePrincipal =
                    !anterior || anterior.parentAccountId !== r.parentAccountId;
                let spanPrincipal = 1;
                if (esPrimeraDePrincipal) {
                    for (
                        let k = idx + 1;
                        k < g.rows.length &&
                        g.rows[k].parentAccountId === r.parentAccountId;
                        k++
                    ) { spanPrincipal++; }
                }
                out.push({
                    key:                  r.key,
                    row:                  r,
                    grupoIdx,
                    grupoKey,
                    esPrimera:            idx === 0,
                    esPrimeraDePrincipal,
                    spanAsesor,
                    spanPrincipal,
                    asesorNombre:         r.parentOwnerName || '—',
                    asesorEmail:          r.parentOwnerEmail || ''
                });
            });
            grupoIdx++;
        }
        return out;
    }

    get hasData() { return this.gruposPlanos.length > 0; }

    // ── Computed — KPIs y paginación ──────────────────────────────────────────

    // null/-1 = métrica no disponible en el servidor (límite de plataforma)
    get totalHijasTxt()      { return this._metricaTxt(this.totales.total); }
    get conRespaldoTxt()     { return this._metricaTxt(this.totales.conRespaldo); }
    get sinRespaldoTxt()     { return this._metricaTxt(this.totales.sinRespaldo); }
    get mostradas()          { return this._allRows.length; }
    get contadorTxt()        { return `Mostrando ${this.mostradas} de ${this.totalHijasTxt} sucursales`; }
    get hayMas()             { return !!this._nextAnchor; }
    get cargarMasDisabled()  { return !this._nextAnchor || this.loadingMore; }
    get labelCargarMas()     { return this.loadingMore ? 'Cargando...' : 'Cargar más'; }
    get iconoCargarMas()     { return this.loadingMore ? 'utility:download' : 'utility:chevrondown'; }

    _metricaTxt(v) {
        return (v == null || v < 0) ? 'N/D' : String(v);
    }

    // ── Computed — tabla resumen (misma data que el Excel exportado) ─────────

    get resumenMetricas() {
        const t = this.totales;
        return [
            { key: 'r1', label: 'Sucursales sin contacto directo',    valor: this._metricaTxt(t.total) },
            { key: 'r2', label: 'Con contactos en cliente principal', valor: this._metricaTxt(t.conRespaldo) },
            { key: 'r3', label: 'Sin ningún contacto disponible',     valor: this._metricaTxt(t.sinRespaldo) },
            { key: 'r4', label: 'Cuentas principales distintas',      valor: this._metricaTxt(t.principales) }
        ];
    }

    get topAsesoresVisibles() { return this.totales.topAsesores || []; }

    get hayTopAsesores() { return this.topAsesoresVisibles.length > 0; }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleSearchChange(e) {
        this.searchTerm = e.detail.value ?? e.target.value ?? '';
        clearTimeout(this._debounceId);
        this._debounceId = setTimeout(() => this._recargar(), DEBOUNCE_MS);
    }

    handleRefresh() { this._recargar(); }

    // ── Acordeón por asesor (solo UI: colapsa/expande el bloque completo) ─────

    handleToggleGrupo(event) {
        const grupoKey = event.currentTarget.dataset.key;
        if (!grupoKey) return;
        if (this._expandidos[grupoKey]) {
            delete this._expandidos[grupoKey];
        } else {
            this._expandidos[grupoKey] = true;
        }
        this._expandidos = Object.assign({}, this._expandidos);
    }

    handleToggleGrupoKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleToggleGrupo(event);
        }
    }

    handleCargarMas() {
        if (!this.hayMas || this.loadingMore || this.isLoading) return;
        this.loadingMore = true;
        this._cargarPagina(true)
            .catch(err => this._toast('Error', this._errorMessage(err), 'error'))
            .finally(() => { this.loadingMore = false; });
    }

    handleExport() {
        if (this.exportando) return;
        if (!this.mostradas && !this.hayMas) {
            this._toast('Aviso', 'No hay datos para exportar.', 'info');
            return;
        }
        this.exportando = true;
        exportarExcel({ searchTerm: this.searchTerm, maxFilas: null })
            .then(res => {
                if (!res.versionId) {
                    this._toast('Aviso', 'No hay datos para exportar.', 'info');
                    return;
                }
                // Descarga via URL de Salesforce: LWS bloquea Blob text/csv
                window.open('/sfc/servlet.shepherd/version/download/' + res.versionId, '_blank');
                const msg = res.truncado
                    ? `Se exportaron ${res.filas} sucursales (archivo truncado por límite de tamaño).`
                    : `Se exportaron ${res.filas} sucursales.`;
                this._toast('Éxito', msg, res.truncado ? 'warning' : 'success');
            })
            .catch(err => this._toast('Error', this._errorMessage(err), 'error'))
            .finally(() => { this.exportando = false; });
    }

    // ── Correo al asesor ──────────────────────────────────────────────────────

    get enviarDisabled() {
        return this.correo.preparando || this.correo.enviando || !this.correo.tablaHtml;
    }

    get enviarLabel() {
        return this.correo.enviando ? 'Enviando...' : 'Enviar';
    }

    get enviarDisabled() {
        return this.correo.preparando || this.correo.enviando || !this._filasCorreo;
    }

    get hayCc() { return this.correo.cc.length > 0; }

    // Preview nativo de las filas del grupo (mismos spans que la tabla principal)
    get correoFilas() {
        if (!this._filasCorreo) return [];
        const out = [];
        this._filasCorreo.forEach((r, idx) => {
            const anterior = idx > 0 ? this._filasCorreo[idx - 1] : null;
            const esPrimeraDePrincipal =
                !anterior || anterior.parentAccountId !== r.parentAccountId;
            let spanPrincipal = 1;
            if (esPrimeraDePrincipal) {
                for (
                    let k = idx + 1;
                    k < this._filasCorreo.length &&
                    this._filasCorreo[k].parentAccountId === r.parentAccountId;
                    k++
                ) { spanPrincipal++; }
            }
            out.push({ key: r.accountId, row: r, esPrimeraDePrincipal, spanPrincipal });
        });
        return out;
    }

    // Abre el modal con las filas VISIBLES del grupo del asesor (mismo filtro
    // de búsqueda que la pantalla). Al servidor solo se le envían los IDs;
    // los datos completos los re-consulta él mismo al construir el correo.
    handleAbrirCorreo(event) {
        const idx   = Number(event.currentTarget.dataset.grupo);
        const grupo = this._buildGroups(this._allRows)[idx];
        if (!grupo || !grupo.rows.length) return;

        const emailAsesor = grupo.rows.map(r => r.parentOwnerEmail).find(e => !!e);
        if (!emailAsesor) {
            this._toast('Aviso', 'El asesor no tiene correo registrado.', 'info');
            return;
        }

        const nombreAsesor = grupo.rows[0].parentOwnerName || '—';
        this.correo.abierto    = true;
        this.correo.para       = emailAsesor;
        this.correo.asunto     = `Sucursales sin contacto directo - ${nombreAsesor}`;
        this.correo.cc         = [];
        this.correo.ccInput    = '';
        this.correo.preparando = true;

        this._filasCorreo = grupo.rows.map(r => ({
            accountId:            r.accountId,
            accountName:          r.accountName,
            recordTypeName:       r.recordTypeName,
            rut:                  r.rut,
            codigoCliente:        r.codigoCliente,
            nombreFantasia:       r.nombreFantasia,
            parentAccountId:      r.parentAccountId,
            parentAccountName:    r.parentAccountName,
            parentRut:            r.parentRut,
            parentCodigoCliente:  r.parentCodigoCliente,
            parentNombreFantasia: r.parentNombreFantasia,
            parentOwnerId:        r.parentOwnerId,
            parentOwnerName:      r.parentOwnerName,
            parentOwnerEmail:     r.parentOwnerEmail,
            padreConContactos:    r.padreConContactos,
            contactoCountPadre:   r.contactoCountPadre,
            contactosPadre:       r.contactosPadre
        }));

        prepararCorreoAsesor({ sucursalIds: this._filasCorreo.map(r => r.accountId) })
            .then(res => {
                this.correo.de       = res.de || '';
                this.correo.nombreDe = res.nombreUsuario || '';
            })
            .catch(err => {
                this._cerrarCorreo();
                this._toast('Error', this._errorMessage(err), 'error');
            })
            .finally(() => { this.correo.preparando = false; });
    }

    handleCerrarCorreo() {
        if (this.correo.enviando) return;
        this._cerrarCorreo();
    }

    _cerrarCorreo() { this.correo.abierto = false; }

    handleAsuntoChange(e) {
        this.correo.asunto = e.detail.value ?? e.target.value ?? '';
    }

    handleCcChange(e) {
        this.correo.ccInput = e.detail.value ?? e.target.value ?? '';
    }

    // Enter o coma agregan el chip; blur también consolida lo tipeado
    handleCcKeydown(e) {
        if (e.key !== 'Enter' && e.key !== ',') return;
        e.preventDefault();
        this._agregarCc();
    }

    handleCcBlur() { this._agregarCc(); }

    _agregarCc() {
        const raw = (this.correo.ccInput || '').trim().replace(/,+$/, '');
        this.correo.ccInput = '';
        if (!raw) return;
        for (const candidato of raw.split(',').map(s => s.trim()).filter(Boolean)) {
            if (this.correo.cc.length >= MAX_CORREOS_CC) {
                this._toast('Aviso', `Máximo ${MAX_CORREOS_CC} correos en copia.`, 'info');
                break;
            }
            if (!REGEX_EMAIL.test(candidato)) {
                this._toast('Aviso', `"${candidato}" no es un correo válido.`, 'warning');
                continue;
            }
            if (!this.correo.cc.some(c => c.toLowerCase() === candidato.toLowerCase())) {
                this.correo.cc = [...this.correo.cc, candidato];
            }
        }
    }

    handleQuitarCc(event) {
        const idx = Number(event.currentTarget.dataset.idx);
        this.correo.cc = this.correo.cc.filter((_, k) => k !== idx);
    }

    handleEnviarCorreo() {
        if (this.enviarDisabled) return;
        if (!REGEX_EMAIL.test(this.correo.para || '')) {
            this._toast('Aviso', 'El destinatario no tiene un correo válido.', 'warning');
            return;
        }
        this.correo.enviando = true;
        enviarCorreoAsesor({
            sucursalIds: this._filasCorreo.map(r => r.accountId),
            para:        this.correo.para,
            cc:          this.correo.cc,
            asunto:      this.correo.asunto
        })
            .then(() => {
                this._cerrarCorreo();
                this._toast('Éxito', `Correo enviado a ${this.correo.para}`, 'success');
            })
            .catch(err => this._toast('Error', this._errorMessage(err), 'error'))
            .finally(() => { this.correo.enviando = false; });
    }

    // Navega al registro de Account (principal o hija)
    handleAccountClick(event) {
        event.preventDefault();
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:      accountId,
                objectApiName: 'Account',
                actionName:    'view'
            }
        });
    }

    // ── Data Loading ──────────────────────────────────────────────────────────

    async _recargar() {
        this.isLoading   = true;
        this._nextAnchor = null;
        try {
            await this._cargarPagina(false);
        } catch (err) {
            this._allRows = [];
            this._toast('Error al cargar cuentas', this._errorMessage(err), 'error');
        } finally {
            this.isLoading = false;
        }
        // Totales globales en segundo plano: no bloquean el render de la tabla
        this._cargarTotales();
    }

    _cargarTotales() {
        getTotales({ searchTerm: this.searchTerm })
            .then(res => {
                this.totales = {
                    total:        res.totalCuentas,
                    conRespaldo:  res.conRespaldoPadre,
                    sinRespaldo:  res.sinRespaldoPadre,
                    principales:  res.cuentasPrincipales,
                    topAsesores:  res.topAsesores || []
                };
            })
            .catch(() => {
                // Silencioso: los badges quedan como N/D
            });
    }

    async _cargarPagina(append) {
        const res = await getCuentasPaginadas({
            searchTerm: this.searchTerm,
            anchorId:   append ? this._nextAnchor : null,
            pageSize:   PAGE_SIZE
        });
        const filas = this._mapearFilas(res.filas || []);
        this._allRows    = append ? this._allRows.concat(filas) : filas;
        this._nextAnchor = res.nextAnchor || null;
    }

    _mapearFilas(data) {
        return data.map(r => ({
            accountId:            r.accountId,
            accountName:          r.accountName,
            recordTypeName:       r.recordTypeName,
            rut:                  r.rut,
            codigoCliente:        r.codigoCliente,
            nombreFantasia:       r.nombreFantasia,
            parentAccountId:      r.parentAccountId,
            parentAccountName:    r.parentAccountName,
            parentRut:            r.parentRut,
            parentCodigoCliente:  r.parentCodigoCliente,
            parentNombreFantasia: r.parentNombreFantasia,
            parentOwnerId:        r.parentOwnerId,
            parentOwnerName:      r.parentOwnerName,
            parentOwnerEmail:     r.parentOwnerEmail || '',
            padreConContactos:    r.padreConContactos === true,
            contactoCountPadre:   r.contactoCountPadre || 0,
            contactosPadre:       r.contactosPadre || [],
            key:                  r.accountId
        }));
    }

    _errorMessage(error) {
        if (!error) return 'Error desconocido';
        return error.body?.message || error.message || JSON.stringify(error);
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}