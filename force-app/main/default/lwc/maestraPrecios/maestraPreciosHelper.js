const helper = {
    generarEncabezado: () => {
        const today = new Date();
        const meses = [
            'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
            'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
        ];
        const mesTexto = meses[today.getMonth()];
        const anio = today.getFullYear();
        
        return `${mesTexto.toUpperCase()} ${anio}`;
    },

    initializeColumns: () => {
        return [
            { 
                label: 'SKU', 
                fieldName: 'sku', 
                type: 'text', 
                initialWidth: 100,
                sortable: true 
            },
            { 
                label: 'UMV', 
                fieldName: 'umv', 
                type: 'text', 
                initialWidth: 80,
                sortable: true 
            },
            { 
                label: 'Descripción', 
                fieldName: 'descripcion', 
                type: 'text', 
                initialWidth: 350,
                sortable: true 
            },
            { 
                label: 'Lista de Precio', 
                fieldName: 'listaPrecio', 
                type: 'number', 
                initialWidth: 150, 
                typeAttributes: { maximumFractionDigits: 2 }, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
            { 
                label: 'Fecha Vigencia', 
                fieldName: 'fechaMaximaOriginal', 
                type: 'date', 
                initialWidth: 150, 
                typeAttributes: { day: '2-digit', month: '2-digit', year: 'numeric', weekday: undefined },
                sortable: true 
            },
            { 
                label: 'Descuento %', 
                fieldName: 'descuento', 
                type: 'number', 
                initialWidth: 140, 
                typeAttributes: { minimumFractionDigits: 2 }, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
            { 
                label: 'Precio Cliente Neto', 
                fieldName: 'precioClienteNeto', 
                type: 'number', 
                initialWidth: 180, 
                typeAttributes: { maximumFractionDigits: 2 }, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
            { 
                label: 'Rappel', 
                fieldName: 'rappel', 
                type: 'number', 
                initialWidth: 100, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
            { 
                label: '%MG', 
                fieldName: 'margen', 
                type: 'number', 
                initialWidth: 100, 
                typeAttributes: { minimumFractionDigits: 2 }, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
            { 
                label: 'MG Contribución x Kilo', 
                fieldName: 'margenContribucionKilo', 
                initialWidth: 200, 
                type: 'number', 
                typeAttributes: { maximumFractionDigits: 0 }, 
                cellAttributes: { alignment: 'left' },
                sortable: true 
            },
        ];
    },

    transformarDatos: (productos) => {
        productos.forEach(producto => {
            producto.descuento = producto.descuento ? Number(producto.descuento).toFixed(2) : 0.00;
            producto.margen = producto.margen ? Number(producto.margen).toFixed(2) : 0.00;
            producto.margenContribucionKilo = producto.margenContribucionKilo ? Number(producto.margenContribucionKilo).toFixed(2) : 0.00;
            producto.rappel = producto.rappel ? Number(producto.rappel) : 0;
        });
    }
}

export { helper }