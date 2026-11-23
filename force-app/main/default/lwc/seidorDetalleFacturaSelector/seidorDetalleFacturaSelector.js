import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import obtenerDetalles from '@salesforce/apex/seidor_DetalleFacturaSelector.obtenerDetalles';
import {
    TIPO_UM,
    CAMPOS_INGRESO,
    calcularCantidadUnidad,
    calcularReclamoFila,
    campoIngresado,
    campoPorUnidadMedida,
    redondear,
    tieneValor,
    tipoUMPorUnidadMedida
} from './calculos';

/** Columna de la fila que define el máximo (cantidad total) de cada sub-input. */
const COLUMNA_TOTAL = Object.freeze({ cajas: 'cantidad', kg: 'pesoNeto', unidades: 'cantidadUnidad' });

/**
 * Tabla de detalles de productos de factura para el flujo "Caso - Ingreso de Caso mejorado".
 * Reemplaza al componente c:datatable (ProductosDeLaFactura_1) en la pantalla
 * Informacion_de_Producto_de_Factura, manteniendo las mismas salidas outputSelectedRow /
 * outputSelectedRows, y agrega el ingreso de cantidades reclamadas por producto.
 */
export default class SeidorDetalleFacturaSelector extends LightningElement {
    // ---------- Entradas (Flow) ----------
    @api facturaId;
    @api caseId;
    @api accountId;
    @api sucursalId;
    @api etiquetaTabla = 'Detalles productos de la factura';
    @api seleccionRequerida = false;
    @api ingresarCantidades = false;
    /** Causa (Sub_Categoria__c) elegida en la pantalla 1. Informativo (contexto del reclamo). */
    @api subCategoria;
    /** Tipo de rechazo elegido en la pantalla 1 (solo Reclamo + Calidad). Informativo. */
    @api tipoRechazo;
    /** Entrada/salida: guarda la selección y cantidades para restaurarlas al volver a la pantalla. */
    @api estadoSeleccion;

    // ---------- Salidas (Flow) ----------
    @api outputSelectedRow;
    @api outputSelectedRows = [];
    @api numberOfRowsSelected = 0;
    @api tipoUMReclamo = '';
    @api cantidadKgReclamada = '0';
    @api cantidadCajasReclamada = 0;
    @api cantidadUnidadesReclamada = 0;
    @api cantidadReclamadaTotal = '0';
    @api valorNetoReclamado = '0';
    @api cantidadFacturadaReclamo = '0';
    @api detalleReclamoJson = '[]';

    filas = [];
    /** { [detalleId]: { kg, cajas, unidades } } — una entrada por fila seleccionada. */
    seleccion = {};
    terminoBusqueda = '';
    cargando = true;
    mensajeError;

    connectedCallback() {
        this.restaurarEstado();
        this.cargarDetalles();
    }

    // ------------------------------------------------------------------
    // Carga de datos
    // ------------------------------------------------------------------

    async cargarDetalles() {
        this.cargando = true;
        this.mensajeError = undefined;
        try {
            const res = await obtenerDetalles({
                caseId: this.caseId || null,
                facturaId: this.facturaId || null,
                accountId: this.accountId || null,
                sucursalId: this.sucursalId || null
            });
            this.filas = (res?.detalles || []).map((registro) => this.mapearFila(registro));
            const idsValidos = new Set(this.filas.map((f) => f.id));
            this.seleccion = Object.fromEntries(
                Object.entries(this.seleccion).filter(([id]) => idsValidos.has(id))
            );
        } catch (error) {
            this.filas = [];
            this.seleccion = {};
            this.mensajeError = error?.body?.message || error?.message || 'No fue posible obtener los detalles de la factura.';
        } finally {
            this.cargando = false;
            this.publicarSalidas();
        }
    }

    mapearFila(registro) {
        const cantidad = Number(registro.Cantidad__c) || 0;
        const conversionUM = Number(registro.Conversion_UM__c) || 0;
        const cantidadUnidad = tieneValor(registro.Cantidad_Unidad__c)
            ? Number(registro.Cantidad_Unidad__c)
            : calcularCantidadUnidad(cantidad, conversionUM);
        return {
            id: registro.Id,
            sku: registro.SKU__c,
            nombre: registro.Nombre_producto__c || registro.Product__r?.Name || registro.Descripcion__c,
            cantidad,
            pesoNeto: Number(registro.Peso_neto__c) || 0,
            conversionUM,
            cantidadUnidad,
            unidadMedida: registro.Unidad_de_Medida__c,
            tipoUMProducto: tipoUMPorUnidadMedida(registro.Unidad_de_Medida__c),
            campoUM: campoPorUnidadMedida(registro.Unidad_de_Medida__c),
            valorNeto: Number(registro.Valor_Neto__c) || 0,
            totalConRappel: Number(registro.Total_con_Rapel__c) || 0,
            registro
        };
    }

