/**
 * Construye el JSON de cabecera + detalle para el envío del contrato de comodato
 * firmado a SAP (ZBI_COMODATO_SF). Reutiliza el mismo query de Comodato__c que
 * ComodatoPropuestaController.loadData() usa para armar el PDF, para que el JSON
 * enviado a SAP y el contenido del PDF nunca diverjan por diferencias de consulta.
 *
 * Decisiones de negocio (2026-07-23, ver docs/MEMORIA_INTEGRACION_SAP_COMODATO_FIRMADO.md):
 *   - TipoSku: Insumo Mensual -> MatConsumo; Aporte de Marca/Merchandising/Servicio -> MatPOP.
 *   - TipoSku de la línea máquina es la constante 'Maquinas' (TextoCategoria__c NO sirve,
 *     valores reales en PROD son '593 MAQUINAS Y REPUESTOS' / '273 ...' / '200 FS-...').
 *   - Kunwe en TODAS las líneas = Account.Cliente_Despacho__c.
 *   - Sin snapshot inmutable: se lee Comodato__c en vivo al momento del envío.
 *
 * Pendiente de confirmar con SAP (no bloquea esta clase, sí bloquea el deploy final):
 *   - Tabla real de Meins por Unidad_de_Medida__c (hoy placeholder).
 *   - Si SAP acepta Cantidad en líneas MatPOP.
 *   - Si SAP reconoce códigos GEN-* como Matnr.
 */
