import { LightningElement, api, track, wire } from 'lwc';
import { helper } from './panelSeteoHelper';
import crearQuote from '@salesforce/apex/MaestraPreciosController.crearQuote';

export default class PanelSeteo extends LightningElement {
    @api accountIdValue;
    @api accountName;
    @api initialProductData; // Datos que llegan desde el padre
    @api shouldFilter = false;
    @api shouldHideButton = false;
    @track productData = []; // Copia los datos del padre para hacerlos reactivos
    @track productDataDraft = []; // Items de la lista que han sido modificados
    @track draftValues = []; // Items de la lista que han sido modificados
    @track selectedProducts = []; // Items que se seleccionen del modal de buscar productos
    showSpinner = true;
    showModal = false;
    columns = [];
    encabezado = '';

    connectedCallback() {
        this.encabezado = helper.generarEncabezado();
        this.columns = helper.initializeColumns();
        if (this.accountIdValue) {
            this.productData = this.shouldFilter ? helper.filtrarProductos([...this.initialProductData]) : [...this.initialProductData]; // Filtra los datos que vienen del padre para que tome solo los que tengan lista de precio
            if (this.productData) {
                this.productDataDraft = this.productData.map(item => ({ ...item })); // Esta es la lista que vamos a mutar
                this.productDataDraft.forEach(item => {
                    if (item.descuento == null || item.descuento == undefined) {
                        item.descuento = 0;
                        item.precioClienteNeto = item.listaPrecio;
                        item.margen = helper.calculateMargen(item);
                        item.margenContribucionKilo = helper.calculateKilo(item);
                    }
                });
                this.showSpinner = false;
            }
        }
    }

    handleAtras() {
        const event = new CustomEvent('atrasclicked', {
            detail: { isActualizarClicked: true }
        });
        this.dispatchEvent(event);
    }

    handlePrecioClienteNeto(event) {
        const newPrecioSolicitado = parseFloat(event.target.value) || 0;
        const itemId = event.target.dataset.id;
        let currentDescuento;
        let currentMg;

        // Obtener valor actual de descuento
        const descuentoElement = this.template.querySelector(`.descuento-value[data-id="${itemId}"]`);
        if (descuentoElement) {
            currentDescuento = descuentoElement.value;
            if (currentDescuento === '') {
                currentDescuento = 0;
            }
            currentDescuento = helper.calculateDescuento(newPrecioSolicitado).toFixed(2);
            descuentoElement.value = currentDescuento;
        } else {
            console.log('Elemento no encontrado para el item con id', itemId);
        }

        // Obtener valor actual de %MG
        const mgElement = this.template.querySelector(`.mg-value[data-id="${itemId}"]`);
        if (mgElement) {
            currentMg = mgElement.innerText;
            if (currentMg === '') {
                currentMg = 0;
            }
            currentMg = helper.calculateMg(newPrecioSolicitado).toFixed(2);
            mgElement.innerText = currentMg;
        } else {
            console.log('Elemento no encontrado para el item con id', itemId);
        }

        // Ajustar el item actualizado en productDataDraft
        const product = this.productDataDraft.find(item => item.id === itemId);
        if (product) {
            product.descuento = currentDescuento.toString();
            product.margen = currentMg.toString();
            product.precioClienteNeto = newPrecioSolicitado;
            // TO DO: Actualizar margen por kilo
        }
    }

    handleDescuentoChange(event) {
        const newDescuento = parseFloat(event.target.value) || 0;
        const itemId = event.target.dataset.id;
        let currentPrecio;
        let currentMg;

        // Obtener valor actual de Precio Solicitado
        const precioElement = this.template.querySelector(`.precio-cliente-value[data-id="${itemId}"]`);
        if (precioElement) {
            currentPrecio = precioElement.value;
            if (currentPrecio === '') {
                currentPrecio = 0;
            }
            currentPrecio = helper.calculatePrecioSolicitado(newDescuento).toFixed(2);
            precioElement.value = currentPrecio;
        } else {
            console.log('Elemento no encontrado para el item con id', itemId);
        }

        // Obtener valor actual de %MG
        const mgElement = this.template.querySelector(`.mg-value[data-id="${itemId}"]`);
        if (mgElement) {
            currentMg = mgElement.innerText;
            if (currentMg === '') {
                currentMg = 0;
            }
            currentMg = helper.calculateMg(currentPrecio).toFixed(2);
            mgElement.innerText = currentMg;
        } else {
            console.log('Elemento no encontrado para el item con id', itemId);
        }

        // Ajustar el item actualizado en productDataDraft
        const auxProductDraft = [...this.productDataDraft]; // Evitar mutabilidad directa.
        const product = auxProductDraft.find(item => item.id === itemId);
        if (product) {
            try {
                product.descuento = newDescuento.toString();
                product.margen = currentMg.toString();
                product.precioClienteNeto = currentPrecio;
                // TO DO: Actualizar margen por kilo
            } catch (error) {
                console.log('error: ', error);
            }
        }
        this.productDataDraft = auxProductDraft;
    }