    restaurarEstado() {
        if (!this.estadoSeleccion) {
            return;
        }
        try {
            const estado = JSON.parse(this.estadoSeleccion);
            this.seleccion = estado && typeof estado === 'object' ? estado : {};
        } catch (e) {
            this.seleccion = {};
        }
    }

    // ------------------------------------------------------------------
    // Vista
    // ------------------------------------------------------------------

    get filasVista() {
        const termino = this.terminoBusqueda.trim().toLowerCase();
        return this.filas
            .filter(
                (f) =>
                    !termino ||
                    [f.sku, f.nombre, f.unidadMedida].some((v) => (v || '').toLowerCase().includes(termino))
            )
            .map((f) => this.construirVista(f));
    }

    construirVista(fila) {
        const estado = this.seleccion[fila.id];
        const seleccionada = !!estado;
        const calculo = seleccionada ? calcularReclamoFila(fila, estado) : null;
        // La UM del producto define el único sub-input habilitado (KG → Peso neto, Caja → Cantidad,
        // Unidad → Cantidad unidad). Si la UM no se reconoce, quedan los tres excluyentes entre sí.
        const campoUM = fila.campoUM;
        const usado = campoUM ? (tieneValor(estado?.[campoUM]) ? campoUM : '') : campoIngresado(estado);
        const bloqueado = (campo) => (campoUM ? campoUM !== campo : usado !== '' && usado !== campo);
        // "Cantidad total" copia el total de la fila al sub-input habilitado (el de la UM, o el ya usado
        // si la UM no se reconoce). Sin sub-input definido o con total 0 queda deshabilitado.
        const campoTotal = campoUM || usado;
        const maximoTotal = campoTotal ? fila[COLUMNA_TOTAL[campoTotal]] : 0;
        return {
            ...fila,
            seleccionada,
            mostrarSubFila: seleccionada && this.cantidadesHabilitadas,
            claveSubFila: `${fila.id}-reclamo`,
            kg: usado === 'kg' ? estado.kg : '',
            cajas: usado === 'cajas' ? estado.cajas : '',
            unidades: usado === 'unidades' ? estado.unidades : '',
            deshabilitarKg: fila.pesoNeto <= 0 || bloqueado('kg'),
            deshabilitarCajas: fila.cantidad <= 0 || bloqueado('cajas'),
            deshabilitarUnidades: fila.cantidadUnidad <= 0 || bloqueado('unidades'),
            cantidadTotal: !!estado?.total && !!campoTotal,
            deshabilitarCantidadTotal: !campoTotal || !(maximoTotal > 0),
            msgMaxKg: `No puede superar el peso neto de la fila (${fila.pesoNeto} KG).`,
            msgMaxCajas: `No puede superar la cantidad de la fila (${fila.cantidad}).`,
            msgMaxUnidades: `No puede superar la cantidad unidad de la fila (${fila.cantidadUnidad}).`,
            textoCalculo: this.textoCalculo(calculo && { ...calculo, tipoUMProducto: fila.tipoUMProducto }),
            valorReclamado: calculo?.valor ?? 0,
            claseFila: seleccionada ? 'slds-hint-parent slds-is-selected fila-seleccionada' : 'slds-hint-parent',
            etiquetaCheckbox: `Seleccionar ${fila.sku || fila.nombre || ''}`
        };
    }

    textoCalculo(calculo) {
        if (!calculo) {
            return '';
        }
        const tipo = calculo.tipoCalculo || calculo.tipoUMProducto;
        if (tipo === TIPO_UM.UNIDAD) {
            return 'UM Unidad: ingrese en Cantidad unidad (Valor neto / Cantidad unidad × unidades)';
        }
        if (tipo === TIPO_UM.KG) {
            return 'UM KG: ingrese en Peso neto (Total con rappel / Peso neto × KG)';
        }
        if (tipo === TIPO_UM.CAJA) {
            return 'UM Caja: ingrese en Cantidad (Total con rappel / Cantidad × cantidad)';
        }
        return 'UM no reconocida: ingrese un valor en una sola columna (Cantidad, Peso neto o Cantidad unidad).';
    }

    /**
     * Muestra la sub-fila de ingreso y la columna de valor reclamado.
     * Aplica a todos los casos (proceso normal y Rechazo parcial); solo depende de ingresarCantidades.
     */
    get cantidadesHabilitadas() {
        return this.ingresarCantidades === true || this.ingresarCantidades === 'true';
    }

