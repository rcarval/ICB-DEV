import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import obtenerLineasParaAjuste from '@salesforce/apex/AjustarValoresComodatoController.obtenerLineasParaAjuste';
import guardarAjuste from '@salesforce/apex/AjustarValoresComodatoController.guardarAjuste';
import revertirAjuste from '@salesforce/apex/AjustarValoresComodatoController.revertirAjuste';

const UNIDAD_OPTIONS = [
    { label: 'Kilos', value: 'Kilos' },
    { label: 'Cajas', value: 'Cajas' },
    { label: 'Unidades', value: 'Unidades' },
    { label: 'Litros', value: 'Litros' }
];

/**
 * Paso EXCEPCIONAL de ajuste de valores Comodato (cantidad, unidad, precio) para una
 * Quote puntual. Solo se muestra si el usuario tiene el Custom Permission
 * 'Ajustar_Valores_Comodato' (hoy asignado unicamente via el Permission Set ADMIN_COMODATO).
 *
 * Comodato__c (configuracion maestra por maquina) nunca se modifica desde aqui: cada
 * cambio se guarda como un Comodato_Override__c ligado a esta Quote, con motivo
 * obligatorio, y queda transparentado en la propuesta y en el contrato de firma digital.
 */
export default class AjustarValoresComodato extends LightningElement {
    @api machineIds = [];              // Ids de Product2 (uso programático directo)
    @api machineSelectionsJson;        // String JSON [{machineId, quantity}] tal como lo emite
                                        // c:selectorMultiMaquina / consume GenerarPDFComodatoMultiAction.
                                        // Si viene poblado, tiene prioridad sobre machineIds.
    @api machineIdUnico;     // Id de la unica maquina cuando el flujo va en modo guiado/single,
                             // donde machineSelectionsJson viene vacio.
    @api quoteId;            // Quote ya creada. Si viene vacia, el componente trabaja EN MEMORIA.
    @api recordId;           // fallback si el flow pasa Opportunity/Quote como recordId

    // Salida al Flow: ajustes capturados en memoria, como JSON.
    // [{comodatoId, cantidadAjustada, unidadAjustada, precioAjustado, motivo}]
    // El Flow los persiste como Comodato_Override__c DESPUES de crear la Quote.
    @api ajustesJson = '[]';

    // Ajustes pendientes cuando todavia no existe la Quote.
    ajustesEnMemoria = [];

    // Ids de maquina cuyo detalle esta desplegado. Con un solo equipo se abre solo;
    // con varios se parte todo contraido para no obligar a hacer scroll.
    maquinasAbiertas = [];

    unidadOptions = UNIDAD_OPTIONS;
    lineas = [];
    isLoading = true;
    errorMessage = '';

    // Modal de edicion de una linea puntual
    lineaEnEdicion = null;
    draftCantidad;
    draftUnidad;
    draftPrecio;
    draftMotivo = '';
    isSaving = false;

    connectedCallback() {
        this.restaurarAjustesPrevios();
        this.cargarLineas();
    }

    /**
     * Al navegar hacia atras y volver, el componente se monta de nuevo y su memoria arranca
     * vacia. El Flow conserva lo ajustado en ajustesJson, asi que se recupera de ahi para
     * que el usuario no pierda el trabajo por revisar un paso anterior.
     */
    restaurarAjustesPrevios() {
        if (!this.ajustesJson) return;
        try {
            const previos = JSON.parse(this.ajustesJson);
            if (Array.isArray(previos) && previos.length) {
                this.ajustesEnMemoria = previos;
            }
        } catch (e) {
            // JSON ilegible: se parte sin ajustes previos en vez de romper la pantalla.
        }
    }

