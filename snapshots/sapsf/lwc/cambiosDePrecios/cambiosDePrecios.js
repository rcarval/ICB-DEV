import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getInformacionProductos from '@salesforce/apex/ControllerTabCambiosDePrecios.getInformacionProductos';
import getOpcionesFiltros from '@salesforce/apex/ControllerTabCambiosDePrecios.getOpcionesFiltros';
import iconChange from '@salesforce/resourceUrl/iconChange';

const PAGE_SIZE = 50;
const SEARCH_DELAY = 350;
const MIN_TABLE_HEIGHT = 200;
const BOTTOM_MARGIN = 32;
const MIN_COLUMN_WIDTH = 50;

// es-CL separa miles con punto (78000 -> 78.000); se redondea a entero como en pesos chilenos
const PRICE_FORMAT = new Intl.NumberFormat('es-CL', { maximumFractionDigits: 0 });

// Valores del picklist Estado__c y la clase CSS de su etiqueta en la tabla
const ESTADO_BADGE_CLASS = {
    ALZA: 'estado-alza',
    BAJA: 'estado-baja',
    MANTIENE: 'estado-mantiene',
    'INCORPORACIÓN': 'estado-incorporacion'
};

function formatPrice(valor) {
    return valor === null || valor === undefined || valor === ''
        ? ''
        : PRICE_FORMAT.format(valor);
}

export default class CambiosDePrecios extends NavigationMixin(LightningElement) {

    products = [];

    pageNumber = 1;
    totalRecords = 0;
    isLoading = false;
    iconChange = iconChange;

    // pageCursors[n] es el cursor (último registro de la página n) para cargar la página n + 1
    pageCursors = [null];
    requestId = 0;

    searchTerm = '';
    searchTimeout;

    // Filtros tipo autofiltro de Excel; optionsKey es la lista que devuelve getOpcionesFiltros
    filters = [
        { name: 'categoria', label: 'Categoría', placeholder: 'Todas las categorías', optionsKey: 'categorias' },
        { name: 'familia', label: 'Familia', placeholder: 'Todas las familias', optionsKey: 'familias' },
        { name: 'marca', label: 'Marca', placeholder: 'Todas las marcas', optionsKey: 'marcas' },
        { name: 'estado', label: 'Estado', placeholder: 'Todos los estados', optionsKey: 'estados' }
    ].map(filtro => ({ ...filtro, value: '', values: [] }));

    optionsRequestId = 0;

    // Rango de última modificación en formato YYYY-MM-DD (el que usa <input type="date">)
    dateFrom = '';
    dateTo = '';

    error;

    showColumnMenu = false;
    showZoneMenu = false;

    // Valores activos del picklist Zona__c; sin ninguna marcada se muestran todas
    zones = [
        'Suc Santiago',
        'Suc Coquimbo',
        'Suc Temuco',
        'Suc Concepción',
        'Suc Antofagasta',
        'Suc Puerto Montt',
        'Suc Iquique',
        'Suc Curicó',
        'Suc Calama',
        'Suc Viña del Mar'
    ].map(zona => ({ name: zona, label: zona, selected: false }));

