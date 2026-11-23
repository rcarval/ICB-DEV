/**
 * Cálculos del valor neto reclamado, homologados con las fórmulas del flujo
 * "Caso - Ingreso de Caso mejorado" (valorNeto y valorPorUnidad).
 */

export const TIPO_UM = Object.freeze({ KG: 'KG', CAJA: 'Caja', UNIDAD: 'Unidad' });

/** ROUND(x, 0) de Salesforce: redondea .5 alejándose de cero. */
export function redondear(valor) {
    const n = Number(valor) || 0;
    // Se normaliza a 6 decimales para evitar errores de punto flotante (p. ej. 100.49999999 → 100.5),
    // ya que Salesforce calcula con Decimal.
    const absoluto = Number(Math.abs(n).toFixed(6));
    return Math.sign(n) * Math.round(absoluto);
}

function num(valor) {
    const n = Number(valor);
    return Number.isFinite(n) ? n : 0;
}

/**
 * KG: IF(Peso_neto__c > 0, ROUND(Cantidad_Reclamada * (Total_con_Rapel__c / Peso_neto__c), 0), 0)
 */
export function calcularValorKg(kgReclamados, totalConRappel, pesoNeto) {
    const peso = num(pesoNeto);
    return peso > 0 ? redondear(num(kgReclamados) * (num(totalConRappel) / peso)) : 0;
}

/**
 * Caja: IF(Cantidad__c > 0, ROUND(Cantidad_Reclamada_1 * (Total_con_Rapel__c / Cantidad__c), 0), 0)
 */
export function calcularValorCaja(cajasReclamadas, totalConRappel, cantidad) {
    const cant = num(cantidad);
    return cant > 0 ? redondear(num(cajasReclamadas) * (num(totalConRappel) / cant)) : 0;
}

/**
 * Unidad: IF(AND(Cantidad_Unidad__c > 0, Valor_Neto__c > 0),
 *            ROUND((Valor_Neto__c / Cantidad_Unidad__c) * Cantidad_de_unidades_reclamadas, 0), 0)
 */
export function calcularValorUnidad(unidadesReclamadas, valorNeto, cantidadUnidad) {
    const unidades = num(cantidadUnidad);
    const neto = num(valorNeto);
    return unidades > 0 && neto > 0 ? redondear((neto / unidades) * num(unidadesReclamadas)) : 0;
}

/** Cantidad_Unidad__c = Cantidad__c * Conversion_UM__c (blancos como cero). */
export function calcularCantidadUnidad(cantidad, conversionUM) {
    return num(cantidad) * num(conversionUM);
}

/** true si el valor fue ingresado (no vacío). */
export function tieneValor(valor) {
    return valor !== null && valor !== undefined && valor !== '';
}

/**
 * Códigos de Detalle_Factura__c.Unidad_de_Medida__c (texto libre, máx. 5) agrupados por fórmula.
 * Se comparan en mayúsculas y sin espacios/puntos.
 */
const CODIGOS_UM = Object.freeze({
    KG: ['KG', 'KGS', 'KGR', 'KILO', 'KILOS', 'K'],
    CAJA: ['CA', 'CJ', 'CJA', 'CAJ', 'CAJA', 'CAJAS', 'CS', 'BOX', 'BX'],
    UNIDAD: ['UN', 'UND', 'UNI', 'UNID', 'U', 'UNIDA', 'ST', 'PZA', 'PZ', 'EA', 'PC', 'PCS']
});

/** Sub-input de la fila que corresponde a cada tipo de UM. */
export const CAMPO_POR_TIPO = Object.freeze({
    [TIPO_UM.KG]: 'kg',
    [TIPO_UM.CAJA]: 'cajas',
    [TIPO_UM.UNIDAD]: 'unidades'
});

/**
 * Tipo de cálculo según la Unidad de Medida del producto:
 *   KG     → fórmula KG    (sub-input Peso neto)
 *   Caja   → fórmula Caja  (sub-input Cantidad)
 *   Unidad → fórmula Unidad (sub-input Cantidad unidad)
 * Devuelve '' si la UM viene vacía o no se reconoce.
 */
export function tipoUMPorUnidadMedida(unidadMedida) {
    const codigo = String(unidadMedida || '')
        .toUpperCase()
        .replace(/[\s.]/g, '');
    if (!codigo) {
        return '';
    }
    if (CODIGOS_UM.KG.includes(codigo)) {
        return TIPO_UM.KG;
    }
    if (CODIGOS_UM.CAJA.includes(codigo)) {
        return TIPO_UM.CAJA;
    }
    if (CODIGOS_UM.UNIDAD.includes(codigo)) {
        return TIPO_UM.UNIDAD;
    }
    return '';
}