    handleFechaChange(event) {
        console.log(event.target.value);
    }

    handleDraft() {
        this.handleCreateQuoteButton('Draft');
    }

    handleSetear() {
        this.handleCreateQuoteButton('Approved');
    }

    handleAddProduct() {
        this.showModal = true;
    }

    handleCloseModal() {
        this.showModal = false;
    }

    handleModalContinue() {
        this.addSelectedProducts();
        this.showModal = false;
    }

    addSelectedProducts() {
        const currentlySelectedData = [...this.selectedProducts.recordData, ...this.productDataDraft];

        // Remove duplicates based on the 'id' attribute
        const uniqueData = [];
        const idSet = new Set();

        currentlySelectedData.forEach(item => {
            if (!idSet.has(item.id)) {
                item.descuento = 0;
                item.precioClienteNeto = item.listaPrecio;
                item.margen = helper.calculateMargen(item);
                item.margenContribucionKilo = helper.calculateKilo(item);
                uniqueData.push(item);
                idSet.add(item.id);
            }
        });

        this.productDataDraft = uniqueData;
    }

    handleCreateQuoteButton(status) {
        // Formatear items antes de enviar a Apex.
        this.productDataDraft = this.productDataDraft.map((item) => {
            let parsedMargin = parseFloat(item.margen);
            if (isNaN(parsedMargin)) {
                parsedMargin = 0;
            }
            return {
                ...item,
                margen: parsedMargin, // Actualiza 'margen' con el valor numérico
            };
        });

        const registrosUnificadosJSON = JSON.parse(JSON.stringify(this.productDataDraft));
        this.showSpinner = true;
        //const proxy = new Proxy(registrosUnificadosJSON, {get: (target, key) => {return target[key];}})
        //console.log(JSON.stringify(proxy));
        helper.showToast('info', 'Pronto se redireccionará...', 'Creando Quote...');
        crearQuote({ status: status, registrosUnificados: registrosUnificadosJSON, accountId: this.accountIdValue })
            .then((result) => {
                helper.showToast('success', 'Redireccionando...', 'Quote creada!');
                helper.redirectToQuote(result.Id);
            })
            .catch((error) => {
                const errorMessage = error.body && error.body.message ? error.body.message : 'Error desconocido al crear Quote. Comuniquese con su administrador';
                helper.showToast('error', errorMessage, 'Error al crear Quote');
                console.error('Error al crear Quote:', error);
                this.showSpinner = false;
            });
    }

    handleSelectProducts(event) {
        this.selectedProducts = event.detail;
    }

    handleCellChange(event) {
        const currentItem = event.detail.draftValues[0]; // Se toma el primer (y unico) item ya que se editan de uno en uno.
        
        const shouldCalculatePrecio = currentItem.descuento != null ? true : false;
        const shouldCalculateDescuento = currentItem.precioClienteNeto != null ? true : false;
        const shouldCalculateDate = currentItem.fechaVencimientoDescuento != null ? true : false;

        // Ajustar el item actualizado en productDataDraft
        const auxProductDraft = [...this.productDataDraft]; // Evitar mutabilidad directa.
        const product = auxProductDraft.find(item => item.id === currentItem.id);

        //const auxDraftValues = [...event.detail.draftValues];
        //const draftProduct = auxDraftValues.find(item => item.id === currentItem.id);

        if (product) {
            try {
                if (shouldCalculatePrecio) {
                    product.descuento = currentItem.descuento;
                    product.precioClienteNeto = helper.calculatePrecioSolicitado(product);
                } else if (shouldCalculateDescuento) {
                    product.precioClienteNeto = currentItem.precioClienteNeto;
                    product.descuento = helper.calculateDescuento(product);
                } else if (shouldCalculateDate) {
                    product.fechaVencimientoDescuento = helper.checkDate(product.fechaMaximaOriginal, currentItem.fechaVencimientoDescuento);
                }
                product.margen = helper.calculateMargen(product);
                product.margenContribucionKilo = helper.calculateKilo(product);

                this.productDataDraft = auxProductDraft;
                this.draftValues = [];
                if (product.descuento < 0) {
                    helper.showToast('error', 'El descuento no puede ser menor a 0.', 'Error en el descuento');
                }
            } catch (error) {
                console.log('error: ', error);
            }
        }
    }
}