    // El orden debe coincidir con el de las celdas <td> de la tabla; width en píxeles
    columns = [
        { name: 'codigo', label: 'Código', header: 'CÓDIGO', width: 90, visible: true },
        { name: 'category', label: 'Category', header: 'CATEGORY', width: 145, visible: true },
        { name: 'jefeCategoria', label: 'Jefe Categoría', header: 'JEFE CATEGORÍA', width: 130, visible: true },
        { name: 'categoria', label: 'Categoría', header: 'CATEGORÍA', width: 130, visible: true },
        { name: 'familia', label: 'Familia', header: 'FAMILIA', width: 110, visible: true },
        { name: 'descripcion', label: 'Descripción', header: 'DESCRIPCIÓN', width: 240, visible: true },
        { name: 'umv', label: 'UMV', header: 'UMV', width: 60, visible: true },
        { name: 'umb', label: 'UMB', header: 'UMB', width: 60, visible: true },
        { name: 'descripcionUmv', label: 'Descripción UMV', header: 'DESCRIPCIÓN UMV', width: 130, visible: true },
        { name: 'estado', label: 'Estado', header: 'ESTADO', width: 90, visible: true },
        { name: 'precio', label: 'Precio', header: 'PRECIO $', width: 90, visible: true },
        { name: 'precioUnidad', label: 'Precio UN', header: 'PRECIO UN $', width: 90, visible: true },
        { name: 'feeApertura', label: 'FEE Apertura', header: 'FEE APERTURA', width: 100, visible: true },
        { name: 'ventasPorUnidad', label: 'Ventas por Unidad', header: 'VENTAS POR UNIDAD', width: 125, visible: true },
        { name: 'precioUnidadFee', label: 'Precio Unidad FEE', header: 'PRECIO UNIDAD FEE', width: 125, visible: true },
        { name: 'descuentoAutonomo', label: 'Descuento Autónomo', header: 'DESCUENTO AUTONOMO %', width: 135, visible: true },
        { name: 'productoFoco', label: 'Producto Foco', header: 'PRODUCTO FOCO', width: 110, visible: true },
        { name: 'base', label: 'Base', header: 'BASE', width: 90, visible: true },
        { name: 'zona', label: 'Zona', header: 'ZONA', width: 130, visible: true }
    ];

    // Estado del arrastre mientras se redimensiona una columna
    resizing = null;

    closeMenusHandler = () => {
        this.showColumnMenu = false;
        this.showZoneMenu = false;
    };


    resizeHandler = () => {
        this.adjustTableHeight();
    };


    columnResizeMoveHandler = event => {

        if (!this.resizing) {
            return;
        }

        const { name, startX, startWidth } = this.resizing;
        const width = Math.max(MIN_COLUMN_WIDTH, startWidth + event.clientX - startX);

        this.columns = this.columns.map(column =>
            column.name === name
                ? { ...column, width }
                : column
        );
    };


    columnResizeEndHandler = () => {
        this.resizing = null;
        window.removeEventListener('mousemove', this.columnResizeMoveHandler);
        window.removeEventListener('mouseup', this.columnResizeEndHandler);
    };


    connectedCallback() {
        document.addEventListener('click', this.closeMenusHandler);
        window.addEventListener('resize', this.resizeHandler);
        this.loadProducts();
        this.loadFilterOptions();
    }


    disconnectedCallback() {
        document.removeEventListener('click', this.closeMenusHandler);
        window.removeEventListener('resize', this.resizeHandler);
        this.columnResizeEndHandler();
        clearTimeout(this.searchTimeout);
    }


    renderedCallback() {
        this.adjustTableHeight();
    }


    // Estira la tabla desde su posición hasta casi el final de la ventana;
    // el scroll queda solo dentro de la tabla
    adjustTableHeight() {

        const wrapper = this.template.querySelector('.table-wrapper');

        if (!wrapper) {
            return;
        }

        const footer = this.template.querySelector('.table-footer');
        const legend = this.template.querySelector('.legend');

        const bottomSpace =
            (footer ? footer.offsetHeight : 0) +
            (legend ? legend.offsetHeight : 0) +
            BOTTOM_MARGIN;

        const height = Math.max(
            MIN_TABLE_HEIGHT,
            window.innerHeight - wrapper.getBoundingClientRect().top - bottomSpace
        );

        wrapper.style.height = `${height}px`;
    }


    // =====================================================
    // SELECTOR DE COLUMNAS
    // =====================================================

    // Evita que un clic dentro del desplegable lo cierre
    handleDropdownClick(event) {
        event.stopPropagation();
    }


    handleToggleColumnMenu() {
        this.showColumnMenu = !this.showColumnMenu;
        this.showZoneMenu = false;
    }


    handleColumnVisibility(event) {

        const { name, checked } = event.target;

        this.columns = this.columns.map(column =>
            column.name === name
                ? { ...column, visible: checked }
                : column
        );
    }


    get columnMenuExpanded() {
        return String(this.showColumnMenu);
    }


    get visibleColumnCount() {
        return this.visibleColumns.length || 1;
    }


