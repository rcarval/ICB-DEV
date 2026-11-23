import { LightningElement, track, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getMachines from '@salesforce/apex/MachineSelectorController.getMachines';

export default class DynamicMachineSelector extends LightningElement {
    // --- Outputs para el Flow ---
    @api selectedMachineId;
    @api selectedMachineName;
    @api allowDynamicFilters = false;
    @api initialBusinessFilter = '';
    @api pricebookId = '';
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
    @track isLoading = true;

    @track _viewMode = 'dynamic';
    
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

    // --- Wire: carga máquinas desde Apex ---
    @wire(getMachines, { pricebookId: '$pricebookId' })
    wiredMachines({ data, error }) {
        if (data) {
            this.allMachines = data;
            if (this.initialBusinessFilter) {
                this.filterNegocio = this.initialBusinessFilter;
            }
            const restoreId = this._preSelectedMachineId || this.selectedMachineId;
            if (restoreId) {
                this.selectedMachine = this.allMachines.find(m => m.Id === restoreId) || null;
            }
            this._applyFilters();
            this.isLoading = false;
        } else if (error) {
            console.error('Error cargando máquinas:', error);
            this.isLoading = false;
        }
    }

    // --- Getters de Modo ---
    // Reactivos: se recalculan cada vez que allowDynamicFilters o _viewMode cambian
    get isDynamicMode() { return this.allowDynamicFilters && this._viewMode === 'dynamic'; }
    get isGuidedMode()  { return !this.allowDynamicFilters || this._viewMode === 'guided'; }
    get dynamicClass()  { return this.isDynamicMode ? 'mode-btn active' : 'mode-btn'; }
    get guidedClass()   { return this.isGuidedMode  ? 'mode-btn active' : 'mode-btn'; }

    // --- Lógica de Filtros Interdependientes (Guided) ---
    
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
        // Fallback UX: si la data está incompleta para la metodología elegida,
        // evita combo vacío para no bloquear al usuario.
        return (this.isGuidedMode && this.filterMetodologia && valid.length === 0)
            ? this.flujosBase
            : valid;
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
        if (explicitVolumes.length > 0) {
            return explicitVolumes;
        }

        // Fallback: si la data ya está normalizada por flujo (Baja/Medio/Alta)
        // y no trae tokens X##, construimos volúmenes disponibles por equivalencia.
        const flowValues = new Set();
        machines.forEach(m => {
            this._splitMultiNormalized(m.Capacidad_Sugerida__c, 'Capacidad_Sugerida__c').forEach(v => flowValues.add(v));
        });

        const mapped = this.volumenesBase.filter(v => {
            const mappedFlow = this._volumeToFlow(v.value);
            return mappedFlow && flowValues.has(mappedFlow);
        });

        return mapped;
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

    // Filtra las opciones de un combo si existen en el set de máquinas actual
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
        return this.filterLeche || (this.showStep5 && this.availableLeches.length === 0);
    }

    // --- Handlers de Modo ---
    handleModeChange(event) {
        this._viewMode = event.target.dataset.mode;
        this.clearFilters();
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
                isSelected: m.Id === selectedId,
                cardClass: m.Id === selectedId ? 'machine-card selected' : 'machine-card'
            }));
    }

    _multiContains(fieldValue, searchValue) {
        if (!fieldValue) return false;
        return this._splitMultiNormalized(fieldValue).includes(searchValue);
    }

    _volumeMatches(capacidadFieldValue, selectedVolume) {
        if (!capacidadFieldValue || !selectedVolume) return false;

        const tokens = this._splitMultiNormalized(capacidadFieldValue, 'Capacidad_Sugerida__c');

        // Caso clásico: el registro trae X## explícito.
        if (tokens.includes(selectedVolume)) return true;

        // Caso normalizado: el registro trae solo Baja/Medio/Alta.
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
        return fieldValue
            .split(';')
            .map(v => this._normalizeToken(v, fieldName))
            .filter(Boolean);
    }

    _normalizeToken(rawValue, fieldName = null) {
        if (!rawValue) return '';
        const value = rawValue.trim();

        // Normalización defensiva para flujo (legacy en mayúsculas)
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
        this.selectedMachine = this.allMachines.find(m => m.Id === id);
        this._applyFilters();
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineId', id));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineName', name));
    }

    clearSelection() {
        this.selectedMachine = null;
        this._applyFilters();
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineId', null));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedMachineName', null));
    }

    clearFilters() {
        this.filterNegocio = '';
        this.filterMetodologia = '';
        this.filterFlujo = '';
        this.filterVolumen = '';
        this.filterLeche = '';
        this.filterSearch = '';
        this.template.querySelectorAll('select').forEach(s => s.value = '');
        const input = this.template.querySelector('input');
        if (input) input.value = '';
        this._applyFilters();
    }

    get noResults() {
        return !this.isLoading && this.filteredMachines.length === 0 && this.showResults;
    }
}