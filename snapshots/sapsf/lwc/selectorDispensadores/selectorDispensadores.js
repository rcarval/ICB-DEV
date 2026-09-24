import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import obtenerDispensadores from '@salesforce/apex/SelectorDispensadoresController.obtenerDispensadores';

/**
 * Selector de dispensadores para el flujo de propuesta de Comodato.
 *
 * Componente propio, separado del selector de cafe: ese proceso esta en produccion y no debe
 * verse afectado por ningun cambio de aqui.
 *
 * El enfoque es distinto al de cafe. Alli el asesor elige la maquina y los insumos quedan
 * implicitos. Aqui la pregunta llega al reves --el cliente quiere ofrecer ketchup y de ahi se
 * deduce el equipo-- asi que cada dispensador muestra los insumos que trae y la busqueda
 * tambien mira dentro de ellos.
 *
 * Emite machineSelectionsJson en el mismo formato que consume el resto del flujo, para que la
 * propuesta, el ajuste excepcional, el PDF y el contrato funcionen sin cambios.
 */
export default class SelectorDispensadores extends LightningElement {
    /** Lista de precios del flujo. Filtra los equipos disponibles. */
    @api pricebookId;

    /**
     * Entrada y salida: [{machineId, quantity}].
     * Bidireccional a proposito, para que la seleccion no se pierda al navegar hacia atras.
     */
    @api machineSelectionsJson = '[]';

    dispensadores = [];
    seleccionados = [];       // [{id, nombre, cantidad}]
    isLoading = true;
    errorMessage = '';
    termino = '';
    // Se muestran todos por defecto, incluidos los que aun no tienen insumos cargados: la
    // tarjeta avisa cual esta sin configurar. Esconderlos dejaria la pantalla en blanco sin
    // explicar por que.
    soloConfigurados = false;

    _cargado = false;

    @wire(obtenerDispensadores, { pricebookId: '$pricebookId' })
    recibirDispensadores({ data, error }) {
        if (data) {
            this.dispensadores = data;
            this.restaurarSeleccion();
            this.isLoading = false;
            this._cargado = true;
        } else if (error) {
            this.errorMessage = this.extraerMensaje(error);
            this.isLoading = false;
        }
    }

    /**
     * Repone lo elegido cuando el usuario vuelve atras en el flujo. El JSON guarda solo id y
     * cantidad, asi que el nombre se resuelve contra el catalogo ya cargado.
     */
    restaurarSeleccion() {
        if (this._cargado || this.seleccionados.length) return;
        if (!this.machineSelectionsJson || this.machineSelectionsJson === '[]') return;
        try {
            const previas = JSON.parse(this.machineSelectionsJson);
            if (!Array.isArray(previas)) return;
            const repuestas = [];
            previas.forEach((sel) => {
                const d = this.dispensadores.find((x) => x.id === sel.machineId);
                if (d) {
                    repuestas.push({ id: d.id, nombre: d.nombre, cantidad: sel.quantity || 1 });
                }
            });
            if (repuestas.length) this.seleccionados = repuestas;
        } catch (e) {
            // JSON ilegible: se parte sin seleccion previa en vez de romper la pantalla.
        }
    }

    // ---------- estado derivado ----------

    get hayError() {
        return !!this.errorMessage;
    }

    get haySeleccion() {
        return this.seleccionados.length > 0;
    }

    get resumenSeleccion() {
        const equipos = this.seleccionados.length;
        const unidades = this.seleccionados.reduce((s, x) => s + Number(x.cantidad || 0), 0);
        return `${equipos} ${equipos === 1 ? 'equipo' : 'equipos'} · ${unidades} ${unidades === 1 ? 'unidad' : 'unidades'}`;
    }

    /** Lista visible: aplica búsqueda por nombre o insumo, y el filtro de configurados. */
    get visibles() {
        const t = (this.termino || '').trim().toLowerCase();
        const elegidos = new Set(this.seleccionados.map((s) => s.id));

        return this.dispensadores
            .filter((d) => (this.soloConfigurados ? d.configurado : true))
            .filter((d) => (t ? (d.textoBusqueda || '').includes(t) : true))
            .map((d) => {
                const elegido = elegidos.has(d.id);
                return {
                    ...d,
                    elegido,
                    clase: elegido ? 'tarjeta tarjeta_elegida' : 'tarjeta',
                    etiquetaBoton: elegido ? 'Quitar' : 'Agregar',
                    variante: elegido ? 'destructive-text' : 'brand-outline',
                    resumenInsumos: this.describirInsumos(d),
                    tieneInsumos: d.insumos && d.insumos.length > 0,
                    tieneAportes: d.aportes && d.aportes.length > 0,
                    tieneServicios: d.servicios && d.servicios.length > 0
                };
            });
    }

    get sinResultados() {
        return !this.isLoading && this.visibles.length === 0;
    }

    get mensajeVacio() {
        if (this.termino) {
            return `Ningún dispensador coincide con "${this.termino}".`;
        }
        return this.soloConfigurados
            ? 'Todos los dispensadores están sin configuración de comodato. Usa el botón para verlos.'
            : 'No hay dispensadores disponibles en esta lista de precios.';
    }

    get totalSinConfigurar() {
        return this.dispensadores.filter((d) => !d.configurado).length;
    }

    get hayOcultos() {
        return this.totalSinConfigurar > 0;
    }

    /** El boton alterna: esconder los equipos sin insumos, o volver a mostrarlos. */
    get textoOcultos() {
        const n = this.totalSinConfigurar;
        const equipos = `${n} sin configuración`;
        return this.soloConfigurados ? `Mostrar ${equipos}` : `Ocultar ${equipos}`;
    }

    describirInsumos(d) {
        if (!d.insumos || !d.insumos.length) return 'Sin insumos configurados';
        return d.insumos.map((i) => i.nombre).join(' · ');
    }

    // ---------- acciones ----------

    handleBuscar(event) {
        this.termino = event.target.value;
    }

    handleToggleOcultos() {
        this.soloConfigurados = !this.soloConfigurados;
    }

    handleAgregar(event) {
        const id = event.currentTarget.dataset.id;
        const existente = this.seleccionados.find((s) => s.id === id);
        if (existente) {
            this.seleccionados = this.seleccionados.filter((s) => s.id !== id);
        } else {
            const d = this.dispensadores.find((x) => x.id === id);
            if (!d) return;
            this.seleccionados = [...this.seleccionados, { id: d.id, nombre: d.nombre, cantidad: 1 }];
        }
        this.publicar();
    }

    handleCantidad(event) {
        const id = event.currentTarget.dataset.id;
        const valor = parseInt(event.target.value, 10);
        this.seleccionados = this.seleccionados.map((s) =>
            s.id === id ? { ...s, cantidad: valor > 0 ? valor : 1 } : s
        );
        this.publicar();
    }

    handleQuitar(event) {
        const id = event.currentTarget.dataset.id;
        this.seleccionados = this.seleccionados.filter((s) => s.id !== id);
        this.publicar();
    }

    handleLimpiar() {
        this.seleccionados = [];
        this.termino = '';
        this.publicar();
    }

    /** Mismo formato que consume el resto del flujo: [{machineId, quantity}]. */
    publicar() {
        const json = JSON.stringify(
            this.seleccionados.map((s) => ({ machineId: s.id, quantity: s.cantidad }))
        );
        this.machineSelectionsJson = json;
        this.dispatchEvent(new FlowAttributeChangeEvent('machineSelectionsJson', json));
    }

    extraerMensaje(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'No se pudieron cargar los dispensadores.';
    }
}