    /**
     * Sin Quote no se puede crear un Comodato_Override__c (Quote__c es obligatorio), y
     * ademas no queremos escribir nada hasta que el usuario confirme la propuesta. En ese
     * caso los ajustes se mantienen en memoria y viajan al Flow por ajustesJson.
     */
    get modoMemoria() {
        return !this.quoteId;
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get hasLineas() {
        return this.lineas && this.lineas.length > 0;
    }

    get hayVariosEquipos() {
        return this.grupos.length > 1;
    }

    get resumenGeneral() {
        const equipos = this.grupos.length;
        const total = this.lineas.length;
        const ajustadas = this.lineas.filter((l) => l.tieneAjuste).length;
        const partes = [
            equipos + (equipos === 1 ? ' equipo' : ' equipos'),
            total + (total === 1 ? ' linea' : ' lineas')
        ];
        if (ajustadas > 0) {
            partes.push(ajustadas + (ajustadas === 1 ? ' ajustada' : ' ajustadas'));
        }
        return partes.join(' \u00b7 ');
    }

    /** Referencia de lo que traia la linea antes del ajuste, para comparar al editar. */
    get resumenOriginal() {
        if (!this.lineaEnEdicion) return '';
        const l = this.lineaEnEdicion;
        return this.formatCantidad(l.cantidadOriginal, l.unidadOriginal) + ' · ' + this.formatPrecio(l.precioOriginal);
    }

    get tituloLineaEnEdicion() {
        if (!this.lineaEnEdicion) return '';
        return this.lineaEnEdicion.maquinaNombre + ' \u2014 ' + this.lineaEnEdicion.productoAsociadoNombre;
    }

    /** Lineas agrupadas por maquina: evita repetir el nombre en cada fila. */
    get grupos() {
        const porMaquina = new Map();
        (this.lineas || []).forEach((l) => {
            if (!porMaquina.has(l.maquinaId)) {
                porMaquina.set(l.maquinaId, { maquinaId: l.maquinaId, maquinaNombre: l.maquinaNombre, lineas: [] });
            }
            porMaquina.get(l.maquinaId).lineas.push(l);
        });

        return [...porMaquina.values()].map((g) => {
            const ajustadas = g.lineas.filter((l) => l.tieneAjuste).length;
            const abierto = this.maquinasAbiertas.includes(g.maquinaId);
            return {
                ...g,
                abierto,
                iconoToggle: abierto ? 'utility:chevrondown' : 'utility:chevronright',
                resumen: g.lineas.length + (g.lineas.length === 1 ? ' linea' : ' lineas'),
                tieneAjustes: ajustadas > 0,
                etiquetaAjustes: ajustadas + (ajustadas === 1 ? ' AJUSTADA' : ' AJUSTADAS')
            };
        });
    }

    handleToggleGrupo(event) {
        const id = event.currentTarget.dataset.maquina;
        this.maquinasAbiertas = this.maquinasAbiertas.includes(id)
            ? this.maquinasAbiertas.filter((m) => m !== id)
            : this.maquinasAbiertas.concat(id);
    }

    handleExpandirTodo() {
        this.maquinasAbiertas = this.grupos.map((g) => g.maquinaId);
    }

    handleContraerTodo() {
        this.maquinasAbiertas = [];
    }

    get modalAbierto() {
        return this.lineaEnEdicion != null;
    }

    /**
     * El flujo tiene dos caminos: multi-seleccion (machineSelectionsJson con varias maquinas)
     * y guiado/single (una sola maquina en machineIdUnico). Hay que soportar los dos.
     */
    get machineIdsResueltos() {
        if (this.machineSelectionsJson) {
            try {
                const selections = JSON.parse(this.machineSelectionsJson) || [];
                const ids = selections.map((s) => s.machineId).filter(Boolean);
                if (ids.length) return ids;
            } catch (e) {
                // formato inesperado: se cae a los otros origenes
            }
        }
        if (this.machineIdUnico) {
            return [this.machineIdUnico];
        }
        return this.machineIds && this.machineIds.length ? this.machineIds : [];
    }

    cargarLineas() {
        this.isLoading = true;
        const ids = this.machineIdsResueltos;
        obtenerLineasParaAjuste({ maquinaIds: ids, quoteId: this.quoteId })
            .then((result) => {
                this.lineas = (result || []).map((l) => {
                    const linea = { ...l };
                    const pendiente = this.ajustesEnMemoria.find((a) => a.comodatoId === l.comodatoId);
                    if (pendiente) {
                        // Refleja el ajuste todavia no persistido sobre los valores originales.
                        if (pendiente.cantidadAjustada !== null && pendiente.cantidadAjustada !== undefined) {
                            linea.cantidadEfectiva = pendiente.cantidadAjustada;
                        }
                        if (pendiente.unidadAjustada) {
                            linea.unidadEfectiva = pendiente.unidadAjustada;
                        }
                        if (pendiente.precioAjustado !== null && pendiente.precioAjustado !== undefined) {
                            linea.precioEfectivo = pendiente.precioAjustado;
                        }
                        linea.tieneAjuste = true;
                        linea.motivoAjuste = pendiente.motivo;
                    }
                    const cantidadFueAjustada =
                        linea.tieneAjuste && linea.cantidadEfectiva !== linea.cantidadOriginal;
                    const precioFueAjustado =
                        linea.tieneAjuste && linea.precioEfectivo !== linea.precioOriginal;
                    return {
                        ...linea,
                        key: linea.comodatoId,
                        motivoKey: linea.comodatoId + '-motivo',
                        cantidadLabel: this.formatCantidad(linea.cantidadEfectiva, linea.unidadEfectiva),
                        precioLabel: this.formatPrecio(linea.precioEfectivo),
                        cantidadFueAjustada,
                        precioFueAjustado,
                        cantidadOriginalLabel: this.formatCantidad(linea.cantidadOriginal, linea.unidadOriginal),
                        precioOriginalLabel: this.formatPrecio(linea.precioOriginal),
                        claseFila: linea.tieneAjuste ? 'fila-ajustada' : '',
                        // El motivo es opcional: sin texto no se dibuja la fila, para no
                        // dejar un "Motivo:" vacio colgando bajo cada linea ajustada.
                        tieneMotivo: !!(linea.tieneAjuste && linea.motivoAjuste && linea.motivoAjuste.trim()),
                        etiquetaBoton: linea.tieneAjuste ? 'Editar' : 'Ajustar'
                    };
                });
                this.abrirGrupoPorDefecto();
                this.isLoading = false;
            })
            .catch((error) => {
                this.errorMessage = this.extraerMensajeError(error);
                this.isLoading = false;
            });
    }

    /** Con un solo equipo no tiene sentido obligar a un clic extra: se abre solo. */
    abrirGrupoPorDefecto() {
        if (this.maquinasAbiertas.length > 0) return;
        const ids = [...new Set(this.lineas.map((l) => l.maquinaId))];
        if (ids.length === 1) {
            this.maquinasAbiertas = ids;
        }
    }

    formatCantidad(cantidad, unidad) {
        if (cantidad == null) return '—';
        return `${Math.round(cantidad)} ${unidad || ''}`.trim();
    }

    formatPrecio(precio) {
        if (precio == null) return '—';
        return '$' + Math.round(precio).toLocaleString('es-CL');
    }

    extraerMensajeError(error) {
        return (error && error.body && error.body.message) || 'Ocurrió un error inesperado.';
    }

    handleAjustarClick(event) {
        const key = event.currentTarget.dataset.key;
        const linea = this.lineas.find((l) => l.key === key);
        if (!linea) return;
        this.lineaEnEdicion = linea;
        this.draftCantidad = linea.cantidadEfectiva;
        this.draftUnidad = linea.unidadEfectiva;
        this.draftPrecio = linea.precioEfectivo;
        this.draftMotivo = linea.motivoAjuste || '';
    }

    publicarAjustes() {
        this.ajustesJson = JSON.stringify(this.ajustesEnMemoria);
        this.dispatchEvent(new FlowAttributeChangeEvent('ajustesJson', this.ajustesJson));
    }

    handleRevertirClick(event) {
        const key = event.currentTarget.dataset.key;
        const linea = this.lineas.find((l) => l.key === key);
        if (!linea) return;

        if (this.modoMemoria) {
            // Todavia no hay nada persistido: basta con descartar el ajuste pendiente.
            this.ajustesEnMemoria = this.ajustesEnMemoria.filter((a) => a.comodatoId !== linea.comodatoId);
            this.publicarAjustes();
            this.notificarCambio();
            this.cargarLineas();
            return;
        }

        if (!linea.overrideId) return;
        this.isSaving = true;
        revertirAjuste({ overrideId: linea.overrideId })
            .then(() => {
                this.isSaving = false;
                this.notificarCambio();
                this.cargarLineas();
            })
            .catch((error) => {
                this.isSaving = false;
                this.errorMessage = this.extraerMensajeError(error);
            });
    }

    handleCerrarModal() {
        this.lineaEnEdicion = null;
        this.draftMotivo = '';
    }

    handleDraftCantidadChange(event) {
        this.draftCantidad = event.target.value ? parseFloat(event.target.value) : null;
    }

    handleDraftUnidadChange(event) {
        this.draftUnidad = event.detail.value;
    }

    handleDraftPrecioChange(event) {
        this.draftPrecio = event.target.value ? parseFloat(event.target.value) : null;
    }

    handleDraftMotivoChange(event) {
        this.draftMotivo = event.target.value;
    }

    get puedeGuardar() {
        if (this.isSaving) return false;
        if (!this.lineaEnEdicion) return false;
        const cambioCantidad = this.draftCantidad !== this.lineaEnEdicion.cantidadOriginal;
        const cambioUnidad = this.draftUnidad !== this.lineaEnEdicion.unidadOriginal;
        const cambioPrecio = this.draftPrecio !== this.lineaEnEdicion.precioOriginal;
        return cambioCantidad || cambioUnidad || cambioPrecio;
    }

    get puedeGuardarDeshabilitado() {
        return !this.puedeGuardar;
    }

    handleGuardarAjuste() {
        if (!this.puedeGuardar) return;

        if (this.modoMemoria) {
            const ajuste = {
                comodatoId: this.lineaEnEdicion.comodatoId,
                cantidadAjustada: this.draftCantidad,
                unidadAjustada: this.draftUnidad,
                precioAjustado: this.draftPrecio,
                motivo: this.draftMotivo
            };
            this.ajustesEnMemoria = this.ajustesEnMemoria
                .filter((a) => a.comodatoId !== ajuste.comodatoId)
                .concat(ajuste);
            this.publicarAjustes();
            this.handleCerrarModal();
            this.notificarCambio();
            this.cargarLineas();
            return;
        }

        this.isSaving = true;
        guardarAjuste({
            comodatoId: this.lineaEnEdicion.comodatoId,
            quoteId: this.quoteId,
            cantidadAjustada: this.draftCantidad,
            unidadAjustada: this.draftUnidad,
            precioAjustado: this.draftPrecio,
            motivo: this.draftMotivo
        })
            .then(() => {
                this.isSaving = false;
                this.handleCerrarModal();
                this.notificarCambio();
                this.cargarLineas();
            })
            .catch((error) => {
                this.isSaving = false;
                this.errorMessage = this.extraerMensajeError(error);
            });
    }

    notificarCambio() {
        this.dispatchEvent(new CustomEvent('ajusteguardado'));
    }
}