    get seleccionadas() {
        return this.filas
            .filter((f) => this.seleccion[f.id])
            .map((f) => ({ fila: f, ...calcularReclamoFila(f, this.seleccion[f.id]) }));
    }

    get cantidadSeleccionadas() {
        return Object.keys(this.seleccion).length;
    }

    get hayFilas() {
        return this.filas.length > 0;
    }

    get sinResultadosBusqueda() {
        return this.hayFilas && this.filasVista.length === 0;
    }

    get mostrarVacio() {
        return !this.cargando && !this.mensajeError && !this.hayFilas;
    }

    get mostrarTabla() {
        return !this.cargando && !this.mensajeError && this.hayFilas;
    }

    get todasVisiblesSeleccionadas() {
        const visibles = this.filasVista;
        return visibles.length > 0 && visibles.every((f) => f.seleccionada);
    }

    get mostrarTotal() {
        return this.cantidadesHabilitadas && this.cantidadSeleccionadas > 0;
    }

    get totalReclamado() {
        return this.seleccionadas.reduce((acc, s) => acc + s.valor, 0);
    }

    get textoSeleccionados() {
        const n = this.cantidadSeleccionadas;
        return n === 1 ? '1 seleccionado' : `${n} seleccionados`;
    }

    // ------------------------------------------------------------------
    // Eventos
    // ------------------------------------------------------------------

    handleBusqueda(event) {
        this.terminoBusqueda = event.detail.value || '';
    }

    handleSeleccionFila(event) {
        const id = event.target.dataset.id;
        const seleccion = { ...this.seleccion };
        if (event.target.checked) {
            seleccion[id] = seleccion[id] || {};
        } else {
            delete seleccion[id];
        }
        this.seleccion = seleccion;
        this.publicarSalidas();
    }

    handleSeleccionTodas(event) {
        const seleccion = { ...this.seleccion };
        this.filasVista.forEach((f) => {
            if (event.target.checked) {
                seleccion[f.id] = seleccion[f.id] || {};
            } else {
                delete seleccion[f.id];
            }
        });
        this.seleccion = seleccion;
        this.publicarSalidas();
    }

    handleCantidad(event) {
        const { id, campo } = event.target.dataset;
        const valor = event.detail.value;
        const fila = this.filas.find((f) => f.id === id);
        if (fila?.campoUM && fila.campoUM !== campo) {
            return; // sub-input no corresponde a la UM del producto
        }
        const estado = { ...(this.seleccion[id] || {}) };
        if (tieneValor(valor)) {
            // Excluyentes: al ingresar en un sub-input se descartan los otros dos
            CAMPOS_INGRESO.filter((c) => c !== campo).forEach((c) => delete estado[c]);
            estado[campo] = valor;
        } else {
            delete estado[campo];
        }
        // Si el usuario cambia el valor a mano, "Cantidad total" solo sigue marcado si coincide con el total
        if (fila && tieneValor(valor) && Number(valor) === Number(fila[COLUMNA_TOTAL[campo]])) {
            estado.total = true;
        } else {
            delete estado.total;
        }
        this.seleccion = { ...this.seleccion, [id]: estado };
        event.target.reportValidity();
        this.publicarSalidas();
    }

    /**
     * Checkbox "Cantidad total": al marcarlo asigna al sub-input habilitado el total de la fila
     * (Peso neto, Cantidad o Cantidad unidad según la UM). Al desmarcarlo limpia ese sub-input.
     * El cálculo del valor reclamado es el mismo (calcularReclamoFila).
     */
    handleCantidadTotal(event) {
        const id = event.target.dataset.id;
        const fila = this.filas.find((f) => f.id === id);
        if (!fila) {
            return;
        }
        const estado = { ...(this.seleccion[id] || {}) };
        const campo = fila.campoUM || campoIngresado(estado);
        if (!campo) {
            return;
        }
        if (event.target.checked) {
            CAMPOS_INGRESO.filter((c) => c !== campo).forEach((c) => delete estado[c]);
            estado[campo] = String(fila[COLUMNA_TOTAL[campo]]);
            estado.total = true;
        } else {
            delete estado[campo];
            delete estado.total;
        }
        this.seleccion = { ...this.seleccion, [id]: estado };
        this.publicarSalidas();
    }

    // ------------------------------------------------------------------
    // Salidas al Flow
    // ------------------------------------------------------------------

