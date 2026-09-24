import { LightningElement, track, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getMachines from '@salesforce/apex/MachineSelectorController.getMachines';

export default class DynamicMachineSelector extends LightningElement {
    // --- Outputs para el Flow ---
    @api selectedMachineId;
    @api selectedMachineName;
    @api machineSelectionsJson = '[]';
    @api allowDynamicFilters = false;
    @api allowMultiSelect = false;
    @api initialBusinessFilter = '';
    @api pricebookId = '';
    @api tipoEquipo = '';
    @api esSolicitudEspecial = false;
    @api solicitudEspecialTexto = '';
    _preSelectedMachineId = '';
    @api
    get preSelectedMachineId() { return this._preSelectedMachineId; }
    set preSelectedMachineId(value) {
        this._preSelectedMachineId = value;
        if (value && this.allMachines.length > 0) {
            this.selectedMachine = this.allMachines.find(m => m.Id === value) || null;
            this._applyFilters();
        }
    }

    // --- Estado interno ---
    @track allMachines = [];
    @track filteredMachines = [];
    @track selectedMachine = null;
    @track selectedMachinesList = []; // Para multi-selección: [{Id, Name, quantity}]
    @track selectedDetailMachine = null; // Máquina abierta en el popup "Ver detalle"
    @track isLoading = true;
    @track _viewMode = 'dynamic';
    @track showMultiQuestion = false; // Para guiado: pregunta si quiere multi
    @track multiAnswer = ''; // 'maquina' o 'especial'

    // Filtros
    @track filterNegocio = '';
    @track filterMetodologia = '';
    @track filterFlujo = '';
    @track filterVolumen = '';
    @track filterLeche = '';
    @track filterSearch = '';

    // --- Opciones Estáticas Base ---
    tiposNegocio = [
        { label: 'Banquetería', value: 'BANQUETERIA' },
        { label: 'Restaurantes', value: 'RESTAURANTES' },
        { label: 'Oficinas', value: 'OFICINAS' },
        { label: 'Hoteles', value: 'HOTELES' },
        { label: 'Cadenas', value: 'CADENAS' },
        { label: 'To Go', value: 'TO_GO' },
        { label: 'Minimarket', value: 'MINIMARKET' },
        { label: 'Cafeterías', value: 'CAFETERIAS' },
        { label: 'Club', value: 'CLUB' },
    ];

    metodologiasBase = [
        { label: 'Cápsula',      value: 'CAPSULA' },
        { label: 'Grano Entero', value: 'GRANO_ENTERO' },
        { label: 'Grano Molido', value: 'GRANO_MOLIDO' },
    ];

    flujosBase = [
        { label: 'Bajo',  value: 'Baja' },
        { label: 'Medio', value: 'Medio' },
        { label: 'Alto',  value: 'Alta' },
    ];

    volumenesBase = [
        { label: '14 cápsulas/día',  value: 'X14' },
        { label: '20 cápsulas/día',  value: 'X20' },
        { label: '34 cápsulas/día',  value: 'X34' },
        { label: '40 cápsulas/día',  value: 'X40' },
        { label: '75 tazas/día',     value: 'X75' },
        { label: '96 tazas/día',     value: 'X96' },
        { label: '100 tazas/día',    value: 'X100' },
        { label: '150 tazas/día',    value: 'X150' },
    ];

    tiposLeche = [
        { label: 'Leche Líquida', value: 'LECHE_LIQUIDA' },
        { label: 'Leche Soluble (Polvo)', value: 'LECHE_SOLUBLE' },
        { label: 'Sin Leche', value: 'SIN_LECHE' },
    ];

    // --- Getters de modo multi ---
    get isMultiMode() {
        // Multi siempre en modo dinámico o cuando allowMultiSelect está activo
        return this.allowMultiSelect || this.isDynamicMode;
    }

    get hasMultiSelections() {
        return this.selectedMachinesList.length > 0;
    }

    get totalSelectedCount() {
        return this.selectedMachinesList.reduce((sum, m) => sum + m.quantity, 0);
    }

    get multiSelectionSummary() {
        return this.selectedMachinesList.map(m =>
            m.quantity > 1 ? `${m.Name} (x${m.quantity})` : m.Name
        ).join(', ');
    }

    // --- Popup "Ver detalle" ---
    get detalleImagenHtml() {
        return this._capAllImagesInHtml(this.selectedDetailMachine?.Imagen_Propuesta__c);
    }

    get detalleTieneImagen() {
        return !!this.detalleImagenHtml;
    }

    get detalleMetodologiaChips() {
        return this._toChips(this.selectedDetailMachine?.Metodologia__c);
    }

    get detalleNegocioChips() {
        return this._toChips(this.selectedDetailMachine?.Tipo_de_Negocio_Recomendado__c);
    }

    get detalleCapacidadChips() {
        return this._toChips(this.selectedDetailMachine?.Capacidad_Sugerida__c);
    }

    get detalleLecheChips() {
        return this._toChips(this.selectedDetailMachine?.Tipo_de_Leche__c);
    }

    get detalleYaAgregada() {
        if (!this.selectedDetailMachine) return false;
        if (this.isMultiMode) {
            return this.selectedMachinesList.some(m => m.Id === this.selectedDetailMachine.Id);
        }
        return this.selectedMachine?.Id === this.selectedDetailMachine.Id;
    }

    get detalleBotonLabel() {
        return this.detalleYaAgregada ? 'Quitar' : 'Agregar';
    }

    // --- Wire: carga máquinas desde Apex ---
    @wire(getMachines, { pricebookId: '$pricebookId', tipoEquipo: '$tipoEquipo' })
    wiredMachines({ data, error }) {
        if (data) {
            this.allMachines = data;
            if (this.initialBusinessFilter) {
                this.filterNegocio = this.initialBusinessFilter;
            }
            // Si es Dispensador, forzar modo dinámico y multi
            if (this.tipoEquipo === 'Dispensador') {
                this._viewMode = 'dynamic';
                this.allowMultiSelect = true;
            }
            const restoreId = this._preSelectedMachineId || this.selectedMachineId;
            if (restoreId) {
                this.selectedMachine = this.allMachines.find(m => m.Id === restoreId) || null;
            }
            this._restaurarSeleccionMulti();
            this._applyFilters();
            this.isLoading = false;
        } else if (error) {
            console.error('Error cargando máquinas:', error);
            this.isLoading = false;
        }
    }

    // --- Getters de Modo ---
    get isDynamicMode() { return this.allowDynamicFilters && this._viewMode === 'dynamic'; }
    get isGuidedMode()  { return !this.allowDynamicFilters || this._viewMode === 'guided'; }
    get dynamicClass()  { return this.isDynamicMode ? 'mode-btn active' : 'mode-btn'; }
    get guidedClass()   { return this.isGuidedMode  ? 'mode-btn active' : 'mode-btn'; }

    // Pregunta "Seleccionar Máquina / Solicitud especial": siempre visible y editable
    // en modo guiado, para que el asesor pueda cambiar de opción sin perder el resto
    // del avance. No se oculta al responder (a diferencia del diseño anterior).
    get showMultiQuestionInGuided() {
        return this.isGuidedMode;
    }

    // Refleja el estado efectivo aunque el componente se haya remontado (volver atrás):
    // multiAnswer es @track local y se resetea, pero esSolicitudEspecial es @api y
    // conserva lo que el Flow ya tenía guardado.
    get multiAnswerEfectivo() {
        if (this.esSolicitudEspecial) return 'especial';
        return this.multiAnswer;
    }

    // El binding value={} en un <select> nativo no refleja la opción marcada
    // (LWC1057 / no vuelve a seleccionarla tras un remount) — se controla por
    // opción con "selected" en su lugar, que sí es un atributo válido de <option>.
    get respuestaEsVacia() {
        return !this.multiAnswerEfectivo;
    }

    get respuestaEsMaquina() {
        return this.multiAnswerEfectivo === 'maquina';
    }

    get respuestaEsEspecial() {
        return this.multiAnswerEfectivo === 'especial';
    }

    // Solicitud especial: reemplaza el resto del guiado por un texto libre.
    get showSolicitudEspecialStep() {
        return this.isGuidedMode && this.esSolicitudEspecial;
    }

    // Tipo de negocio solo se muestra después de elegir "Seleccionar Máquina" (y no en solicitud especial)
    get showNegocioStep() {
        return this.isGuidedMode && !this.esSolicitudEspecial && this.multiAnswerEfectivo === 'maquina';
    }

    // --- Lógica de Filtros Interdependientes ---
    get availableMetodologias() {
        const machines = this.allMachines.filter(m =>
            (!this.filterNegocio || this._multiContains(m.Tipo_de_Negocio_Recomendado__c, this.filterNegocio)) &&
            (this.isGuidedMode ? true : (
                (!this.filterFlujo || this._multiContains(m.Capacidad_Sugerida__c, this.filterFlujo)) &&
                (!this.filterVolumen || this._multiContains(m.Capacidad_Sugerida__c, this.filterVolumen)) &&
                (!this.filterLeche || this._multiContains(m.Tipo_de_Leche__c, this.filterLeche))
            ))
        );
        return this._getValidOptions(this.metodologiasBase, machines, 'Metodologia__c');
    }

    get availableFlujos() {
        if (this.isGuidedMode && !this.filterMetodologia) return [];
        const machines = this.allMachines.filter(m =>
            (!this.filterNegocio || this._multiContains(m.Tipo_de_Negocio_Recomendado__c, this.filterNegocio)) &&
            (!this.filterMetodologia || this._multiContains(m.Metodologia__c, this.filterMetodologia)) &&
            (this.isGuidedMode ? true : (
                (!this.filterVolumen || this._multiContains(m.Capacidad_Sugerida__c, this.filterVolumen)) &&
                (!this.filterLeche || this._multiContains(m.Tipo_de_Leche__c, this.filterLeche))
            ))
        );
        const valid = this._getValidOptions(this.flujosBase, machines, 'Capacidad_Sugerida__c');
        return (this.isGuidedMode && this.filterMetodologia && valid.length === 0)
            ? this.flujosBase : valid;
    }

    get availableVolumenes() {
        if (this.isGuidedMode && !this.filterFlujo) return [];
        const machines = this.allMachines.filter(m =>
            (!this.filterNegocio || this._multiContains(m.Tipo_de_Negocio_Recomendado__c, this.filterNegocio)) &&
            (!this.filterMetodologia || this._multiContains(m.Metodologia__c, this.filterMetodologia)) &&
            (!this.filterFlujo || this._multiContains(m.Capacidad_Sugerida__c, this.filterFlujo)) &&
            (this.isGuidedMode ? true : (!this.filterLeche || this._multiContains(m.Tipo_de_Leche__c, this.filterLeche)))
        );
        const explicitVolumes = this._getValidOptions(this.volumenesBase, machines, 'Capacidad_Sugerida__c');
        if (explicitVolumes.length > 0) return explicitVolumes;
        const flowValues = new Set();
        machines.forEach(m => {
            this._splitMultiNormalized(m.Capacidad_Sugerida__c, 'Capacidad_Sugerida__c').forEach(v => flowValues.add(v));
        });
        return this.volumenesBase.filter(v => {
            const mappedFlow = this._volumeToFlow(v.value);
            return mappedFlow && flowValues.has(mappedFlow);
        });
    }

    get availableLeches() {
        if (this.isGuidedMode && !this.filterVolumen) return [];
        const machines = this.allMachines.filter(m =>
            (!this.filterNegocio || this._multiContains(m.Tipo_de_Negocio_Recomendado__c, this.filterNegocio)) &&
            (!this.filterMetodologia || this._multiContains(m.Metodologia__c, this.filterMetodologia)) &&
            (!this.filterFlujo || this._multiContains(m.Capacidad_Sugerida__c, this.filterFlujo)) &&
            (!this.filterVolumen || this._volumeMatches(m.Capacidad_Sugerida__c, this.filterVolumen))
        );
        return this._getValidOptions(this.tiposLeche, machines, 'Tipo_de_Leche__c');
    }

    _getValidOptions(baseOptions, currentMachines, fieldName) {
        const presentValues = new Set();
        currentMachines.forEach(m => {
            if (m[fieldName]) {
                this._splitMultiNormalized(m[fieldName], fieldName).forEach(v => presentValues.add(v));
            }
        });
        return baseOptions.filter(opt => presentValues.has(opt.value));
    }

    // --- Visibilidad de pasos en modo guiado ---
    get showStep2() { return this.filterNegocio; }
    get showStep3() { return this.filterMetodologia; }
    get showStep4() { return this.filterFlujo; }
    get showStep5() { return this.filterVolumen || (this.filterFlujo && this.availableVolumenes.length === 0); }

    get showResults() {
        if (this.isDynamicMode) return true;
        if (this.isMultiMode && this.filterNegocio) return true;
        return this.filterLeche || (this.showStep5 && this.availableLeches.length === 0);
    }

    // --- Handlers de Modo ---
    handleModeChange(event) {
        this._viewMode = event.target.dataset.mode;
        this.clearFilters();
    }

    // Handler para la pregunta "Seleccionar Máquina / Solicitud especial" en guiado.
    // El filtro guiado es de selección única siempre: el multi-selección con edición
    // de precio/cantidad queda reservado exclusivamente a "Desplegar filtros dinámicos"
    // (Comodato Admin) — por eso nunca se toca allowMultiSelect acá.
    handleMultiAnswer(event) {
        this.multiAnswer = event.target.value;
        if (this.multiAnswer === 'maquina' && this.esSolicitudEspecial) {
            this.esSolicitudEspecial = false;
            this.dispatchEvent(new FlowAttributeChangeEvent('esSolicitudEspecial', false));
        } else if (this.multiAnswer === 'especial') {
            this.esSolicitudEspecial = true;
            this.dispatchEvent(new FlowAttributeChangeEvent('esSolicitudEspecial', true));
        }
    }

    // Handler para el texto libre de "Solicitud especial"
    handleSolicitudEspecialChange(event) {
        this.solicitudEspecialTexto = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('solicitudEspecialTexto', this.solicitudEspecialTexto));
    }

    /**
     * Validación llamada automáticamente por el runtime del Screen Flow al presionar
     * "Siguiente". Solo bloquea el avance en el paso de "Solicitud especial": el resto
     * de los modos (single, multi, filtros) no se ven afectados.
     */
    @api
    validate() {
        if (this.esSolicitudEspecial && (!this.solicitudEspecialTexto || !this.solicitudEspecialTexto.trim())) {
            return {
                isValid: false,
                errorMessage: 'Describe tu solicitud antes de continuar.'
            };
        }
        return { isValid: true };
    }

    // --- Handlers de Filtros ---
    handleTipoNegocioChange(event) {
        this.filterNegocio = event.target.value;
        if (this.isGuidedMode) {
            this.filterMetodologia = '';
            this.filterFlujo = '';
            this.filterVolumen = '';
        }
        this._applyFilters();
    }

    handleMetodologiaChange(event) {
        this.filterMetodologia = event.target.value;
        if (this.isGuidedMode) {
            this.filterFlujo = '';
            this.filterVolumen = '';
        }
        this._applyFilters();
    }

    handleFlujoChange(event) {
        this.filterFlujo = event.target.value;
        if (this.isGuidedMode) {
            this.filterVolumen = '';
        }
        this._applyFilters();
    }

    handleVolumenChange(event) {
        this.filterVolumen = event.target.value;
        if (this.isGuidedMode) {
            this.filterLeche = '';
        }
        this._applyFilters();
    }

    handleTipoLecheChange(event) {
        this.filterLeche = event.target.value;
        this._applyFilters();
    }

    handleSearchChange(event) {
        this.filterSearch = event.target.value;
        this._applyFilters();
    }

    // --- Aplicación de Filtros Principal ---
    _applyFilters() {
        const selectedId = this.selectedMachine?.Id;
        const multiIds = new Set(this.selectedMachinesList.map(m => m.Id));
        this.filteredMachines = this.allMachines
            .filter(m => {
                const negocioOk    = !this.filterNegocio    || this._multiContains(m.Tipo_de_Negocio_Recomendado__c, this.filterNegocio);
                const metodOk      = !this.filterMetodologia || this._multiContains(m.Metodologia__c, this.filterMetodologia);
                const flujoOk      = !this.filterFlujo      || this._multiContains(m.Capacidad_Sugerida__c, this.filterFlujo);
                const volumenOk    = !this.filterVolumen    || this._volumeMatches(m.Capacidad_Sugerida__c, this.filterVolumen);
                const lecheOk      = !this.filterLeche      || this._multiContains(m.Tipo_de_Leche__c, this.filterLeche);
                const searchOk     = !this.filterSearch     || m.Name.toLowerCase().includes(this.filterSearch.toLowerCase());
                return negocioOk && metodOk && flujoOk && volumenOk && lecheOk && searchOk;
            })
            .map(m => ({
                ...m,
                isSelected: this.isMultiMode ? multiIds.has(m.Id) : m.Id === selectedId,
                cardClass: (this.isMultiMode ? multiIds.has(m.Id) : m.Id === selectedId) ? 'machine-card selected' : 'machine-card',
                thumbnailHtml: this._extractFirstImageTagStyled(m.Imagen_Propuesta__c)
            }));
    }

    _multiContains(fieldValue, searchValue) {
        if (!fieldValue) return false;
        return this._splitMultiNormalized(fieldValue).includes(searchValue);
    }

    _volumeMatches(capacidadFieldValue, selectedVolume) {
        if (!capacidadFieldValue || !selectedVolume) return false;
        const tokens = this._splitMultiNormalized(capacidadFieldValue, 'Capacidad_Sugerida__c');
        if (tokens.includes(selectedVolume)) return true;
        const mappedFlow = this._volumeToFlow(selectedVolume);
        return mappedFlow ? tokens.includes(mappedFlow) : false;
    }

    _volumeToFlow(volumeValue) {
        const map = {
            X14: 'Baja', X20: 'Baja', X34: 'Baja', X40: 'Baja',
            X75: 'Medio', X96: 'Medio', X100: 'Medio',
            X150: 'Alta'
        };
        return map[volumeValue] || null;
    }

    _splitMultiNormalized(fieldValue, fieldName = null) {
        if (!fieldValue) return [];
        return fieldValue.split(';').map(v => this._normalizeToken(v, fieldName)).filter(Boolean);
    }

    _normalizeToken(rawValue, fieldName = null) {
        if (!rawValue) return '';
        const value = rawValue.trim();
        if (fieldName === 'Capacidad_Sugerida__c' || fieldName === null) {
            const upper = value.toUpperCase();
            if (upper === 'BAJO') return 'Baja';
            if (upper === 'MEDIO') return 'Medio';
            if (upper === 'ALTO') return 'Alta';
            if (upper === 'BAJA') return 'Baja';
            if (upper === 'ALTA') return 'Alta';
        }
        return value;
    }

    // --- Selección de máquina ---
    handleSelectMachine(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this._toggleOrSelectMachine(id, name);
    }

    // --- Popup "Ver detalle" ---
    handleVerDetalle(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.selectedDetailMachine = this.allMachines.find(m => m.Id === id) || null;
    }

    closeDetalle() {
        this.selectedDetailMachine = null;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleAgregarDesdeDetalle() {
        if (!this.selectedDetailMachine) return;
        this._toggleOrSelectMachine(this.selectedDetailMachine.Id, this.selectedDetailMachine.Name);
        this.closeDetalle();
    }

    _toggleOrSelectMachine(id, name) {
        if (this.isMultiMode) {
            // Multi-selección: toggle (agregar o quitar)
            const existing = this.selectedMachinesList.find(m => m.Id === id);
            if (existing) {
                // Ya está seleccionada → deseleccionar
                this.selectedMachinesList = this.selectedMachinesList.filter(m => m.Id !== id);
            } else {
                // No está → agregar
                this.selectedMachinesList = [...this.selectedMachinesList, { Id: id, Name: name, quantity: 1 }];
            }
            this._updateMultiOutput();
        } else {
            // Selección única (comportamiento original)
            this.selectedMachine = this.allMachines.find(m => m.Id === id);
            this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineId', id));
            this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineName', name));
        }
        this._applyFilters();
    }

    // --- Helpers de parsing para miniaturas y el popup de detalle ---
    //
    // Imagen_Propuesta__c es un campo Rich Text: las imágenes se sirven vía el
    // servlet rtaImage, que solo resuelve la sesión/dominio correctamente cuando
    // se renderiza a través de lightning-formatted-rich-text (el mismo mecanismo
    // que usa cualquier campo Rich Text nativo en un Lightning Record Page). Un
    // <img src> crudo con esa URL no comparte esa sesión y se ve como imagen rota.
    // Por eso se inyecta el estilo de tamaño directo en el HTML y se renderiza
    // siempre con ese componente, nunca con <img> directo.
    _capImageStyle(imgTag, styleValue) {
        if (/style\s*=/i.test(imgTag)) {
            return imgTag.replace(/style\s*=\s*"([^"]*)"/i, (m, existing) => `style="${existing};${styleValue}"`);
        }
        return imgTag.replace(/<img/i, `<img style="${styleValue}"`);
    }

    // Miniatura de la tarjeta: solo la primera imagen, recortada a un cuadrado uniforme.
    _extractFirstImageTagStyled(html) {
        if (!html) return null;
        const match = /<img[^>]*>/i.exec(html);
        if (!match) return null;
        return this._capImageStyle(match[0], 'width:100%;height:100%;object-fit:cover;display:block;');
    }

    // Popup de detalle: todas las imágenes embebidas (a veces cargan 2), a tamaño natural acotado.
    _capAllImagesInHtml(html) {
        if (!html) return null;
        if (!/<img/i.test(html)) return null;
        return html.replace(/<img[^>]*>/gi, (tag) =>
            this._capImageStyle(tag, 'max-width:100%;height:auto;display:block;margin:0 auto 10px auto;border-radius:8px;')
        );
    }

    _toChips(value) {
        if (!value) return [];
        return value
            .split(';')
            .map((v) => v.trim())
            .filter(Boolean)
            .map((v, i) => ({ key: `${v}-${i}`, label: v }));
    }

    handleMultiQuantityChange(event) {
        const id = event.currentTarget.dataset.id;
        const qty = parseInt(event.target.value, 10);
        if (qty < 1) return;
        this.selectedMachinesList = this.selectedMachinesList.map(m =>
            m.Id === id ? { ...m, quantity: qty } : m
        );
        this._updateMultiOutput();
    }

    handleRemoveMultiMachine(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedMachinesList = this.selectedMachinesList.filter(m => m.Id !== id);
        this._updateMultiOutput();
        this._applyFilters();
    }

    /**
     * Repone los equipos ya elegidos cuando el usuario vuelve atras en el flujo.
     *
     * Al navegar, el componente se monta de nuevo y selectedMachinesList arranca vacia. El
     * Flow conserva lo elegido en machineSelectionsJson, asi que se reconstruye desde ahi.
     * Se ejecuta despues de cargar allMachines porque el JSON solo guarda id y cantidad:
     * el nombre se resuelve contra el catalogo.
     */
    _restaurarSeleccionMulti() {
        if (this.selectedMachinesList.length > 0) return;
        if (!this.machineSelectionsJson || this.machineSelectionsJson === '[]') return;
        try {
            const previas = JSON.parse(this.machineSelectionsJson);
            if (!Array.isArray(previas) || !previas.length) return;
            const restauradas = [];
            previas.forEach((sel) => {
                const maquina = this.allMachines.find((m) => m.Id === sel.machineId);
                if (maquina) {
                    restauradas.push({ Id: maquina.Id, Name: maquina.Name, quantity: sel.quantity || 1 });
                }
            });
            if (restauradas.length) {
                this.selectedMachinesList = restauradas;
                // Si habia seleccion multi, el modo multi tiene que quedar activo.
                this.allowMultiSelect = true;
            }
        } catch (e) {
            // JSON ilegible: se parte sin seleccion previa en vez de romper la pantalla.
        }
    }

    _updateMultiOutput() {
        const json = JSON.stringify(this.selectedMachinesList.map(m => ({
            machineId: m.Id,
            quantity: m.quantity
        })));
        this.machineSelectionsJson = json;
        this.dispatchEvent(new FlowAttributeChangeEvent('machineSelectionsJson', json));
        // En modo multi, limpiar selectedMachineId para que el flow no cree partida duplicada
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineId', null));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineName', null));
    }

    clearSelection() {
        this.selectedMachine = null;
        this.selectedMachinesList = [];
        this._applyFilters();
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineId', null));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineName', null));
        this.dispatchEvent(new FlowAttributeChangeEvent('machineSelectionsJson', '[]'));
    }

    clearFilters() {
        this.filterNegocio = '';
        this.filterMetodologia = '';
        this.filterFlujo = '';
        this.filterVolumen = '';
        this.filterLeche = '';
        this.filterSearch = '';
        // NO resetear multiAnswer para no perder la elección
        this.template.querySelectorAll('select').forEach(s => { s.value = ''; });
        const input = this.template.querySelector('input[type="text"]');
        if (input) input.value = '';
        this._applyFilters();
    }

    get noResults() {
        return !this.isLoading && this.filteredMachines.length === 0 && this.showResults;
    }
}