    get visibleColumns() {
        return this.columns
            .filter(column => column.visible)
            .map(column => ({ ...column, style: `width: ${column.width}px;` }));
    }


    // Con table-layout: fixed el ancho de la tabla es la suma de sus columnas,
    // así agrandar una columna no encoge a las demás
    get tableStyle() {
        const total = this.columns
            .filter(column => column.visible)
            .reduce((suma, column) => suma + column.width, 0);

        return `width: ${total}px;`;
    }


    // =====================================================
    // REDIMENSIONAR COLUMNAS
    // =====================================================

    handleColumnResizeStart(event) {

        event.preventDefault();
        event.stopPropagation();

        const name = event.currentTarget.dataset.name;
        const column = this.columns.find(col => col.name === name);

        this.resizing = {
            name,
            startX: event.clientX,
            startWidth: column.width
        };

        window.addEventListener('mousemove', this.columnResizeMoveHandler);
        window.addEventListener('mouseup', this.columnResizeEndHandler);
    }


    // =====================================================
    // SELECTOR DE ZONAS
    // =====================================================

    handleToggleZoneMenu() {
        this.showZoneMenu = !this.showZoneMenu;
        this.showColumnMenu = false;
    }


    handleZoneSelection(event) {

        const { name, checked } = event.target;

        this.zones = this.zones.map(zona =>
            zona.name === name
                ? { ...zona, selected: checked }
                : zona
        );

        this.applyFilters();
    }


    // "Todas" no se puede desmarcar: siempre limpia la selección de zonas
    handleAllZonesChange(event) {
        event.target.checked = true;
        this.handleAllZones();
    }


    handleAllZones() {

        if (this.allZonesSelected) {
            return;
        }

        this.zones = this.zones.map(zona => ({ ...zona, selected: false }));

        this.applyFilters();
    }


    get selectedZones() {
        return this.zones
            .filter(zona => zona.selected)
            .map(zona => zona.name);
    }


    get allZonesSelected() {
        return this.selectedZones.length === 0;
    }


    get zone() {

        const seleccionadas = this.selectedZones;

        if (seleccionadas.length === 0) {
            return 'Todas';
        }

        return seleccionadas.length === 1
            ? seleccionadas[0]
            : `${seleccionadas.length} zonas`;
    }


    get zoneMenuExpanded() {
        return String(this.showZoneMenu);
    }


    getColumnClass(name) {
        const column = this.columns.find(col => col.name === name);
        return column && column.visible ? '' : 'hide';
    }


    // Getter para calcular las clases CSS de las columnas dinámicamente
    get codigoClass() {
        return this.getColumnClass('codigo');
    }

    get categoryClass() {
        return this.getColumnClass('category');
    }

    get jefeCategoriaClass() {
        return this.getColumnClass('jefeCategoria');
    }

    get categoriaClass() {
        return this.getColumnClass('categoria');
    }

    get familiaClass() {
        return this.getColumnClass('familia');
    }

    get descripcionClass() {
        return this.getColumnClass('descripcion');
    }

    get umvClass() {
        return this.getColumnClass('umv');
    }

    get umbClass() {
        return this.getColumnClass('umb');
    }

    get descripcionUMVClass() {
        return this.getColumnClass('descripcionUmv');
    }

    get estadoClass() {
        return this.getColumnClass('estado');
    }

    get precioClass() {
        return this.getColumnClass('precio');
    }

    get precioPorUnidadClass() {
        return this.getColumnClass('precioUnidad');
    }

    get feeAperturaClass() {
        return this.getColumnClass('feeApertura');
    }

    get ventasPorUnidadClass() {
        return this.getColumnClass('ventasPorUnidad');
    }

    get precioUnFeeClass() {
        return this.getColumnClass('precioUnidadFee');
    }

    get descuentoAutClass() {
        return this.getColumnClass('descuentoAutonomo');
    }

    get productoFocoClass() {
        return this.getColumnClass('productoFoco');
    }

    get baseClass() {
        return this.getColumnClass('base');
    }