public with sharing class ICB_ComodatoSapPayloadBuilder {

    public class ValidationException extends Exception {}

    public static Map<String, Object> build(Id contratoDigitalId) {
        Contrato_Digital__c cd = queryContrato(contratoDigitalId);
        if (cd == null) {
            throw new ValidationException('Contrato_Digital__c no encontrado: ' + contratoDigitalId);
        }
        if (cd.Presupuesto__c == null) {
            throw new ValidationException('El Contrato Digital no tiene Presupuesto (Quote) asociado.');
        }
        if (cd.Oportunidad__r?.Account == null) {
            throw new ValidationException('No se pudo resolver Oportunidad -> Account.');
        }
        if (cd.Fecha_Firma__c == null) {
            throw new ValidationException('Contrato_Digital__c sin Fecha_Firma__c: no se puede enviar antes de firmar.');
        }
        if (String.isBlank(cd.PDF_Firmado_URL__c)) {
            throw new ValidationException('Contrato_Digital__c sin PDF_Firmado_URL__c.');
        }

        List<QuoteLineItem> quoteLines = [
            SELECT Product2Id, Product2.Name, Product2.Codigo__c, Product2.Precio_de_Lista__c, Quantity, UMV__c
            FROM QuoteLineItem
            WHERE QuoteId = :cd.Presupuesto__c
        ];
        if (quoteLines.isEmpty()) {
            throw new ValidationException('El Presupuesto (Quote) no tiene QuoteLineItems.');
        }

        String cliente = cd.Oportunidad__r.Account.C_digo_de_cliente__c;
        String kunwe = cd.Oportunidad__r.Account.Cliente_Despacho__c;
        if (String.isBlank(cliente)) {
            throw new ValidationException('Account sin C_digo_de_cliente__c.');
        }
        if (String.isBlank(kunwe)) {
            throw new ValidationException('Account sin Cliente_Despacho__c (requerido para Kunwe en todas las líneas).');
        }

        String contrato = stripPrefijoFD(cd.Contrato_ID__c);
        if (String.isBlank(contrato)) {
            throw new ValidationException('Contrato_ID__c vacío o con formato inesperado: ' + cd.Contrato_ID__c);
        }

        Map<Id, QuoteLineItem> qliByProduct = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem qli : quoteLines) {
            qliByProduct.put(qli.Product2Id, qli);
        }

        // Identificar máquina(s): producto de la Quote que aparece como Maquina__c en Comodato__c.
        // (Al momento de la firma ya no existe la variable de Flow varSelectedMachineId;
        //  esta es la forma correcta de re-derivarla — ver sección 4.2 de la memoria.)
        Set<Id> machineIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Maquina__c mid
            FROM Comodato__c
            WHERE Maquina__c IN :qliByProduct.keySet()
            GROUP BY Maquina__c
        ]) {
            machineIds.add((Id) ar.get('mid'));
        }
        if (machineIds.isEmpty()) {
            throw new ValidationException('Ninguna máquina de la Quote tiene configuraciones Comodato__c asociadas.');
        }

        List<Object> detalle = new List<Object>();

        Map<Id, Decimal> valorPorMaquina = resolverValorEquipos(machineIds);

        for (Id machineId : machineIds) {
            QuoteLineItem machineLine = qliByProduct.get(machineId);
            Decimal valor = valorPorMaquina.get(machineId);
            if (valor == null) {
                throw new ValidationException(
                    'Sin valor para la máquina ' + machineLine.Product2.Name +
                    ' (' + machineLine.Product2.Id + '): no tiene precio en la lista ' +
                    LISTA_VALOR_EQUIPOS + ' ni en Product2.Precio_de_Lista__c. ' +
                    'Cargar el precio antes de enviar a SAP.'
                );
            }
            if (String.isBlank(machineLine.Product2.Codigo__c)) {
                throw new ValidationException('Máquina sin Codigo__c: ' + machineLine.Product2.Name);
            }

            detalle.add(new Map<String, Object>{
                'Bukrs' => 'SFSL',
                'Contrato' => contrato,
                'Anexo' => '0',
                'TipoSku' => 'Maquinas',
                'Matnr' => machineLine.Product2.Codigo__c,
                'MatnrCambio' => '',
                'Cantidad' => String.valueOf(machineLine.Quantity),
                'Meins' => mapUnidadSAP(machineLine.UMV__c),
                'Valor' => String.valueOf(valor.setScale(0)),
                'Waers' => 'CLP',
                'ConsumoMinimo' => String.valueOf(machineLine.Quantity),
                'PrecioVtaAcordado' => '',
                'Kunwe' => kunwe
            });

            // Lineas YA RESUELTAS contra la Quote del contrato: si hubo un ajuste excepcional,
            // SAP recibe exactamente los mismos valores que el PDF y el contrato firmado.
            for (ComodatoOverrideResolver.LineaResuelta c :
                    ComodatoOverrideResolver.resolver(new Set<Id>{ machineId }, cd.Presupuesto__c)) {
                if (c.productoAsociadoId == null || c.tipoDeAsociacion == 'Servicio') {
                    continue;
                }
                if (String.isBlank(c.productoAsociadoCodigo)) {
                    throw new ValidationException('Producto asociado sin Codigo__c: ' + c.productoAsociadoNombre);
                }

                String tipoSku = mapTipoSku(c.tipoDeAsociacion);
                Boolean esConsumo = tipoSku == 'MatConsumo';

                // Una cantidad vacia en un insumo mensual no es un dato faltante: son las
                // variedades alternativas. En PROD, 12 de los 47 insumos mensuales estan asi
                // --por ejemplo la S2 EK 2G compromete 24 kg de CREMA Y AROMA y habilita
                // TIERRA SEL y ORGANICO sin cantidad propia--. Se informan con cantidad 0:
                // el insumo esta autorizado para el equipo, sin compromiso propio.
                Decimal cantidadMensual = c.cantidadMinimaMensual != null ? c.cantidadMinimaMensual : 0;

                detalle.add(new Map<String, Object>{
                    'Bukrs' => 'SFSL',
                    'Contrato' => contrato,
                    'Anexo' => '0',
                    'TipoSku' => tipoSku,
                    'Matnr' => c.productoAsociadoCodigo,
                    'MatnrCambio' => '',
                    'Cantidad' => esConsumo ? String.valueOf(cantidadMensual) : String.valueOf(c.cantidadAporte != null ? c.cantidadAporte : 0),
                    'Meins' => mapUnidadSAP(c.unidadDeMedida),
                    'Valor' => '',
                    'Waers' => 'CLP',
                    'ConsumoMinimo' => esConsumo ? String.valueOf(cantidadMensual) : '',
                    'PrecioVtaAcordado' => esConsumo ? String.valueOf(c.precioUnitarioNeto != null ? c.precioUnitarioNeto : 0) : '',
                    'Kunwe' => kunwe
                });
            }
        }

        return new Map<String, Object>{
            'Bukrs' => 'SFSL',
            'Contrato' => contrato,
            'Anexo' => '0',
            'Accion' => '01',
            'FechaContrato' => formatFecha(cd.Fecha_Firma__c),
            'Cliente' => cliente,
            'FechaInicio' => '',
            'FechaFinal' => '',
            'Url' => String.isNotBlank(cd.PDF_Original_URL__c) ? cd.PDF_Original_URL__c : cd.PDF_Firmado_URL__c,
            'UrlFirma' => cd.PDF_Firmado_URL__c,
            'AfComodatoDetSet' => consolidarParaSap(detalle)
        };
    }

    /**
     * Consolida el detalle antes de enviarlo a SAP.
     *
     * SAP identifica cada linea por (Bukrs, Contrato, Anexo, TipoSku, Matnr) --lo dice el
     * __metadata.id que devuelve-- y el Anexo va fijo en 0. La maquina no forma parte de la
     * clave, asi que cuando varias comparten un material SAP se queda con la ultima linea
     * recibida y descarta las demas. En un contrato de 4 maquinas se enviaron 44 lineas que
     * colapsaron en 15: las 12+12+12+20+18 tazas quedaron en 18.
     *
     * Solo las maquinas se suman: 5 equipos del mismo modelo viajan como una linea de 5. Los
     * insumos y los aportes no se acumulan por equipo, asi que de las lineas repetidas se
     * conserva la cantidad mayor: quedar en la menor dejaria al contrato por debajo de lo que
     * compromete el equipo mas exigente.
     *
     * Los precios son unitarios y no se tocan.
     *
     * Solo afecta el envio a SAP: la propuesta, el PDF y el contrato siguen mostrando el
     * detalle por maquina.
     */
    private static List<Object> consolidarParaSap(List<Object> detalle) {
        Map<String, Map<String, Object>> porClave = new Map<String, Map<String, Object>>();
        List<String> orden = new List<String>();

        for (Object o : detalle) {
            Map<String, Object> linea = (Map<String, Object>) o;
            String tipoSku = String.valueOf(linea.get('TipoSku'));
            String clave = tipoSku + '|' + linea.get('Matnr');

            if (!porClave.containsKey(clave)) {
                porClave.put(clave, linea);
                orden.add(clave);
                continue;
            }

            Map<String, Object> acum = porClave.get(clave);

            // Unidades distintas para el mismo material: sumar seria mezclar magnitudes. Es un
            // dato inconsistente que hay que corregir antes de informar a SAP.
            if (String.valueOf(acum.get('Meins')) != String.valueOf(linea.get('Meins'))) {
                throw new ValidationException(
                    'El material ' + linea.get('Matnr') + ' viene con dos unidades distintas ('
                    + acum.get('Meins') + ' y ' + linea.get('Meins') + '). '
                    + 'Corregir Unidad_de_Medida__c en las configuraciones de Comodato antes de enviar.'
                );
            }

            if (tipoSku == 'Maquinas') {
                acum.put('Cantidad', sumar(acum.get('Cantidad'), linea.get('Cantidad')));
                acum.put('ConsumoMinimo', sumar(acum.get('ConsumoMinimo'), linea.get('ConsumoMinimo')));
            } else {
                acum.put('Cantidad', mayor(acum.get('Cantidad'), linea.get('Cantidad')));
                acum.put('ConsumoMinimo', mayor(acum.get('ConsumoMinimo'), linea.get('ConsumoMinimo')));
            }
        }

        List<Object> salida = new List<Object>();
        for (String clave : orden) {
            salida.add(porClave.get(clave));
        }
        return salida;
    }

    /** Suma dos cantidades del payload, que viajan como texto. Vacio + vacio se queda vacio. */
    private static String sumar(Object a, Object b) {
        Decimal da = aDecimal(a);
        Decimal db = aDecimal(b);
        if (da == null && db == null) {
            return '';
        }
        return String.valueOf((da == null ? 0 : da) + (db == null ? 0 : db));
    }

    /** La mayor de dos cantidades, para lo que no se suma. */
    private static String mayor(Object a, Object b) {
        Decimal da = aDecimal(a);
        Decimal db = aDecimal(b);
        if (da == null && db == null) {
            return '';
        }
        if (da == null) return String.valueOf(db);
        if (db == null) return String.valueOf(da);
        return String.valueOf(da >= db ? da : db);
    }

    private static Decimal aDecimal(Object v) {
        String s = v == null ? '' : String.valueOf(v);
        return String.isBlank(s) ? null : Decimal.valueOf(s);
    }

    @TestVisible
    private static Contrato_Digital__c queryContrato(Id contratoDigitalId) {
        List<Contrato_Digital__c> recs = [
            SELECT Id, Contrato_ID__c, Estado__c, Fecha_Firma__c, PDF_Original_URL__c, PDF_Firmado_URL__c,
                   Oportunidad__c, Oportunidad__r.Account.C_digo_de_cliente__c, Oportunidad__r.Account.Cliente_Despacho__c,
                   Presupuesto__c
            FROM Contrato_Digital__c
            WHERE Id = :contratoDigitalId
            LIMIT 1
        ];
        return recs.isEmpty() ? null : recs[0];
    }

    // TODO: confirmar con SAP si además de quitar el prefijo hay que normalizar largo.
    // Hoy el campo fórmula descrito en la memoria (sección 0) NO existe aún en Contrato_Digital__c;
    // esta función es el equivalente en Apex mientras no se cree ese campo.
    @TestVisible
    private static String stripPrefijoFD(String contratoId) {
        if (String.isBlank(contratoId)) return '';
        return contratoId.startsWith('FD-') ? contratoId.substring(3) : contratoId;
    }

    @TestVisible
    private static String mapTipoSku(String tipoAsociacion) {
        if (tipoAsociacion == 'Insumo Mensual') return 'MatConsumo';
        // Servicio se excluye antes de llegar acá (ver query en build()); Aporte de Marca /
        // Merchandising -> MatPOP.
        return 'MatPOP';
    }

    // TODO BLOQUEANTE: tabla real de códigos SAP de unidad de medida (Meins) pendiente de confirmar.
    // Placeholder basado en los 4 valores del picklist Unidad_de_Medida__c.
    @TestVisible
    private static String mapUnidadSAP(String unidadSf) {
        if (unidadSf == null) return 'UN';
        Map<String, String> mapa = new Map<String, String>{
            'Kilos' => 'KG',
            'Cajas' => 'CJ',
            'Unidades' => 'UN',
            'Litros' => 'LT'
        };
        return mapa.containsKey(unidadSf) ? mapa.get(unidadSf) : 'UN';
    }

    private static String formatFecha(Datetime dt) {
        if (dt == null) return '';
        return dt.format('yyyyMMdd');
    }

    /** Lista de precios de donde sale el valor del equipo que se informa a SAP. */
    private static final String LISTA_VALOR_EQUIPOS = 'COMODATO';

    /**
     * Valor a informar a SAP por cada equipo.
     *
     * La fuente es el precio de la lista COMODATO, que es donde el equipo mantiene el valor de
     * los equipos. Product2.Precio_de_Lista__c queda solo como respaldo: esta vacio en 27 de los
     * 31 equipos activos y en algunos productos arrastra valores de prueba, asi que depender de
     * el hacia fallar el envio.
     *
     * Devuelve solo los equipos con valor. Los que no lo tengan quedan fuera del mapa para que
     * quien llama pueda avisar con el nombre del equipo en vez de mandar un cero silencioso.
     */
    private static Map<Id, Decimal> resolverValorEquipos(Set<Id> equipoIds) {
        Map<Id, Decimal> valores = new Map<Id, Decimal>();
        if (equipoIds == null || equipoIds.isEmpty()) {
            return valores;
        }

        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :equipoIds
              AND Pricebook2.Name = :LISTA_VALOR_EQUIPOS
              AND IsActive = true
              AND UnitPrice > 0
        ]) {
            valores.put(pbe.Product2Id, pbe.UnitPrice);
        }

        // Respaldo para los que la lista no cubre.
        for (Product2 p : [
            SELECT Id, Precio_de_Lista__c FROM Product2
            WHERE Id IN :equipoIds AND Precio_de_Lista__c != null AND Precio_de_Lista__c > 0
        ]) {
            if (!valores.containsKey(p.Id)) {
                valores.put(p.Id, p.Precio_de_Lista__c);
            }
        }
        return valores;
    }
}