/** Sub-input habilitado por la UM del producto ('kg' | 'cajas' | 'unidades'), o '' si la UM no se reconoce. */
export function campoPorUnidadMedida(unidadMedida) {
    return CAMPO_POR_TIPO[tipoUMPorUnidadMedida(unidadMedida)] || '';
}

function validarCantidad(valor, maximo, entero, nombreMaximo) {
    if (!Number.isFinite(valor) || valor <= 0) {
        return 'debe ser mayor a 0.';
    }
    if (entero && !Number.isInteger(valor)) {
        return 'solo se permiten números enteros.';
    }
    if (valor > maximo) {
        return `no puede superar ${nombreMaximo} de la fila (${maximo}).`;
    }
    return '';
}

/** Campos de ingreso de la sub-fila, en orden de prioridad si (por estado antiguo) hubiera más de uno. */
export const CAMPOS_INGRESO = Object.freeze(['cajas', 'kg', 'unidades']);

/** Devuelve el campo de ingreso que tiene valor ('cajas' | 'kg' | 'unidades') o '' si ninguno. */
export function campoIngresado(estado) {
    return CAMPOS_INGRESO.find((c) => tieneValor(estado?.[c])) || '';
}

const NOMBRE_CAMPO = Object.freeze({ cajas: 'Cantidad', kg: 'Peso neto', unidades: 'Cantidad unidad' });

/**
 * Calcula el reclamo de una fila seleccionada.
 * La Unidad de Medida del producto define el único sub-input habilitado y su fórmula:
 *   UM Caja   → Cantidad        (cajas)    → ROUND(cajas × Total_con_Rapel / Cantidad)
 *   UM KG     → Peso neto       (kg)       → ROUND(kg × Total_con_Rapel / Peso_neto)
 *   UM Unidad → Cantidad unidad (unidades) → ROUND(Valor_Neto / Cantidad_Unidad × unidades)
 * Si la UM no se reconoce, los tres sub-inputs quedan disponibles (excluyentes) y el usado define la fórmula.
 *
 * @param fila   { unidadMedida, cantidad, pesoNeto, cantidadUnidad, valorNeto, totalConRappel }
 * @param estado { kg, cajas, unidades } (strings tal como vienen de los inputs)
 * @returns { tipoUM, tipoCalculo, campoUM, cantidad, valor, kg, cajas, unidades, error }
 *          tipoUM queda vacío si no se ingresó la cantidad.
 */
export function calcularReclamoFila(fila, estado) {
    const campoUM = campoPorUnidadMedida(fila?.unidadMedida);
    // Con UM reconocida solo cuenta el sub-input de esa UM (se ignora cualquier valor de otra columna)
    const permitido = (c) => !campoUM || campoUM === c;
    const valor = (c) => (permitido(c) && tieneValor(estado?.[c]) ? Number(estado[c]) : null);
    const kg = valor('kg');
    const cajas = valor('cajas');
    const unidades = valor('unidades');
    const resultado = { tipoUM: '', tipoCalculo: '', campoUM, cantidad: 0, valor: 0, kg, cajas, unidades, error: '' };
    const campo = campoUM ? (tieneValor(estado?.[campoUM]) ? campoUM : '') : campoIngresado(estado);

    switch (campo) {
        case 'cajas':
            resultado.tipoUM = TIPO_UM.CAJA;
            resultado.cantidad = cajas;
            resultado.valor = calcularValorCaja(cajas, fila.totalConRappel, fila.cantidad);
            resultado.error = prefijo('Cantidad', validarCantidad(cajas, num(fila.cantidad), true, 'la cantidad'));
            break;
        case 'kg':
            resultado.tipoUM = TIPO_UM.KG;
            resultado.cantidad = kg;
            resultado.valor = calcularValorKg(kg, fila.totalConRappel, fila.pesoNeto);
            resultado.error = prefijo('Peso neto', validarCantidad(kg, num(fila.pesoNeto), false, 'el peso neto'));
            break;
        case 'unidades':
            resultado.tipoUM = TIPO_UM.UNIDAD;
            resultado.cantidad = unidades;
            resultado.valor = calcularValorUnidad(unidades, fila.valorNeto, fila.cantidadUnidad);
            resultado.error = prefijo(
                'Cantidad unidad',
                validarCantidad(unidades, num(fila.cantidadUnidad), true, 'la cantidad unidad')
            );
            break;
        default:
            resultado.error = campoUM
                ? `Ingrese la cantidad reclamada en ${NOMBRE_CAMPO[campoUM]} (UM ${fila.unidadMedida}).`
                : 'Ingrese la cantidad reclamada en Cantidad, Peso neto o Cantidad unidad.';
    }
    resultado.tipoCalculo = resultado.tipoUM;
    return resultado;
}

function prefijo(campo, error) {
    return error ? `${campo}: ${error}` : '';
}