    get zonaClass() {
        return this.getColumnClass('zona');
    }
    // =====================================================
    // OBTENER PRODUCTOS
    // =====================================================

    async loadProducts() {

        // Solo se aplica la respuesta de la última petición (evita carreras al cambiar filtros rápido)
        const currentRequest = ++this.requestId;
        const cursor = this.pageCursors[this.pageNumber - 1];

        this.isLoading = true;

        try {

            const result = await getInformacionProductos({
                ...this.filterParams,
                tamanoPagina: PAGE_SIZE,
                cursorFecha: cursor ? cursor.fecha : null,
                cursorId: cursor ? cursor.id : null
            });

            if (currentRequest !== this.requestId) {
                return;
            }

            const registros = result.registros || [];

            this.products = this.mapProducts(registros);
            this.totalRecords = result.totalRegistros || 0;

            const ultimo = registros[registros.length - 1];

            if (ultimo) {
                this.pageCursors[this.pageNumber] = {
                    fecha: ultimo.LastModifiedDate,
                    id: ultimo.Id
                };
            }

            this.error = undefined;

        } catch (error) {

            if (currentRequest !== this.requestId) {
                return;
            }

            console.error(
                'Error obteniendo productos:',
                error
            );

            this.error = error;

            this.products = [];
            this.totalRecords = 0;

        } finally {

            if (currentRequest === this.requestId) {
                this.isLoading = false;
                this.scrollTableToTop();
            }
        }
    }


    mapProducts(registros) {

        return registros.map(producto => {

            return {
                id: producto.Id,

                codigo: producto.Codigo__c,

                category: producto.Category__c,

                jefeCategoria: producto.Jefe_Categoria__c,

                categoria: producto.Categoria__c,

                familia: producto.Familia__c,

                productoId: producto.Producto__c,

                descripcion: producto.Producto__r ? producto.Producto__r.Name : '',

                productoUrl: producto.Producto__c
                    ? `/lightning/r/Product2/${producto.Producto__c}/view`
                    : null,

                umv: producto.UMV__c,

                umb: producto.UMB__c,

                descripcionUmv: producto.Descripcion_UMV__c,

                estado: producto.Estado__c,

                estadoBadgeClass: `estado-badge ${ESTADO_BADGE_CLASS[producto.Estado__c] || ''}`,

                esAlza: producto.Estado__c === 'ALZA',

                precio: formatPrice(producto.Precio__c),

                precioUnidad: formatPrice(producto.Precio_UN__c),

                feeApertura: producto.FEE_Apertura__c,

                ventasPorUnidad: producto.Ventas_Por_Unidad__c,

                precioUnidadFee: formatPrice(producto.Precio_UN_FEE__c),

                descuentoAutonomo: producto.Descuento_Autonomo__c,

                productoFoco: producto.Producto_Foco__c,

                tipo: producto.tipo__c,

                zona: producto.Zona__c
            };

        });
    }