    publicarSalidas() {
        const seleccionadas = this.seleccionadas;
        const tipos = new Set(seleccionadas.map((s) => s.tipoUM).filter(Boolean));

        const sumar = (tipo) =>
            seleccionadas.filter((s) => s.tipoUM === tipo).reduce((acc, s) => acc + s.cantidad, 0);
        const kg = Math.round(sumar(TIPO_UM.KG) * 1000) / 1000;
        const cajas = sumar(TIPO_UM.CAJA);
        const unidades = sumar(TIPO_UM.UNIDAD);
        const valor = seleccionadas.reduce((acc, s) => acc + s.valor, 0);
        // Cantidad facturada: valor de la fila en la misma columna donde se ingresa lo reclamado
        // (KG → Peso neto, Caja → Cantidad, Unidad → Cantidad unidad).
        const facturadaFila = (s) => {
            const tipo = s.tipoUM || s.fila.tipoUMProducto;
            if (tipo === TIPO_UM.KG) return Number(s.fila.pesoNeto) || 0;
            if (tipo === TIPO_UM.CAJA) return Number(s.fila.cantidad) || 0;
            if (tipo === TIPO_UM.UNIDAD) return Number(s.fila.cantidadUnidad) || 0;
            return 0;
        };
        const facturada = Math.round(seleccionadas.reduce((acc, s) => acc + facturadaFila(s), 0) * 1000) / 1000;

        let tipoUM = '';
        if (tipos.size === 1) {
            tipoUM = [...tipos][0];
        } else if (tipos.size > 1) {
            tipoUM = 'Mixto';
        }

        const salidas = {
            outputSelectedRows: seleccionadas.map((s) => s.fila.registro),
            outputSelectedRow: seleccionadas.length > 0 ? seleccionadas[0].fila.registro : null,
            numberOfRowsSelected: seleccionadas.length,
            tipoUMReclamo: tipoUM,
            cantidadKgReclamada: String(kg),
            cantidadCajasReclamada: Number.isInteger(cajas) ? cajas : redondear(cajas),
            cantidadUnidadesReclamada: Number.isInteger(unidades) ? unidades : redondear(unidades),
            cantidadReclamadaTotal: String(Math.round((kg + cajas + unidades) * 1000) / 1000),
            valorNetoReclamado: String(valor),
            cantidadFacturadaReclamo: String(facturada),
            detalleReclamoJson: JSON.stringify(
                seleccionadas.map((s) => ({
                    detalleId: s.fila.id,
                    productId: s.fila.registro.Product__c || null,
                    sku: s.fila.sku || null,
                    unidadMedidaProducto: s.fila.unidadMedida || null,
                    tipoUM: s.tipoUM || null,
                    cantidadReclamada: s.cantidad,
                    cajasIngresadas: s.cajas,
                    kgIngresados: s.kg,
                    unidadesIngresadas: s.unidades,
                    cantidadTotal: !!this.seleccion[s.fila.id]?.total,
                    valorNetoReclamado: s.valor
                }))
            ),
            estadoSeleccion: JSON.stringify(this.seleccion)
        };

        Object.entries(salidas).forEach(([nombre, valorSalida]) => {
            this[nombre] = valorSalida;
            this.dispatchEvent(new FlowAttributeChangeEvent(nombre, valorSalida));
        });
    }

    // ------------------------------------------------------------------
    // Validación del Flow (al presionar Siguiente)
    // ------------------------------------------------------------------

    @api
    validate() {
        if (this.mensajeError) {
            return { isValid: false, errorMessage: this.mensajeError };
        }
        const seleccionadas = this.seleccionadas;
        if (this.seleccionRequerida && seleccionadas.length === 0) {
            return { isValid: false, errorMessage: 'Debe seleccionar al menos un producto de la factura.' };
        }
        if (!this.cantidadesHabilitadas) {
            return { isValid: true };
        }

        this.template.querySelectorAll('lightning-input[data-campo]').forEach((input) => input.reportValidity());

        const nombre = (s) => s.fila.sku || s.fila.nombre;
        // Incluye cantidades faltantes (según la UM del producto) y valores que superan la fila
        const conError = seleccionadas.filter((s) => s.error);
        if (conError.length > 0) {
            return {
                isValid: false,
                errorMessage: conError.map((s) => `${nombre(s)}: ${s.error}`).join(' ')
            };
        }
        if (new Set(seleccionadas.map((s) => s.tipoUM)).size > 1) {
            return {
                isValid: false,
                errorMessage:
                    'Todos los productos seleccionados deben reclamarse en la misma unidad (KG, Caja o Unidad), ya que el Caso registra un solo tipo de UM.'
            };
        }
        return { isValid: true };
    }
}