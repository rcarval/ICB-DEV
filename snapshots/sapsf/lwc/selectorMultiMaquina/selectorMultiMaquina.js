import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import searchMachines from '@salesforce/apex/SelectorMultiMaquinaController.searchMachines';
import getMultiMachinePreviewHtml from '@salesforce/apex/ComodatoPropuestaMultiController.getMultiMachinePreviewHtml';

export default class SelectorMultiMaquina extends LightningElement {
    // Flow inputs
    @api tipoEquipo = ''; // 'Máquina Café' o 'Dispensador'
    @api isSingleMode = false;

    // Flow output
    @api machineSelectionsJson = '[]';

    // Internal state
    searchTerm = '';
    searchResults = [];
    selectedMachines = []; // [{machineId, machineName, quantity, key}]
    isSearching = false;
    previewHtml = '';
    isLoadingPreview = false;
    showPreview = false;
    _keyCounter = 0;

    get hasSelections() {
        return this.selectedMachines.length > 0;
    }

    get totalMachines() {
        return this.selectedMachines.reduce((sum, m) => sum + m.quantity, 0);
    }

    get selectionSummary() {
        if (this.selectedMachines.length === 0) return 'Ninguna máquina seleccionada';
        const items = this.selectedMachines.map(m =>
            m.quantity > 1 ? `${m.machineName} (x${m.quantity})` : m.machineName
        );
        return items.join(', ');
    }

    get searchPlaceholder() {
        return this.tipoEquipo === 'Dispensador'
            ? 'Buscar dispensador por nombre...'
            : 'Buscar máquina de café por nombre...';
    }

    get canAddMore() {
        if (this.isSingleMode) {
            return this.selectedMachines.length === 0;
        }
        return true;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        if (this.searchTerm.length >= 2) {
            this.doSearch();
        } else {
            this.searchResults = [];
        }
    }

    doSearch() {
        this.isSearching = true;
        searchMachines({ searchTerm: this.searchTerm, tipoEquipo: this.tipoEquipo })
            .then(results => {
                this.searchResults = results.map(r => ({
                    ...r,
                    isAlreadySelected: this.selectedMachines.some(s => s.machineId === r.Id)
                }));
                this.isSearching = false;
            })
            .catch(error => {
                console.error('Search error:', error);
                this.searchResults = [];
                this.isSearching = false;
            });
    }

    handleSelectMachine(event) {
        const machineId = event.currentTarget.dataset.id;
        const machineName = event.currentTarget.dataset.name;

        // Verificar si ya está seleccionada
        const existing = this.selectedMachines.find(m => m.machineId === machineId);
        if (existing) {
            // Incrementar cantidad
            this.selectedMachines = this.selectedMachines.map(m =>
                m.machineId === machineId ? { ...m, quantity: m.quantity + 1 } : m
            );
        } else {
            this._keyCounter++;
            this.selectedMachines = [...this.selectedMachines, {
                machineId,
                machineName,
                quantity: 1,
                key: 'sel-' + this._keyCounter
            }];
        }

        this.searchTerm = '';
        this.searchResults = [];
        this.updateFlowOutput();
        this.showPreview = false;
    }

    handleQuantityChange(event) {
        const key = event.currentTarget.dataset.key;
        const newQty = parseInt(event.target.value, 10);
        if (newQty < 1) return;

        this.selectedMachines = this.selectedMachines.map(m =>
            m.key === key ? { ...m, quantity: newQty } : m
        );
        this.updateFlowOutput();
        this.showPreview = false;
    }

    handleRemoveMachine(event) {
        const key = event.currentTarget.dataset.key;
        this.selectedMachines = this.selectedMachines.filter(m => m.key !== key);
        this.updateFlowOutput();
        this.showPreview = false;
    }

    handlePreview() {
        if (this.selectedMachines.length === 0) return;
        this.isLoadingPreview = true;
        this.showPreview = true;

        getMultiMachinePreviewHtml({ machineSelectionsJson: this.machineSelectionsJson })
            .then(html => {
                this.previewHtml = html;
                this.isLoadingPreview = false;
                this.renderPreview();
            })
            .catch(error => {
                this.previewHtml = '<div style="color:red;">Error al generar vista previa: ' + (error.body?.message || error.message) + '</div>';
                this.isLoadingPreview = false;
                this.renderPreview();
            });
    }

    renderPreview() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.template.querySelector('.preview-container');
            if (container) {
                container.innerHTML = this.previewHtml;
            }
        }, 0);
    }

    updateFlowOutput() {
        const selections = this.selectedMachines.map(m => ({
            machineId: m.machineId,
            quantity: m.quantity
        }));
        this.machineSelectionsJson = JSON.stringify(selections);

        // Notify flow of change
        const event = new FlowAttributeChangeEvent('machineSelectionsJson', this.machineSelectionsJson);
        this.dispatchEvent(event);
    }
}