    // El href permite abrir en otra pestaña; el clic normal navega dentro de Lightning
    handleProductClick(event) {

        event.preventDefault();

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Product2',
                actionName: 'view'
            }
        });
    }


    scrollTableToTop() {

        const wrapper = this.template.querySelector('.table-wrapper');

        if (wrapper) {
            wrapper.scrollTop = 0;
        }
    }


    // =====================================================
    // PAGINACIÓN
    // =====================================================

    resetPagination() {
        this.pageNumber = 1;
        this.pageCursors = [null];
        this.loadProducts();
    }


    handlePreviousPage() {

        if (this.isFirstPage) {
            return;
        }

        this.pageNumber--;
        this.loadProducts();
    }


    handleNextPage() {

        if (this.isLastPage) {
            return;
        }

        this.pageNumber++;
        this.loadProducts();
    }


    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / PAGE_SIZE));
    }


    get isFirstPage() {
        return this.pageNumber <= 1 || this.isLoading;
    }


    get isLastPage() {
        return this.pageNumber >= this.totalPages || this.isLoading;
    }


    get previousButtonClass() {
        return this.isFirstPage ? 'pagination-button disabled' : 'pagination-button';
    }


    get nextButtonClass() {
        return this.isLastPage ? 'pagination-button disabled' : 'pagination-button';
    }


    get rangeStart() {
        return this.hasProducts ? (this.pageNumber - 1) * PAGE_SIZE + 1 : 0;
    }


    get rangeEnd() {
        return this.hasProducts ? (this.pageNumber - 1) * PAGE_SIZE + this.products.length : 0;
    }


    // =====================================================
    // GETTERS
    // =====================================================

    get productCount() {
        return this.totalRecords;
    }


    get hasProducts() {
        return this.products.length > 0;
    }


    // =====================================================
    // BUSCADOR
    // =====================================================

    // Espera a que el usuario deje de escribir para no consultar por cada tecla
    handleSearch(event) {

        this.searchTerm = event.target.value;

        clearTimeout(this.searchTimeout);

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimeout = setTimeout(() => {
            this.applyFilters();
        }, SEARCH_DELAY);
    }


    // =====================================================
    // FILTROS
    // =====================================================

    handleFilterChange(event) {

        const { name, value } = event.target;

        this.filters = this.filters.map(filtro =>
            filtro.name === name
                ? { ...filtro, value }
                : filtro
        );

        this.applyFilters();
    }


    handleDateChange(event) {

        const { name, value } = event.target;

        if (name === 'fechaDesde') {
            this.dateFrom = value;
        } else {
            this.dateTo = value;
        }

        // Rango incompleto al escribir a mano o invertido: se espera a que quede válido
        if (this.dateFrom && this.dateTo && this.dateFrom > this.dateTo) {
            return;
        }

        this.applyFilters();
    }


    // Recarga la tabla desde la primera página y las listas de valores de los filtros
    applyFilters() {
        this.resetPagination();
        this.loadFilterOptions();
    }


    getFilterValue(name) {
        return this.filters.find(filtro => filtro.name === name).value;
    }


    // Parámetros comunes de getInformacionProductos y getOpcionesFiltros
    get filterParams() {
        return {
            zonas: this.selectedZones,
            categoria: this.getFilterValue('categoria'),
            familia: this.getFilterValue('familia'),
            marca: this.getFilterValue('marca'),
            estado: this.getFilterValue('estado'),
            textoBusqueda: this.searchTerm ? this.searchTerm.trim() : '',
            fechaDesde: this.dateFrom || null,
            fechaHasta: this.dateTo || null
        };
    }


    // Si el valor elegido ya no viene en la lista (p. ej. al cambiar de zona) se mantiene visible
    get filterList() {
        return this.filters.map(filtro => {

            const valores = filtro.value && !filtro.values.includes(filtro.value)
                ? [filtro.value, ...filtro.values]
                : filtro.values;

            return {
                ...filtro,
                options: valores.map(valor => ({
                    value: valor,
                    selected: valor === filtro.value
                }))
            };
        });
    }


    async loadFilterOptions() {

        const currentRequest = ++this.optionsRequestId;

        try {

            const opciones = await getOpcionesFiltros(this.filterParams);

            if (currentRequest !== this.optionsRequestId) {
                return;
            }

            this.filters = this.filters.map(filtro => ({
                ...filtro,
                values: opciones[filtro.optionsKey] || []
            }));

        } catch (error) {

            if (currentRequest === this.optionsRequestId) {
                console.error('Error obteniendo opciones de filtros:', error);
            }
        }
    }


    // =====================================================
    // LIMPIAR
    // =====================================================

    handleClear() {

        clearTimeout(this.searchTimeout);

        this.searchTerm = '';

        this.filters = this.filters.map(filtro => ({ ...filtro, value: '' }));

        this.zones = this.zones.map(zona => ({ ...zona, selected: false }));

        this.dateFrom = '';
        this.dateTo = '';

        // El value de un input/select no se reinicia solo al cambiar la propiedad enlazada
        this.template.querySelectorAll('.search-input, .filter-select select, .date-field input').forEach(control => {
            control.value = '';
        });

        this.applyFilters();
    }


    // =====================================================
    // REFRESCAR
    // =====================================================

    handleRefresh() {
        this.applyFilters();
    }
}